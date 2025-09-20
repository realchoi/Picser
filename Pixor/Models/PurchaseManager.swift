//
//  PurchaseManager.swift
//  Pixor
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
  private let silentKeychainPolicy: KeychainHelper.AccessPolicy = .standard
  private let clockSkewTolerance: TimeInterval = 5 * 60
  private let isReceiptValidationEnabled: Bool
  private let sharedSecret: String?
  private let receiptValidator: ReceiptValidator?
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
      let base = Bundle.main.bundleIdentifier ?? "com.soyotube.Pixor"
      return base + ".purchase"
    }
    static let licenseAccount = "full-access"
  }

  init(
    trialDays: Int = 7,
    userDefaults: UserDefaults = .standard,
    productIdentifier: String = SecretsProvider.defaultProductIdentifier,
    enableReceiptValidation: Bool = false,
    sharedSecret: String? = nil,
    receiptValidator: ReceiptValidator? = nil
  ) {
    self.trialDuration = TimeInterval(trialDays * 24 * 60 * 60)
    self.userDefaults = userDefaults
    self.productIdentifier = productIdentifier
    self.isTrialBannerDismissed = userDefaults.bool(forKey: StorageKey.trialBannerDismissed)
    self.isReceiptValidationEnabled = enableReceiptValidation
    self.sharedSecret = sharedSecret
    if enableReceiptValidation {
      self.receiptValidator = receiptValidator ?? ReceiptValidator()
    } else {
      self.receiptValidator = nil
    }

    refreshEntitlements()

    updatesTask = Task(priority: .background) { [weak self] in
      guard let self = self else { return }
      await self.listenForTransactions()
    }

    Task { @MainActor in
      await loadProduct()
      await syncCurrentEntitlements()
      await validateReceiptIfNeeded()
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

    if var cached = loadEntitlementFromKeychain() {
      if isClockRollbackDetected(currentDate: currentDate, cachedTimestamp: cached.lastUpdated) {
        let fallbackEnd = cached.trialEndDate ?? cached.lastUpdated
        let fallbackStart = cached.trialStartDate ?? fallbackEnd
        userDefaults.set(fallbackStart, forKey: StorageKey.trialStartDate)
        userDefaults.set(fallbackEnd, forKey: StorageKey.trialEndDate)
        userDefaults.removeObject(forKey: StorageKey.purchaseDate)
        userDefaults.removeObject(forKey: StorageKey.transactionID)
        state = .trialExpired(endDate: fallbackEnd)
        saveEntitlementToKeychain(cached)
        return
      }

      if let purchaseDate = cached.purchaseDate {
        let transactionID = cached.transactionID
        userDefaults.set(purchaseDate, forKey: StorageKey.purchaseDate)
        if let transactionID {
          userDefaults.set(transactionID, forKey: StorageKey.transactionID)
        } else {
          userDefaults.removeObject(forKey: StorageKey.transactionID)
        }
        userDefaults.removeObject(forKey: StorageKey.trialStartDate)
        userDefaults.removeObject(forKey: StorageKey.trialEndDate)
        state = .purchased(purchaseDate: purchaseDate, transactionID: transactionID)
        cached.lastUpdated = currentDate
        saveEntitlementToKeychain(cached)
        return
      }

      if let trialStart = cached.trialStartDate, let trialEnd = cached.trialEndDate {
        userDefaults.set(trialStart, forKey: StorageKey.trialStartDate)
        userDefaults.set(trialEnd, forKey: StorageKey.trialEndDate)
        state = currentDate < trialEnd ? .trial(endDate: trialEnd) : .trialExpired(endDate: trialEnd)
        cached.lastUpdated = currentDate
        saveEntitlementToKeychain(cached)
        return
      }
    }

    if let purchaseDate = userDefaults.object(forKey: StorageKey.purchaseDate) as? Date {
      let transactionID = userDefaults.string(forKey: StorageKey.transactionID)
      state = .purchased(purchaseDate: purchaseDate, transactionID: transactionID)
      updateKeychainEntitlement { entitlement in
        entitlement.transactionID = transactionID
        entitlement.purchaseDate = purchaseDate
        entitlement.trialStartDate = nil
        entitlement.trialEndDate = nil
      }
      return
    }

    if let trialStart = userDefaults.object(forKey: StorageKey.trialStartDate) as? Date,
       let trialEnd = userDefaults.object(forKey: StorageKey.trialEndDate) as? Date {
      state = currentDate < trialEnd ? .trial(endDate: trialEnd) : .trialExpired(endDate: trialEnd)
      updateKeychainEntitlement { entitlement in
        entitlement.transactionID = nil
        entitlement.purchaseDate = nil
        entitlement.trialStartDate = trialStart
        entitlement.trialEndDate = trialEnd
      }
      return
    }

    startTrial(from: currentDate)
  }

  private func isClockRollbackDetected(currentDate: Date, cachedTimestamp: Date) -> Bool {
    currentDate.addingTimeInterval(clockSkewTolerance) < cachedTimestamp
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
    userDefaults.removeObject(forKey: StorageKey.trialStartDate)
    userDefaults.removeObject(forKey: StorageKey.trialEndDate)
    userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = true
    state = .purchased(purchaseDate: date, transactionID: transactionID)

    updateKeychainEntitlement { entitlement in
      entitlement.transactionID = transactionID
      entitlement.purchaseDate = date
      entitlement.trialStartDate = nil
      entitlement.trialEndDate = nil
    }
  }

  func revokePurchase() {
    userDefaults.removeObject(forKey: StorageKey.purchaseDate)
    userDefaults.removeObject(forKey: StorageKey.transactionID)
    userDefaults.removeObject(forKey: StorageKey.trialStartDate)
    userDefaults.removeObject(forKey: StorageKey.trialEndDate)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false

    updateKeychainEntitlement { entitlement in
      entitlement.transactionID = nil
      entitlement.purchaseDate = nil
      if !entitlement.hasTrial {
        let now = Date()
        entitlement.trialStartDate = now
        entitlement.trialEndDate = now
      }
    }

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
      let error = NSError(domain: "com.soyotube.Pixor.purchase", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
      throw PurchaseManagerError.unknown(error)
    }
  }

  @MainActor
  func restorePurchases() async throws {
    do {
      try await AppStore.sync()
      await syncCurrentEntitlements()
      await validateReceiptIfNeeded()
    } catch {
      if let cached = loadEntitlementFromKeychain(),
         let purchaseDate = cached.purchaseDate {
        recordPurchase(date: purchaseDate, transactionID: cached.transactionID)
        return
      }
      throw PurchaseManagerError.restoreFailed
    }

    if isEntitled {
      return
    }

    if let cached = loadEntitlementFromKeychain(),
       let purchaseDate = cached.purchaseDate {
      recordPurchase(date: purchaseDate, transactionID: cached.transactionID)
    } else {
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

    updateKeychainEntitlement { entitlement in
      entitlement.transactionID = nil
      entitlement.purchaseDate = nil
      entitlement.trialStartDate = date
      entitlement.trialEndDate = trialEnd
    }
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

    if !hasActiveEntitlement {
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

  @MainActor
  private func validateReceiptIfNeeded() async {
    guard isReceiptValidationEnabled, let validator = receiptValidator else { return }

    do {
      guard let result = try await validator.validateReceipt(for: productIdentifier, sharedSecret: sharedSecret) else {
        return
      }

      if case let .purchased(currentDate, currentTransaction) = state,
         currentTransaction == result.transactionID,
         abs(currentDate.timeIntervalSince(result.purchaseDate)) < 1 {
        return
      }

      recordPurchase(date: result.purchaseDate, transactionID: result.transactionID)
    } catch ReceiptValidatorError.missingReceipt {
      #if DEBUG
      print("Receipt validation skipped: missing receipt")
      #endif
    } catch {
      #if DEBUG
      print("Receipt validation error: \(error.localizedDescription)")
      #endif
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
      await validateReceiptIfNeeded()
    }

    if shouldFinish {
      await transaction.finish()
    }
  }

  private func saveEntitlementToKeychain(_ entitlement: CachedEntitlement) {
    var payload = entitlement
    payload.schemaVersion = CachedEntitlement.currentSchemaVersion
    payload.lastUpdated = max(entitlement.lastUpdated, Date())

    do {
      let data = try JSONEncoder().encode(payload)
      try KeychainHelper.save(
        data: data,
        service: KeychainKey.service,
        account: KeychainKey.licenseAccount,
        policy: silentKeychainPolicy
      )
    } catch {
      // 保底策略：忽略钥匙串错误，但保持日志便于调试
      #if DEBUG
      print("Keychain save error: \(error)")
      #endif
    }
  }

  private func updateKeychainEntitlement(_ transform: (inout CachedEntitlement) -> Void) {
    var entitlement = loadEntitlementFromKeychain() ?? CachedEntitlement()
    transform(&entitlement)
    entitlement.lastUpdated = Date()
    saveEntitlementToKeychain(entitlement)
  }

  private func loadEntitlementFromKeychain() -> CachedEntitlement? {
    do {
      if let data = try KeychainHelper.load(
        service: KeychainKey.service,
        account: KeychainKey.licenseAccount,
        policy: silentKeychainPolicy
      ) {
        return try JSONDecoder().decode(CachedEntitlement.self, from: data)
      }
    } catch let error as KeychainError {
      #if DEBUG
      print("Keychain load error: \(error.localizedDescription)")
      #endif
    } catch {
      #if DEBUG
      print("Keychain load error: \(error)")
      #endif
    }

    return nil
  }

  private func clearKeychainEntitlement() {
    do {
      try KeychainHelper.delete(service: KeychainKey.service, account: KeychainKey.licenseAccount)
    } catch {
      #if DEBUG
      print("Keychain delete error: \(error)")
      #endif
    }
  }

  private struct CachedEntitlement: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var transactionID: String?
    var purchaseDate: Date?
    var trialStartDate: Date?
    var trialEndDate: Date?
    var lastUpdated: Date

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case transactionID
      case purchaseDate
      case trialStartDate
      case trialEndDate
      case lastUpdated
    }

    init(
      transactionID: String? = nil,
      purchaseDate: Date? = nil,
      trialStartDate: Date? = nil,
      trialEndDate: Date? = nil,
      lastUpdated: Date = Date(),
      schemaVersion: Int = CachedEntitlement.currentSchemaVersion
    ) {
      self.schemaVersion = schemaVersion
      self.transactionID = transactionID
      self.purchaseDate = purchaseDate
      self.trialStartDate = trialStartDate
      self.trialEndDate = trialEndDate
      self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
      transactionID = try container.decodeIfPresent(String.self, forKey: .transactionID)
      purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
      trialStartDate = try container.decodeIfPresent(Date.self, forKey: .trialStartDate)
      trialEndDate = try container.decodeIfPresent(Date.self, forKey: .trialEndDate)

      if let timestamp = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) {
        lastUpdated = timestamp
      } else if let purchaseDate {
        // 兼容旧版本仅存储购买日期的结构
        lastUpdated = purchaseDate
      } else if let trialEndDate {
        lastUpdated = trialEndDate
      } else {
        lastUpdated = Date()
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(schemaVersion, forKey: .schemaVersion)
      try container.encodeIfPresent(transactionID, forKey: .transactionID)
      try container.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
      try container.encodeIfPresent(trialStartDate, forKey: .trialStartDate)
      try container.encodeIfPresent(trialEndDate, forKey: .trialEndDate)
      try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    var hasPurchase: Bool { purchaseDate != nil }
    var hasTrial: Bool { trialStartDate != nil && trialEndDate != nil }
  }

  #if DEBUG
  /// 测试辅助：重置本地状态
  func resetLocalState() {
    userDefaults.removeObject(forKey: StorageKey.trialStartDate)
    userDefaults.removeObject(forKey: StorageKey.trialEndDate)
    userDefaults.removeObject(forKey: StorageKey.purchaseDate)
    userDefaults.removeObject(forKey: StorageKey.transactionID)
    userDefaults.removeObject(forKey: StorageKey.trialBannerDismissed)
    clearKeychainEntitlement()
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

    updateKeychainEntitlement { entitlement in
      entitlement.transactionID = nil
      entitlement.purchaseDate = nil
      entitlement.trialStartDate = trialStart
      entitlement.trialEndDate = trialEnd
    }

    refreshEntitlements(currentDate: referenceDate)
    restoreBannerVisibilityIfNeeded()
  }
  #endif
}
