//
//  PurchaseReceiptValidator.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/20.
//

import Foundation

/// 通过 App Store 服务器校验收据，确认购买有效性
struct PurchaseReceiptValidationResult {
  let transactionID: String
  let purchaseDate: Date
  let expirationDate: Date?
  let environment: String?
}

enum PurchaseReceiptValidatorError: LocalizedError {
  case missingReceipt
  case network(Error)
  case invalidHTTPStatus(code: Int)
  case decoding(Error)
  case serverStatus(code: Int)

  var errorDescription: String? {
    switch self {
    case .missingReceipt:
      return "receipt_validator_missing_receipt".localized
    case .network(let error):
      return error.localizedDescription
    case .invalidHTTPStatus(let code):
      return String(format: "receipt_validator_invalid_http".localized, code)
    case .decoding(let error):
      return String(format: "receipt_validator_decoding".localized, error.localizedDescription)
    case .serverStatus(let code):
      return String(format: "receipt_validator_server_status".localized, code)
    }
  }
}

/// 苹果官方收据验证 API 的封装
final class PurchaseReceiptValidator {
  private enum VerificationEndpoint {
    static let production = URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
    static let sandbox = URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
  }

  private struct ValidationPayload: Encodable {
    let receiptData: String
    let password: String?
    let excludeOldTransactions: Bool

    enum CodingKeys: String, CodingKey {
      case receiptData = "receipt-data"
      case password
      case excludeOldTransactions = "exclude-old-transactions"
    }
  }

  private struct ValidationResponse: Decodable {
    let status: Int
    let environment: String?
    let receipt: ReceiptObject?
    let latestReceiptInfo: [ReceiptItem]?

    enum CodingKeys: String, CodingKey {
      case status
      case environment
      case receipt
      case latestReceiptInfo = "latest_receipt_info"
    }
  }

  private struct ReceiptObject: Decodable {
    let inApp: [ReceiptItem]?

    enum CodingKeys: String, CodingKey {
      case inApp = "in_app"
    }
  }

  private struct ReceiptItem: Decodable {
    let productId: String
    let transactionId: String
    let originalTransactionId: String?
    let purchaseDateMs: String?
    let originalPurchaseDateMs: String?
    let expiresDateMs: String?

    enum CodingKeys: String, CodingKey {
      case productId = "product_id"
      case transactionId = "transaction_id"
      case originalTransactionId = "original_transaction_id"
      case purchaseDateMs = "purchase_date_ms"
      case originalPurchaseDateMs = "original_purchase_date_ms"
      case expiresDateMs = "expires_date_ms"
    }

    var purchaseDate: Date? {
      if let ms = purchaseDateMs, let value = Double(ms) {
        return Date(timeIntervalSince1970: value / 1000)
      }
      if let originalMs = originalPurchaseDateMs, let value = Double(originalMs) {
        return Date(timeIntervalSince1970: value / 1000)
      }
      return nil
    }

    var expirationDate: Date? {
      guard let ms = expiresDateMs, let value = Double(ms) else { return nil }
      return Date(timeIntervalSince1970: value / 1000)
    }
  }

  private let session: URLSession
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// 校验指定商品的收据信息
  func validateReceipt(for productIdentifier: String, sharedSecret: String?) async throws -> PurchaseReceiptValidationResult? {
    let payloadData = try buildPayloadData(sharedSecret: sharedSecret)

    let productionResponse = try await sendRequest(to: VerificationEndpoint.production, body: payloadData)

    switch productionResponse.status {
    case 0:
      return extractResult(from: productionResponse, for: productIdentifier)
    case 21007:
      // 生产环境返回沙盒状态，需要切换到沙盒接口
      let sandboxResponse = try await sendRequest(to: VerificationEndpoint.sandbox, body: payloadData)
      guard sandboxResponse.status == 0 else {
        throw PurchaseReceiptValidatorError.serverStatus(code: sandboxResponse.status)
      }
      return extractResult(from: sandboxResponse, for: productIdentifier)
    default:
      throw PurchaseReceiptValidatorError.serverStatus(code: productionResponse.status)
    }
  }

  // MARK: - Private Helpers

  private func buildPayloadData(sharedSecret: String?) throws -> Data {
    let receipt = try loadReceiptData()
    let base64String = receipt.base64EncodedString()
    let payload = ValidationPayload(receiptData: base64String, password: sharedSecret, excludeOldTransactions: true)
    return try encoder.encode(payload)
  }

  private func loadReceiptData() throws -> Data {
    guard let receiptURL = Bundle.main.appStoreReceiptURL else {
      throw PurchaseReceiptValidatorError.missingReceipt
    }

    do {
      let data = try Data(contentsOf: receiptURL)
      if data.isEmpty {
        throw PurchaseReceiptValidatorError.missingReceipt
      }
      return data
    } catch {
      throw PurchaseReceiptValidatorError.missingReceipt
    }
  }

  private func sendRequest(to url: URL, body: Data) async throws -> ValidationResponse {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw PurchaseReceiptValidatorError.invalidHTTPStatus(code: -1)
      }

      guard 200 ..< 300 ~= httpResponse.statusCode else {
        throw PurchaseReceiptValidatorError.invalidHTTPStatus(code: httpResponse.statusCode)
      }

      do {
        return try decoder.decode(ValidationResponse.self, from: data)
      } catch {
        throw PurchaseReceiptValidatorError.decoding(error)
      }
    } catch let error as PurchaseReceiptValidatorError {
      throw error
    } catch {
      throw PurchaseReceiptValidatorError.network(error)
    }
  }

  private func extractResult(from response: ValidationResponse, for productIdentifier: String) -> PurchaseReceiptValidationResult? {
    let candidates: [ReceiptItem] = {
      if let latest = response.latestReceiptInfo, !latest.isEmpty {
        return latest
      }
      return response.receipt?.inApp ?? []
    }()

    guard !candidates.isEmpty else { return nil }

    let matched = candidates
      .filter { $0.productId == productIdentifier }
      .sorted { (lhs, rhs) -> Bool in
        let left = lhs.purchaseDate ?? .distantPast
        let right = rhs.purchaseDate ?? .distantPast
        return left < right
      }
      .last

    guard let purchase = matched, let purchaseDate = purchase.purchaseDate else { return nil }

    return PurchaseReceiptValidationResult(
      transactionID: purchase.transactionId,
      purchaseDate: purchaseDate,
      expirationDate: purchase.expirationDate,
      environment: response.environment
    )
  }
}
