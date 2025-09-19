//
//  UpgradePromptSheet.swift
//  Pixo
//
//  Created by Codex on 2025/2/15.
//

import SwiftUI
import StoreKit

/// 升级提示上下文
enum UpgradePromptContext: String, Identifiable {
  case transform
  case crop
  case generic
  case purchase

  var id: String { rawValue }

  var message: String {
    switch self {
    case .transform:
      return "unlock_alert_body_transform".localized
    case .crop:
      return "unlock_alert_body_crop".localized
    case .generic:
      return "unlock_alert_body_generic".localized
    case .purchase:
      return "unlock_alert_body_manual_purchase".localized
    }
  }
}

/// 购买解锁提示弹窗
struct UpgradePromptSheet: View {
  @EnvironmentObject private var purchaseManager: PurchaseManager

  let context: UpgradePromptContext
  let onConfirmPurchase: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("unlock_alert_title".localized)
        .font(.title3)
        .bold()

      Text(context.message)
        .font(.body)
        .foregroundStyle(.primary)

      productInfoSection

      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Button("purchase_prompt_confirm".localized, action: onConfirmPurchase)
          .buttonStyle(.borderedProminent)

        Text("purchase_prompt_confirm_note".localized)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button("unlock_alert_cancel".localized, action: onCancel)
          .buttonStyle(.plain)
      }
      .padding(.top, 8)
    }
    .frame(minWidth: 320)
    .padding(24)
  }

  private var productInfoSection: some View {
    Group {
      if let product = purchaseManager.availableProduct {
        VStack(alignment: .leading, spacing: 6) {
          Text(String(format: "purchase_product_name".localized, product.displayName))
            .font(.headline)

          Text(String(format: "purchase_product_price".localized, product.displayPrice))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.05))
        )
      } else {
        Text("purchase_product_loading".localized)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}
