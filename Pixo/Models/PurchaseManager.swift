//
//  PurchaseManager.swift
//  Pixo
//
//  Created by Eric Cai on 2025/9/19.
//

import Foundation
import Combine
import StoreKit

/// 购买与试用状态
enum PurchaseState: Equatable {
  case unknown
  case trial(endDate: Date)
  case trialExpired(endDate: Date)
  case purchased(purchaseDate: Date, transactionID: String?)
}

enum PurchaseManagerError: LocalizedError {
  case productUnavailable
  case failedVerification
  case purchaseCancelled
  case purchasePending
  case restoreFailed
  case unknown(Error)

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return "purchase_error_product_unavailable".localized
    case .failedVerification:
      return "purchase_error_failed_verification".localized
    case .purchaseCancelled:
      return "purchase_error_cancelled".localized
    case .purchasePending:
      return "purchase_error_pending".localized
    case .restoreFailed:
      return "purchase_error_restore_failed".localized
    case .unknown(let error):
      return error.localizedDescription
    }
  }

  var shouldSuppressAlert: Bool {
    if case .purchaseCancelled = self {
      return true
    }
    return false
  }
}

/// 负责管理应用的购买状态与试用逻辑
final class PurchaseManager: ObservableObject {
  @Published private(set) var state: PurchaseState = .unknown
  @Published private(set) var isTrialBannerDismissed: Bool
  @Published private(set) var availableProduct: Product?

  private let userDefaults: UserDefaults
  private let trialDuration: TimeInterval
  private let productIdentifier: String
  private let keychainPolicy: KeychainHelper.AccessPolicy
  private var updatesTask: Task<Void, Never>?

  private enum StorageKey {
    static let trialStartDate = "purchase.trialStartDate"
    static let trialEndDate = "purchase.trialEndDate"
    static let purchaseDate = "purchase.purchaseDate"
    static let transactionID = "purchase.transactionID"
    static let trialBannerDismissed = "purchase.trialBannerDismissed"
  }

  private enum KeychainKey {
    static var service: String {
      let base = Bundle.main.bundleIdentifier ?? "com.pixo.app"
      return base + ".purchase"
    }
    static let licenseAccount = "full-access"
  }

  init(
    trialDays: Int = 7,
    userDefaults: UserDefaults = .standard,
    productIdentifier: String = "com.suyotube.pixo.full"
  ) {
    self.trialDuration = TimeInterval(trialDays * 24 * 60 * 60)
    self.userDefaults = userDefaults
    self.productIdentifier = productIdentifier
    self.keychainPolicy = .userPresence(prompt: "purchase_keychain_prompt".localized)
    self.isTrialBannerDismissed = userDefaults.bool(forKey: StorageKey.trialBannerDismissed)

    if let cachedPurchase = loadPurchaseFromKeychain() {
      state = .purchased(purchaseDate: cachedPurchase.purchaseDate, transactionID: cachedPurchase.transactionID)
    } else {
      refreshEntitlements()
    }

    updatesTask = Task(priority: .background) { [weak self] in
      guard let self = self else { return }
      await self.listenForTransactions()
    }

    Task { @MainActor in
      await loadProduct()
      await syncCurrentEntitlements()
    }
  }

  deinit {
    updatesTask?.cancel()
  }

  /// 当前是否具备完整版权限（试用期或已购买）
  var isEntitled: Bool {
    switch state {
    case .trial, .purchased:
      return true
    case .unknown, .trialExpired:
      return false
    }
  }

  /// 是否已过试用期
  var isTrialExpired: Bool {
    if case .trialExpired = state { return true }
    return false
  }

  /// 重新评估当前的权益状态
  func refreshEntitlements(currentDate: Date = Date()) {
    defer { restoreBannerVisibilityIfNeeded() }

    if let purchaseDate = userDefaults.object(forKey: StorageKey.purchaseDate) as? Date {
      let transactionID = userDefaults.string(forKey: StorageKey.transactionID)
      state = .purchased(purchaseDate: purchaseDate, transactionID: transactionID)
      return
    }

    if let trialEnd = userDefaults.object(forKey: StorageKey.trialEndDate) as? Date {
      if currentDate < trialEnd {
        state = .trial(endDate: trialEnd)
      } else {
        state = .trialExpired(endDate: trialEnd)
      }
      return
    }

    startTrial(from: currentDate)
  }

  /// 如果当前状态是试用期或试用期过期，且用户之前关闭了试用提示，则恢复显示
  private func restoreBannerVisibilityIfNeeded() {
    switch state {
    case .trial, .trialExpired:
      if isTrialBannerDismissed {
        isTrialBannerDismissed = false
        userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
      }
    case .unknown, .purchased:
      break
    }
  }

  /// 标记购买成功（后续步骤会从 StoreKit 调用）
  func recordPurchase(date: Date = Date(), transactionID: String?) {
    userDefaults.set(date, forKey: StorageKey.purchaseDate)
    userDefaults.set(transactionID, forKey: StorageKey.transactionID)
    userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = true
    state = .purchased(purchaseDate: date, transactionID: transactionID)

    let cached = CachedPurchase(transactionID: transactionID, purchaseDate: date)
    savePurchaseToKeychain(cached)
  }

  func revokePurchase() {
    userDefaults.removeObject(forKey: StorageKey.purchaseDate)
    userDefaults.removeObject(forKey: StorageKey.transactionID)
    clearKeychainPurchase()
    refreshEntitlements()
  }

  @MainActor
  func purchaseFullVersion() async throws {
    if availableProduct == nil {
      await loadProduct()
    }

    guard let product = availableProduct else {
      throw PurchaseManagerError.productUnavailable
    }

    let result: Product.PurchaseResult
    do {
      result = try await product.purchase()
    } catch {
      throw PurchaseManagerError.unknown(error)
    }

    switch result {
    case .success(let verificationResult):
      let transaction = try checkVerified(verificationResult)
      await handle(transaction: transaction, shouldFinish: true)
    case .userCancelled:
      throw PurchaseManagerError.purchaseCancelled
    case .pending:
      throw PurchaseManagerError.purchasePending
    @unknown default:
      let message = "purchase_error_unknown_result".localized
      let error = NSError(domain: "com.pixo.purchase", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
      throw PurchaseManagerError.unknown(error)
    }
  }

  @MainActor
  func restorePurchases() async throws {
    do {
      try await AppStore.sync()
      await syncCurrentEntitlements()
    } catch {
      throw PurchaseManagerError.restoreFailed
    }
  }

  /// 用户主动关闭试用提示
  func dismissTrialBanner() {
    guard !isTrialBannerDismissed else { return }
    isTrialBannerDismissed = true
    userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
  }

  private func startTrial(from date: Date) {
    let trialEnd = date.addingTimeInterval(trialDuration)
    userDefaults.set(date, forKey: StorageKey.trialStartDate)
    userDefaults.set(trialEnd, forKey: StorageKey.trialEndDate)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    state = .trial(endDate: trialEnd)
  }

  @MainActor
  private func loadProduct() async {
    do {
      let products = try await Product.products(for: [productIdentifier])
      availableProduct = products.first
    } catch {
      #if DEBUG
      print("Product fetch error: \(error)")
      #endif
      availableProduct = nil
    }
  }

  @MainActor
  private func syncCurrentEntitlements() async {
    var hasActiveEntitlement = false
    for await result in Transaction.currentEntitlements {
      guard let transaction = try? checkVerified(result) else { continue }
      guard transaction.productID == productIdentifier else { continue }

      hasActiveEntitlement = true
      await handle(transaction: transaction, shouldFinish: false)
    }

    if !hasActiveEntitlement, loadPurchaseFromKeychain() == nil {
      refreshEntitlements()
    }
  }

  private func listenForTransactions() async {
    for await update in Transaction.updates {
      guard let transaction = try? checkVerified(update) else { continue }
      guard transaction.productID == productIdentifier else { continue }

      await handle(transaction: transaction, shouldFinish: true)
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let safe):
      return safe
    case .unverified:
      throw PurchaseManagerError.failedVerification
    }
  }

  @MainActor
  private func handle(transaction: Transaction, shouldFinish: Bool) async {
    if transaction.revocationDate != nil {
      revokePurchase()
    } else {
      recordPurchase(date: transaction.purchaseDate, transactionID: String(transaction.id))
    }

    if shouldFinish {
      await transaction.finish()
    }
  }

  private func savePurchaseToKeychain(_ purchase: CachedPurchase) {
    do {
      let data = try JSONEncoder().encode(purchase)
      try KeychainHelper.save(
        data: data,
        service: KeychainKey.service,
        account: KeychainKey.licenseAccount,
        policy: keychainPolicy
      )
    } catch {
      // 保底策略：忽略钥匙串错误，但保持日志便于调试
      #if DEBUG
      print("Keychain save error: \(error)")
      #endif
    }
  }

  private func loadPurchaseFromKeychain() -> CachedPurchase? {
    do {
      guard let data = try KeychainHelper.load(
        service: KeychainKey.service,
        account: KeychainKey.licenseAccount,
        policy: keychainPolicy
      ) else {
        return nil
      }
      return try JSONDecoder().decode(CachedPurchase.self, from: data)
    } catch let error as KeychainError {
      if case .authenticationFailed = error {
        #if DEBUG
        print("Keychain auth cancelled: \(error.localizedDescription)")
        #endif
        return nil
      }
      #if DEBUG
      print("Keychain load error: \(error.localizedDescription)")
      #endif
      return nil
    } catch {
      #if DEBUG
      print("Keychain load error: \(error)")
      #endif
      return nil
    }
  }

  private func clearKeychainPurchase() {
    do {
      try KeychainHelper.delete(service: KeychainKey.service, account: KeychainKey.licenseAccount)
    } catch {
      #if DEBUG
      print("Keychain delete error: \(error)")
      #endif
    }
  }

  private struct CachedPurchase: Codable {
    let transactionID: String?
    let purchaseDate: Date
  }

  #if DEBUG
  /// 测试辅助：重置本地状态
  func resetLocalState() {
    userDefaults.removeObject(forKey: StorageKey.trialStartDate)
    userDefaults.removeObject(forKey: StorageKey.trialEndDate)
    userDefaults.removeObject(forKey: StorageKey.purchaseDate)
    userDefaults.removeObject(forKey: StorageKey.transactionID)
    userDefaults.removeObject(forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    state = .unknown
    refreshEntitlements()
  }

  /// 测试辅助：强制将试用期置为已过期，便于调试 UI
  func simulateTrialExpiration(referenceDate: Date = Date()) {
    let trialEnd = referenceDate.addingTimeInterval(-60)
    let trialStart = trialEnd.addingTimeInterval(-trialDuration)
    userDefaults.set(trialStart, forKey: StorageKey.trialStartDate)
    userDefaults.set(trialEnd, forKey: StorageKey.trialEndDate)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    refreshEntitlements(currentDate: referenceDate)
    restoreBannerVisibilityIfNeeded()
  }
  #endif
}
