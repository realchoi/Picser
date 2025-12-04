//
//  TagSettingsLockedView.swift
//
//  未订阅用户在标签设置页面看到的升级提示视图
//

import SwiftUI

/// 标签设置功能锁定视图
///
/// 当用户未订阅时，在标签管理标签页显示此视图，
/// 引导用户购买完整版以解锁标签管理功能。
struct TagSettingsLockedView: View {
  @ObservedObject var purchaseManager: PurchaseManager
  @ObservedObject private var localizationManager = LocalizationManager.shared

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // 锁定图标
      Image(systemName: "lock.circle")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)

      // 标题
      Text(l10n: "tag_settings_locked_title")
        .font(.title2)
        .fontWeight(.semibold)

      // 说明文字
      Text(l10n: "tag_settings_locked_message")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      // 功能列表
      VStack(alignment: .leading, spacing: 12) {
        featureRow(icon: "tag.fill", text: L10n.string("tag_settings_locked_feature_1"))
        featureRow(icon: "magnifyingglass", text: L10n.string("tag_settings_locked_feature_2"))
        featureRow(icon: "wand.and.stars", text: L10n.string("tag_settings_locked_feature_3"))
      }
      .padding(.vertical, 8)

      // 购买按钮
      Button {
        presentPurchasePrompt()
      } label: {
        Label(L10n.string("tag_settings_locked_button"), systemImage: "cart")
          .frame(minWidth: 160)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
    .settingsContentContainer()
  }

  private func featureRow(icon: String, text: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(Color.accentColor)
        .frame(width: 24)
      Text(text)
        .font(.callout)
    }
  }

  private func presentPurchasePrompt() {
    PurchaseFlowCoordinator.shared.present(
      context: .tags,
      purchaseManager: purchaseManager,
      onPurchase: { kind in
        Task { @MainActor in
          do {
            try await purchaseManager.purchase(kind: kind)
            PurchaseFlowCoordinator.shared.dismiss()
          } catch {
            if !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false) {
              #if DEBUG
              print("TagSettingsLockedView purchase failed: \(error.localizedDescription)")
              #endif
            }
          }
        }
      },
      onRestore: {
        guard PurchaseFlowCoordinator.shared.tryBeginRestore() else { return }
        Task { @MainActor in
          defer { PurchaseFlowCoordinator.shared.endRestore() }
          do {
            try await purchaseManager.restorePurchases()
            PurchaseFlowCoordinator.shared.dismiss()
          } catch {
            if !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false) {
              #if DEBUG
              print("TagSettingsLockedView restore failed: \(error.localizedDescription)")
              #endif
            }
          }
        }
      },
      onRefreshReceipt: {
        Task { @MainActor in
          do {
            try await purchaseManager.refreshReceipt()
          } catch {
            #if DEBUG
            print("TagSettingsLockedView refresh receipt failed: \(error.localizedDescription)")
            #endif
          }
        }
      },
      onDismiss: {}
    )
  }
}

#Preview {
  TagSettingsLockedView(purchaseManager: PurchaseManager())
}
