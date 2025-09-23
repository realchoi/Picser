//
//  GeneralSettingsView.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/06.
//

import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @State private var showLanguageChangeNote = false
  @State private var alertContent: AlertContent?
  @EnvironmentObject private var purchaseManager: PurchaseManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("general_settings_title".localized)
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 界面设置组
        VStack(alignment: .leading, spacing: 16) {
          Text("interface_group".localized)
            .fontWeight(.medium)

          // 语言选择
          VStack(alignment: .leading, spacing: 8) {
            Text("app_language_label".localized)
              .fontWeight(.medium)
            Text("app_language_description".localized)
              .font(.caption)
              .foregroundColor(.secondary)

            HStack {
              Picker("", selection: $appSettings.appLanguage) {
                ForEach(AppLanguage.availableKeys(), id: \.self) { language in
                  Text(language.displayName).tag(language)
                }
              }
              .pickerStyle(.menu)
              .frame(minWidth: 120)
              .onChange(of: appSettings.appLanguage) {
                showLanguageChangeNote = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                  showLanguageChangeNote = false
                }
              }

              Spacer()
            }

            // 语言变更提示
            if showLanguageChangeNote {
              HStack {
                Image(systemName: "info.circle.fill")
                  .foregroundColor(.blue)
                  .font(.caption)

                Text("language_restart_note".localized)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
        }

        Divider()

        purchaseSection

        Spacer(minLength: 20)

        // 重置按钮
        HStack {
          Spacer()
          Button("reset_defaults_button".localized) {
            withAnimation {
              appSettings.resetToDefaults(settingsTab: .general)
            }
          }
          .buttonStyle(.bordered)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
    .alert(item: $alertContent) { alertData in
      Alert(
        title: Text(alertData.title),
        message: Text(alertData.message),
        dismissButton: .default(Text("ok_button".localized))
      )
    }
  }

  private var purchaseSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("purchase_section_title".localized)
        .fontWeight(.medium)

      Text("purchase_section_description".localized)
        .font(.caption)
        .foregroundColor(.secondary)

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Label(purchaseStatusText, systemImage: purchaseStatusIcon)
            .labelStyle(.titleAndIcon)

          if let trialText = trialRemainingText {
            Text(trialText)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 12) {
            Button("purchase_section_restore".localized) {
              performRestore()
            }
            .buttonStyle(.bordered)

            Button("purchase_section_purchase".localized) {
              presentPurchasePrompt()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var purchaseStatusText: String {
    switch purchaseManager.state {
    case .trial(_):
      return localized("purchase_status_trial_prefix", fallback: "当前状态：试用")
    case .trialExpired(_):
      return localized("purchase_status_expired", fallback: "当前状态：试用已结束")
    case .subscriber(_):
      return localized("purchase_status_subscribed", fallback: "当前状态：订阅中")
    case .subscriberLapsed(_):
      return localized("purchase_status_subscribed_lapsed", fallback: "当前状态：订阅已过期")
    case .lifetime(_):
      return localized("purchase_status_purchased", fallback: "当前状态：已买断")
    case .revoked(_):
      return localized("purchase_status_revoked", fallback: "当前状态：权限已撤销")
    case .onboarding, .unknown:
      return localized("purchase_status_unknown", fallback: "当前状态：加载中")
    }
  }

  private var purchaseStatusIcon: String {
    switch purchaseManager.state {
    case .trial(_):
      return "clock"
    case .trialExpired(_):
      return "lock.circle"
    case .subscriber(_):
      return "bell.badge"
    case .subscriberLapsed(_):
      return "bell.slash"
    case .lifetime(_):
      return "checkmark.seal"
    case .revoked(_):
      return "exclamationmark.shield"
    case .onboarding, .unknown:
      return "questionmark.circle"
    }
  }

  private var trialRemainingText: String? {
    switch purchaseManager.state {
    case let .trial(status):
      let description = TrialFormatter.remainingDescription(endDate: status.endDate)
      let template = localized("purchase_status_trial_remaining", fallback: "试用剩余时间：%@")
      return String(format: template, description)
    case let .subscriber(status):
      if let expiry = status.expirationDate, expiry > Date() {
        let description = TrialFormatter.remainingDescription(endDate: expiry)
        let template = localized("purchase_status_subscription_remaining", fallback: "订阅剩余时间：%@")
        return String(format: template, description)
      }
      return nil
    default:
      return nil
    }
  }

  private func presentPurchasePrompt() {
    PurchaseFlowCoordinator.shared.present(
      context: .purchase,
      purchaseManager: purchaseManager,
      onPurchase: { kind in
        performPurchase(kind: kind)
      },
      onRestore: {
        performRestore()
      },
      onDismiss: {}
    )
  }

  private func performPurchase(kind: PurchaseProductKind) {
    Task { @MainActor in
      do {
        try await purchaseManager.purchase(kind: kind)
        PurchaseFlowCoordinator.shared.dismiss()
      } catch {
        if ((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false) {
          return
        }
        handlePurchaseError(error, operation: .purchase)
      }
    }
  }

  private func performRestore() {
    guard PurchaseFlowCoordinator.shared.tryBeginRestore() else { return }

    Task { @MainActor in
      defer { PurchaseFlowCoordinator.shared.endRestore() }

      do {
        try await purchaseManager.restorePurchases()
        PurchaseFlowCoordinator.shared.dismiss()
      } catch {
        if ((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false) {
          return
        }
        handlePurchaseError(error, operation: .restore)
      }
    }
  }

  @MainActor
  private func handlePurchaseError(_ error: Error, operation: PurchaseFlowOperation) {
    if let managerError = error as? PurchaseManagerError, managerError.shouldSuppressAlert {
      return
    }

    #if DEBUG
    print("Settings purchase flow (\(operation.debugLabel)) failed: \(error.localizedDescription)")
    #endif

    PurchaseFlowCoordinator.shared.presentError(
      title: operation.failureTitle,
      message: error.purchaseDisplayMessage
    ) {
      self.alertContent = AlertContent(
        title: operation.failureTitle,
        message: error.purchaseDisplayMessage
      )
    }
  }

  private func localized(_ key: String, fallback: String) -> String {
    let value = key.localized
    return value == key ? fallback : value
  }
}

// 预览
#Preview {
  GeneralSettingsView(appSettings: AppSettings())
    .environmentObject(PurchaseManager())
}
