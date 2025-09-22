import Foundation
import StoreKit

/// 负责协调内购的状态、商品加载与交易处理
final class PurchaseManager: ObservableObject {
  @Published private(set) var state: PurchaseState = .unknown
  @Published private(set) var offerings: [PurchaseOffering] = []
  @Published private(set) var isTrialBannerDismissed: Bool

  /// 订阅商品（若已加载）
  var subscriptionOffering: PurchaseOffering? {
    offerings.first(where: { $0.kind == .subscription })
  }

  /// 买断商品（若已加载）
  var lifetimeOffering: PurchaseOffering? {
    offerings.first(where: { $0.kind == .lifetime })
  }

  private enum StorageKey {
    static let trialBannerDismissed = "purchase.trialBannerDismissed"
  }

  private let configuration: PurchaseConfiguration
  private let entitlementStore: PurchaseEntitlementStore
  private let userDefaults: UserDefaults
  private let transactionMonitor = PurchaseTransactionMonitor()
  private let clockSkewTolerance: TimeInterval = 5 * 60
  private let isReceiptValidationEnabled: Bool
  private let receiptSharedSecret: String?
  private let receiptValidator: PurchaseReceiptValidator?

  private var updatesTask: Task<Void, Never>?

  init(
    configuration: PurchaseConfiguration = .loadDefault(),
    userDefaults: UserDefaults = .standard,
    enableReceiptValidation: Bool = false,
    sharedSecret: String? = nil,
    receiptValidator: PurchaseReceiptValidator? = nil
  ) {
    self.configuration = configuration
    self.userDefaults = userDefaults
    self.entitlementStore = PurchaseEntitlementStore(userDefaults: userDefaults)
    self.isReceiptValidationEnabled = enableReceiptValidation
    self.receiptSharedSecret = sharedSecret
    if enableReceiptValidation {
      self.receiptValidator = receiptValidator ?? PurchaseReceiptValidator()
    } else {
      self.receiptValidator = nil
    }
    self.isTrialBannerDismissed = userDefaults.bool(forKey: StorageKey.trialBannerDismissed)

    refreshEntitlements()
    startListeningForTransactions()

    Task { @MainActor in
      await loadOfferings()
      await syncCurrentEntitlements()
      await validateReceiptIfNeeded()
    }
  }
  deinit {
    updatesTask?.cancel()
  }

  /// 当前是否具备完整版权限（试用期、订阅或买断）
  var isEntitled: Bool {
    switch state {
    case .trial:
      return true
    case .subscriber(let status):
      return status.isInGracePeriod || status.expirationDate == nil || (status.expirationDate ?? .distantPast) > Date()
    case .lifetime:
      return true
    case .subscriberLapsed(let status):
      return status.isInGracePeriod
    default:
      return false
    }
  }

  /// 是否已过试用期
  var isTrialExpired: Bool {
    if case .trialExpired = state {
      return true
    }
    return false
  }
  /// 重新评估当前的权益状态
  func refreshEntitlements(currentDate: Date = Date()) {
    defer { restoreBannerVisibilityIfNeeded() }

    guard var snapshot = entitlementStore.loadSnapshot() else {
      startTrial(from: currentDate)
      return
    }

    if isClockRollbackDetected(currentDate: currentDate, cachedTimestamp: snapshot.lastUpdated) {
      snapshot.trialEndDate = snapshot.trialEndDate ?? snapshot.lastUpdated
      snapshot.trialStartDate = snapshot.trialStartDate ?? snapshot.trialEndDate
      entitlementStore.saveSnapshot(snapshot)
      state = .trialExpired(TrialStatus(startDate: snapshot.trialStartDate ?? currentDate, endDate: snapshot.trialEndDate ?? currentDate))
      return
    }

    if let lifetimeDate = snapshot.lifetimePurchaseDate {
      let lifetimeStatus = LifetimeStatus(
        productID: snapshot.lifetimeProductID ?? configuration.lifetime?.identifier ?? "",
        transactionID: snapshot.lifetimeTransactionID,
        purchaseDate: lifetimeDate
      )
      snapshot.trialStartDate = nil
      snapshot.trialEndDate = nil
      snapshot.lastUpdated = currentDate
      entitlementStore.saveSnapshot(snapshot)
      state = .lifetime(lifetimeStatus)
      return
    }

    if let subscriptionExpiration = snapshot.subscriptionExpirationDate {
      let isActive = subscriptionExpiration > currentDate
      let status = SubscriptionStatus(
        productID: snapshot.subscriptionProductID ?? configuration.subscription?.identifier ?? "",
        transactionID: snapshot.subscriptionTransactionID,
        expirationDate: subscriptionExpiration,
        isInGracePeriod: currentDate <= subscriptionExpiration.addingTimeInterval(3 * 24 * 60 * 60)
      )
      snapshot.lastUpdated = currentDate
      entitlementStore.saveSnapshot(snapshot)
      state = isActive ? .subscriber(status) : .subscriberLapsed(status)
      return
    }

    if let trialStart = snapshot.trialStartDate, let trialEnd = snapshot.trialEndDate {
      let status = TrialStatus(startDate: trialStart, endDate: trialEnd)
      snapshot.lastUpdated = currentDate
      entitlementStore.saveSnapshot(snapshot)
      state = currentDate < trialEnd ? .trial(status) : .trialExpired(status)
      return
    }

    startTrial(from: currentDate)
  }
  private func isClockRollbackDetected(currentDate: Date, cachedTimestamp: Date) -> Bool {
    currentDate.addingTimeInterval(clockSkewTolerance) < cachedTimestamp
  }
  private func startTrial(from date: Date) {
    let trialEnd = date.addingTimeInterval(configuration.trialDuration)
    let status = TrialStatus(startDate: date, endDate: trialEnd)
    let snapshot = PurchaseEntitlementSnapshot(
      trialStartDate: date,
      trialEndDate: trialEnd,
      lastUpdated: date
    )
    entitlementStore.saveSnapshot(snapshot)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    state = .trial(status)
  }
  private func restoreBannerVisibilityIfNeeded() {
    switch state {
    case .trial, .trialExpired, .subscriberLapsed:
      if isTrialBannerDismissed {
        isTrialBannerDismissed = false
        userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
      }
    default:
      break
    }
  }
  /// 用户主动关闭试用提示
  func dismissTrialBanner() {
    guard !isTrialBannerDismissed else { return }
    isTrialBannerDismissed = true
    userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
  }
  private func startListeningForTransactions() {
    let productIDs = Set(configuration.allProductConfigurations.map { $0.identifier })
    updatesTask = transactionMonitor.observeUpdates(for: productIDs) { [weak self] transaction in
      await self?.handle(transaction: transaction, shouldFinish: true)
    }
  }
  @MainActor
  private func syncCurrentEntitlements() async {
    let productIDs = Set(configuration.allProductConfigurations.map { $0.identifier })
    await transactionMonitor.iterateCurrentEntitlements(for: productIDs) { [weak self] transaction in
      await self?.handle(transaction: transaction, shouldFinish: false)
    }

    if case .unknown = state {
      refreshEntitlements()
    }
  }
  @MainActor
  private func loadOfferings() async {
    let productIDs = configuration.allProductConfigurations.map { $0.identifier }
    guard !productIDs.isEmpty else {
      offerings = []
      return
    }

    do {
      let products = try await Product.products(for: productIDs)
      let mapped = products.compactMap { product -> PurchaseOffering? in
        guard let config = configuration.configuration(for: product.id) else { return nil }
        return PurchaseOffering(configuration: config, product: product)
      }

      offerings = mapped.sorted { lhs, rhs in
        func priority(for kind: PurchaseProductKind) -> Int {
          switch kind {
          case .subscription: return 0
          case .lifetime: return 1
          }
        }
        if priority(for: lhs.kind) == priority(for: rhs.kind) {
          return lhs.product.displayName < rhs.product.displayName
        }
        return priority(for: lhs.kind) < priority(for: rhs.kind)
      }
    } catch {
      #if DEBUG
      print("Product fetch error: \(error)")
      #endif
      offerings = []
    }
  }
  private func offering(for kind: PurchaseProductKind) -> PurchaseOffering? {
    offerings.first(where: { $0.kind == kind })
  }

  @MainActor
  func purchase(kind: PurchaseProductKind) async throws {
    let targetOffering: PurchaseOffering?
    if let offering = offering(for: kind) {
      targetOffering = offering
    } else {
      await loadOfferings()
      targetOffering = offering(for: kind)
    }

    guard let offering = targetOffering else {
      throw PurchaseManagerError.productUnavailable
    }

    let result: Product.PurchaseResult
    do {
      result = try await offering.product.purchase()
    } catch {
      throw PurchaseManagerError.unknown(error)
    }

    switch result {
    case .success(let verificationResult):
      let transaction = try PurchaseTransactionMonitor.checkVerified(verificationResult)
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
  func purchaseFullVersion() async throws {
    try await purchase(kind: .lifetime)
  }

  @MainActor
  func purchaseSubscription() async throws {
    try await purchase(kind: .subscription)
  }
  @MainActor
  func restorePurchases() async throws {
    do {
      try await AppStore.sync()
      await syncCurrentEntitlements()
      await validateReceiptIfNeeded()
    } catch {
      if let snapshot = entitlementStore.loadSnapshot(),
         let lifetimeDate = snapshot.lifetimePurchaseDate {
        let lifetimeStatus = LifetimeStatus(
          productID: snapshot.lifetimeProductID ?? configuration.lifetime?.identifier ?? "",
          transactionID: snapshot.lifetimeTransactionID,
          purchaseDate: lifetimeDate
        )
        state = .lifetime(lifetimeStatus)
        return
      }
      throw PurchaseManagerError.restoreFailed
    }

    switch state {
    case .subscriber, .lifetime:
      return
    default:
      if let snapshot = entitlementStore.loadSnapshot(),
         let lifetimeDate = snapshot.lifetimePurchaseDate {
        let lifetimeStatus = LifetimeStatus(
          productID: snapshot.lifetimeProductID ?? configuration.lifetime?.identifier ?? "",
          transactionID: snapshot.lifetimeTransactionID,
          purchaseDate: lifetimeDate
        )
        state = .lifetime(lifetimeStatus)
      } else {
        throw PurchaseManagerError.restoreFailed
      }
    }
  }
  @MainActor
  private func handle(transaction: Transaction, shouldFinish: Bool) async {
    guard let config = configuration.configuration(for: transaction.productID) else {
      if shouldFinish {
        await transaction.finish()
      }
      return
    }

    if let revocationDate = transaction.revocationDate {
      handleRevocation(productID: transaction.productID, date: revocationDate)
    } else {
      switch config.kind {
      case .lifetime:
        recordLifetimePurchase(
          productID: transaction.productID,
          transactionID: String(transaction.id),
          purchaseDate: transaction.purchaseDate
        )
      case .subscription:
        recordSubscription(
          productID: transaction.productID,
          transactionID: String(transaction.id),
          expirationDate: transaction.expirationDate,
          purchaseDate: transaction.purchaseDate
        )
      }
      await validateReceiptIfNeeded()
    }

    if shouldFinish {
      await transaction.finish()
    }
  }
  private func recordLifetimePurchase(productID: String, transactionID: String?, purchaseDate: Date) {
    var snapshot = entitlementStore.loadSnapshot() ?? PurchaseEntitlementSnapshot()
    snapshot.lifetimeProductID = productID
    snapshot.lifetimeTransactionID = transactionID
    snapshot.lifetimePurchaseDate = purchaseDate
    snapshot.trialStartDate = nil
    snapshot.trialEndDate = nil
    snapshot.lastUpdated = Date()
    entitlementStore.saveSnapshot(snapshot)

    userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = true

    state = .lifetime(
      LifetimeStatus(
        productID: productID,
        transactionID: transactionID,
        purchaseDate: purchaseDate
      )
    )
  }

  private func recordSubscription(productID: String, transactionID: String?, expirationDate: Date?, purchaseDate: Date) {
    var snapshot = entitlementStore.loadSnapshot() ?? PurchaseEntitlementSnapshot()
    let effectiveExpiration = expirationDate ?? purchaseDate.addingTimeInterval(configuration.trialDuration)
    snapshot.subscriptionProductID = productID
    snapshot.subscriptionTransactionID = transactionID
    snapshot.subscriptionExpirationDate = effectiveExpiration
    snapshot.lastUpdated = Date()
    entitlementStore.saveSnapshot(snapshot)

    let now = Date()
    let graceLimit = effectiveExpiration.addingTimeInterval(3 * 24 * 60 * 60)
    let status = SubscriptionStatus(
      productID: productID,
      transactionID: transactionID,
      expirationDate: effectiveExpiration,
      isInGracePeriod: now <= graceLimit
    )

    state = effectiveExpiration > now ? .subscriber(status) : .subscriberLapsed(status)

    if effectiveExpiration > now {
      userDefaults.set(true, forKey: StorageKey.trialBannerDismissed)
      isTrialBannerDismissed = true
    }
  }

  private func handleRevocation(productID: String, date: Date) {
    var snapshot = entitlementStore.loadSnapshot() ?? PurchaseEntitlementSnapshot()
    if snapshot.lifetimeProductID == productID {
      snapshot.lifetimeProductID = nil
      snapshot.lifetimeTransactionID = nil
      snapshot.lifetimePurchaseDate = nil
    }
    if snapshot.subscriptionProductID == productID {
      snapshot.subscriptionProductID = nil
      snapshot.subscriptionTransactionID = nil
      snapshot.subscriptionExpirationDate = nil
    }
    snapshot.lastUpdated = date
    entitlementStore.saveSnapshot(snapshot)

    state = .revoked(.refunded)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
  }
  @MainActor
  private func validateReceiptIfNeeded() async {
    guard isReceiptValidationEnabled, let validator = receiptValidator else { return }

    for config in configuration.allProductConfigurations {
      do {
        if let result = try await validator.validateReceipt(for: config.identifier, sharedSecret: receiptSharedSecret) {
          switch config.kind {
          case .lifetime:
            recordLifetimePurchase(
              productID: config.identifier,
              transactionID: result.transactionID,
              purchaseDate: result.purchaseDate
            )
          case .subscription:
            recordSubscription(
              productID: config.identifier,
              transactionID: result.transactionID,
              expirationDate: result.expirationDate,
              purchaseDate: result.purchaseDate
            )
          }
        }
      } catch PurchaseReceiptValidatorError.missingReceipt {
        #if DEBUG
        print("Receipt validation skipped: missing receipt")
        #endif
      } catch {
        #if DEBUG
        print("Receipt validation error: \(error.localizedDescription)")
        #endif
      }
    }
  }
  #if DEBUG
  func resetLocalState() {
    entitlementStore.clearSnapshot()
    userDefaults.removeObject(forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    state = .unknown
    refreshEntitlements()
  }

  func simulateTrialExpiration(referenceDate: Date = Date()) {
    let trialEnd = referenceDate.addingTimeInterval(-60)
    let trialStart = trialEnd.addingTimeInterval(-configuration.trialDuration)
    let snapshot = PurchaseEntitlementSnapshot(
      trialStartDate: trialStart,
      trialEndDate: trialEnd,
      lastUpdated: referenceDate
    )
    entitlementStore.saveSnapshot(snapshot)
    userDefaults.set(false, forKey: StorageKey.trialBannerDismissed)
    isTrialBannerDismissed = false
    refreshEntitlements(currentDate: referenceDate)
  }
  #endif
}
