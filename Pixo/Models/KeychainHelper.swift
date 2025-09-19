//
//  KeychainHelper.swift
//  Pixo
//
//  Created by Eric Cai on 2025/9/19.
//

import Foundation
import LocalAuthentication
import Security

enum KeychainHelper {
  enum AccessPolicy {
    case standard
    case userPresence(prompt: String)

    var accessible: CFString {
      switch self {
      case .standard:
        return kSecAttrAccessibleAfterFirstUnlock
      case .userPresence:
        return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      }
    }

    var accessControlFlags: SecAccessControlCreateFlags? {
      switch self {
      case .standard:
        return nil
      case .userPresence:
        return [.userPresence]
      }
    }

    var operationPrompt: String? {
      switch self {
      case .standard:
        return nil
      case .userPresence(let prompt):
        return prompt
      }
    }
  }

  static func save(data: Data, service: String, account: String, policy: AccessPolicy = .standard) throws {
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    SecItemDelete(baseQuery as CFDictionary)

    var attributes = baseQuery
    attributes[kSecValueData as String] = data

    if let flags = policy.accessControlFlags {
      guard let accessControl = SecAccessControlCreateWithFlags(nil, policy.accessible, flags, nil) else {
        throw KeychainError.unhandledError(status: errSecParam)
      }
      attributes[kSecAttrAccessControl as String] = accessControl
    } else {
      attributes[kSecAttrAccessible as String] = policy.accessible
    }

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status != errSecSuccess {
      throw KeychainError.unhandledError(status: status)
    }
  }

  static func load(service: String, account: String, policy: AccessPolicy = .standard, context: LAContext? = nil) throws -> Data? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    if policy.accessControlFlags != nil {
      let activeContext: LAContext
      if let providedContext = context {
        activeContext = providedContext
      } else {
        activeContext = LAContext()
      }
      activeContext.interactionNotAllowed = false
      if let prompt = policy.operationPrompt {
        if #available(macOS 11.0, *) {
          activeContext.localizedReason = prompt
        } else {
          // 旧系统使用提示字符串
          query[kSecUseOperationPrompt as String] = prompt
        }
      }
      query[kSecUseAuthenticationContext as String] = activeContext
      if #unavailable(macOS 11.0) {
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIAllow
      }
    }

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecItemNotFound {
      return nil
    }

    if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
      throw KeychainError.authenticationFailed(status: status)
    }

    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }

    guard let data = item as? Data else {
      throw KeychainError.invalidData
    }

    return data
  }

  static func delete(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError.unhandledError(status: status)
    }
  }
}

enum KeychainError: LocalizedError {
  case invalidData
  case authenticationFailed(status: OSStatus)
  case unhandledError(status: OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      return "keychain_invalid_data".localized
    case .authenticationFailed(let status):
      let format = "keychain_authentication_failed".localized
      return String(format: format, status)
    case .unhandledError(let status):
      let format = "keychain_unhandled_error".localized
      return String(format: format, status)
    }
  }
}
