//
//  SecretsProvider.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/20.
//

import Foundation

/// 统一管理敏感配置的获取方式，避免在代码中硬编码共享密钥
enum SecretsProvider {
  private enum KeychainKey {
    static var service: String {
      let base = Bundle.main.bundleIdentifier ?? "com.soyotube.Pixor"
      return base + ".secrets"
    }
    static let iapSharedSecretAccount = "iap-shared-secret"
  }

  private enum InfoKey {
    static let sharedSecret = "PIXOR_IAP_SHARED_SECRET"
    static let primaryProductIdentifier = "PIXOR_IAP_PRODUCT_ID"
  }

  static let defaultProductIdentifier = "com.soyotube.Pixor.full"

  /// 读取 App Store Connect 中配置的共享密钥。
  /// 加载顺序：钥匙串 → 环境变量 → Info.plist（或自定义配置文件）。
  static func purchaseSharedSecret() -> String? {
    if let keychainSecret = loadSharedSecretFromKeychain(), !keychainSecret.isEmpty {
      return keychainSecret
    }

    if let envSecret = ProcessInfo.processInfo.environment["PIXOR_IAP_SHARED_SECRET"], !envSecret.isEmpty {
      return envSecret
    }

    if let infoSecret = Bundle.main.object(forInfoDictionaryKey: InfoKey.sharedSecret) as? String, !infoSecret.isEmpty {
      return infoSecret
    }

    return nil
  }

  /// 读取主要的 IAP 产品标识。加载顺序：环境变量 → Info.plist → 默认值。
  static func purchaseProductIdentifier() -> String {
    if let envProduct = ProcessInfo.processInfo.environment["PIXOR_IAP_PRODUCT_ID"], !envProduct.isEmpty {
      return envProduct
    }

    if let infoProduct = Bundle.main.object(forInfoDictionaryKey: InfoKey.primaryProductIdentifier) as? String,
       !infoProduct.isEmpty {
      return infoProduct
    }

    return defaultProductIdentifier
  }

  /// 调试用途：写入共享密钥到钥匙串，方便本地测试。
  static func storePurchaseSharedSecret(_ secret: String) {
    guard let data = secret.data(using: .utf8) else { return }
    try? KeychainHelper.save(
      data: data,
      service: KeychainKey.service,
      account: KeychainKey.iapSharedSecretAccount,
      policy: .standard
    )
  }

  @discardableResult
  static func clearPurchaseSharedSecret() -> Bool {
    do {
      try KeychainHelper.delete(service: KeychainKey.service, account: KeychainKey.iapSharedSecretAccount)
      return true
    } catch {
      return false
    }
  }

  private static func loadSharedSecretFromKeychain() -> String? {
    do {
      guard let data = try KeychainHelper.load(
        service: KeychainKey.service,
        account: KeychainKey.iapSharedSecretAccount,
        policy: .standard
      ) else {
        return nil
      }
      return String(data: data, encoding: .utf8)
    } catch {
      #if DEBUG
      print("SecretsProvider keychain load failed: \(error.localizedDescription)")
      #endif
      return nil
    }
  }
}
