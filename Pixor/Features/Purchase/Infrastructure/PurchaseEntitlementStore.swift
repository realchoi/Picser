import Foundation

/// 管理本地缓存的内购权益信息（UserDefaults + 钥匙串）
final class PurchaseEntitlementStore {
  private enum StorageKey {
    static let trialStartDate = "purchase.trialStartDate"
    static let trialEndDate = "purchase.trialEndDate"
    static let lifetimePurchaseDate = "purchase.purchaseDate"
    static let lifetimeTransactionID = "purchase.transactionID"
    static let lifetimeProductID = "purchase.lifetimeProductID"
    static let subscriptionExpirationDate = "purchase.subscriptionExpirationDate"
    static let subscriptionTransactionID = "purchase.subscriptionTransactionID"
    static let subscriptionProductID = "purchase.subscriptionProductID"
  }

  private enum KeychainKey {
    static func service(bundle: Bundle) -> String {
      let base = bundle.bundleIdentifier ?? "com.soyotube.Pixor"
      return base + ".purchase"
    }

    static let account = "full-access"
  }

  private let userDefaults: UserDefaults
  private let bundle: Bundle
  private let keychainPolicy: KeychainHelper.AccessPolicy

  init(userDefaults: UserDefaults = .standard, bundle: Bundle = .main, keychainPolicy: KeychainHelper.AccessPolicy = .standard) {
    self.userDefaults = userDefaults
    self.bundle = bundle
    self.keychainPolicy = keychainPolicy
  }

  func loadSnapshot() -> PurchaseEntitlementSnapshot? {
    if let data = (try? KeychainHelper.load(
      service: KeychainKey.service(bundle: bundle),
      account: KeychainKey.account,
      policy: keychainPolicy
    )) ?? nil,
    let snapshot = try? JSONDecoder().decode(PurchaseEntitlementSnapshot.self, from: data) {
      return snapshot
    }

    if let fallback = snapshotFromUserDefaults() {
      return fallback
    }

    return nil
  }

  func saveSnapshot(_ snapshot: PurchaseEntitlementSnapshot) {
    persistToUserDefaults(snapshot)
    persistToKeychain(snapshot)
  }

  func clearSnapshot() {
    persistToUserDefaults(PurchaseEntitlementSnapshot())
    try? KeychainHelper.delete(
      service: KeychainKey.service(bundle: bundle),
      account: KeychainKey.account
    )
  }

  // MARK: - Private

  private func snapshotFromUserDefaults() -> PurchaseEntitlementSnapshot? {
    let purchaseDate = userDefaults.object(forKey: StorageKey.lifetimePurchaseDate) as? Date
    let trialStart = userDefaults.object(forKey: StorageKey.trialStartDate) as? Date
    let trialEnd = userDefaults.object(forKey: StorageKey.trialEndDate) as? Date
    let subscriptionExpiration = userDefaults.object(forKey: StorageKey.subscriptionExpirationDate) as? Date

    if purchaseDate == nil && trialStart == nil && subscriptionExpiration == nil {
      return nil
    }

    return PurchaseEntitlementSnapshot(
      trialStartDate: trialStart,
      trialEndDate: trialEnd,
      lifetimePurchaseDate: purchaseDate,
      lifetimeTransactionID: userDefaults.string(forKey: StorageKey.lifetimeTransactionID),
      lifetimeProductID: userDefaults.string(forKey: StorageKey.lifetimeProductID),
      subscriptionExpirationDate: subscriptionExpiration,
      subscriptionTransactionID: userDefaults.string(forKey: StorageKey.subscriptionTransactionID),
      subscriptionProductID: userDefaults.string(forKey: StorageKey.subscriptionProductID),
      lastUpdated: Date()
    )
  }

  private func persistToUserDefaults(_ snapshot: PurchaseEntitlementSnapshot) {
    userDefaults.set(snapshot.trialStartDate, forKey: StorageKey.trialStartDate)
    userDefaults.set(snapshot.trialEndDate, forKey: StorageKey.trialEndDate)
    userDefaults.set(snapshot.lifetimePurchaseDate, forKey: StorageKey.lifetimePurchaseDate)

    if let lifetimeTransactionID = snapshot.lifetimeTransactionID {
      userDefaults.set(lifetimeTransactionID, forKey: StorageKey.lifetimeTransactionID)
    } else {
      userDefaults.removeObject(forKey: StorageKey.lifetimeTransactionID)
    }

    if let lifetimeProductID = snapshot.lifetimeProductID {
      userDefaults.set(lifetimeProductID, forKey: StorageKey.lifetimeProductID)
    } else {
      userDefaults.removeObject(forKey: StorageKey.lifetimeProductID)
    }

    if let subscriptionExpirationDate = snapshot.subscriptionExpirationDate {
      userDefaults.set(subscriptionExpirationDate, forKey: StorageKey.subscriptionExpirationDate)
    } else {
      userDefaults.removeObject(forKey: StorageKey.subscriptionExpirationDate)
    }

    if let subscriptionTransactionID = snapshot.subscriptionTransactionID {
      userDefaults.set(subscriptionTransactionID, forKey: StorageKey.subscriptionTransactionID)
    } else {
      userDefaults.removeObject(forKey: StorageKey.subscriptionTransactionID)
    }

    if let subscriptionProductID = snapshot.subscriptionProductID {
      userDefaults.set(subscriptionProductID, forKey: StorageKey.subscriptionProductID)
    } else {
      userDefaults.removeObject(forKey: StorageKey.subscriptionProductID)
    }
  }

  private func persistToKeychain(_ snapshot: PurchaseEntitlementSnapshot) {
    do {
      var payload = snapshot
      payload.schemaVersion = PurchaseEntitlementSnapshot.currentSchemaVersion
      payload.lastUpdated = Date()
      let data = try JSONEncoder().encode(payload)
      try KeychainHelper.save(
        data: data,
        service: KeychainKey.service(bundle: bundle),
        account: KeychainKey.account,
        policy: keychainPolicy
      )
    } catch {
      #if DEBUG
      print("PurchaseEntitlementStore keychain save error: \(error)")
      #endif
    }
  }
}

/// 权益信息快照
struct PurchaseEntitlementSnapshot: Codable {
  static let currentSchemaVersion = 3

  var schemaVersion: Int
  var trialStartDate: Date?
  var trialEndDate: Date?
  var lifetimePurchaseDate: Date?
  var lifetimeTransactionID: String?
  var lifetimeProductID: String?
  var subscriptionExpirationDate: Date?
  var subscriptionTransactionID: String?
  var subscriptionProductID: String?
  var lastUpdated: Date

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case trialStartDate
    case trialEndDate
    case lifetimePurchaseDate
    case lifetimeTransactionID
    case lifetimeProductID
    case subscriptionExpirationDate
    case subscriptionTransactionID
    case subscriptionProductID
    case lastUpdated
  }

  init(
    schemaVersion: Int = PurchaseEntitlementSnapshot.currentSchemaVersion,
    trialStartDate: Date? = nil,
    trialEndDate: Date? = nil,
    lifetimePurchaseDate: Date? = nil,
    lifetimeTransactionID: String? = nil,
    lifetimeProductID: String? = nil,
    subscriptionExpirationDate: Date? = nil,
    subscriptionTransactionID: String? = nil,
    subscriptionProductID: String? = nil,
    lastUpdated: Date = Date()
  ) {
    self.schemaVersion = schemaVersion
    self.trialStartDate = trialStartDate
    self.trialEndDate = trialEndDate
    self.lifetimePurchaseDate = lifetimePurchaseDate
    self.lifetimeTransactionID = lifetimeTransactionID
    self.lifetimeProductID = lifetimeProductID
    self.subscriptionExpirationDate = subscriptionExpirationDate
    self.subscriptionTransactionID = subscriptionTransactionID
    self.subscriptionProductID = subscriptionProductID
    self.lastUpdated = lastUpdated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    trialStartDate = try container.decodeIfPresent(Date.self, forKey: .trialStartDate)
    trialEndDate = try container.decodeIfPresent(Date.self, forKey: .trialEndDate)
    lifetimePurchaseDate = try container.decodeIfPresent(Date.self, forKey: .lifetimePurchaseDate)
    lifetimeTransactionID = try container.decodeIfPresent(String.self, forKey: .lifetimeTransactionID)
    lifetimeProductID = try container.decodeIfPresent(String.self, forKey: .lifetimeProductID)
    subscriptionExpirationDate = try container.decodeIfPresent(Date.self, forKey: .subscriptionExpirationDate)
    subscriptionTransactionID = try container.decodeIfPresent(String.self, forKey: .subscriptionTransactionID)
    subscriptionProductID = try container.decodeIfPresent(String.self, forKey: .subscriptionProductID)

    if let timestamp = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) {
      lastUpdated = timestamp
    } else if let purchaseDate = lifetimePurchaseDate {
      lastUpdated = purchaseDate
    } else if let trialEndDate = trialEndDate {
      lastUpdated = trialEndDate
    } else {
      lastUpdated = Date()
    }

    migrateLegacySchemaIfNeeded()
  }

  mutating func migrateLegacySchemaIfNeeded() {
    if schemaVersion < 3 {
      schemaVersion = PurchaseEntitlementSnapshot.currentSchemaVersion
    }
  }
}
