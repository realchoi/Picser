//
//  GeneralSettingsView.swift
//
//  Created by Eric Cai on 2025/09/06.
//

import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @State private var showLanguageChangeNote = false
  @State private var alertContent: AlertContent?
  @EnvironmentObject private var purchaseManager: PurchaseManager
  @Environment(\.isSettingsMeasurement) private var isMeasurement

  var body: some View {
    let container = contentView
      .settingsContentContainer()

    return Group {
      if isMeasurement {
        container
      } else {
        container
          .alert(item: $alertContent) { alertData in
            Alert(
              title: Text(alertData.title),
              message: Text(alertData.message),
              dismissButton: .default(Text(l10n: "ok_button"))
            )
          }
      }
    }
  }

  private var purchaseSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(l10n: "purchase_section_title")
        .fontWeight(.medium)

      Text(l10n: "purchase_section_description")
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
            Button(L10n.key("purchase_section_restore")) {
              performRestore()
            }
            .buttonStyle(.bordered)

            if shouldShowPurchaseButton {
              Button(L10n.key("purchase_section_purchase")) {
                presentPurchasePrompt()
              }
              .buttonStyle(.borderedProminent)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var purchaseStatusText: String {
    switch purchaseManager.state {
    case .trial(_):
      return localized("purchase_status_trial_prefix")
    case .trialExpired(_):
      return localized("purchase_status_expired")
    case .subscriber(_):
      return localized("purchase_status_subscribed")
    case .subscriberLapsed(_):
      return localized("purchase_status_subscribed_lapsed")
    case .lifetime(_):
      return localized("purchase_status_purchased")
    case .revoked(_):
      return localized("purchase_status_revoked")
    case .onboarding, .unknown:
      return localized("purchase_status_unknown")
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
      let template = localized("purchase_status_trial_remaining")
      return String(format: template, description)
    case let .subscriber(status):
      if let expiry = status.expirationDate, expiry > Date() {
        let description = TrialFormatter.remainingDescription(endDate: expiry)
        let template = localized("purchase_status_subscription_remaining")
        return String(format: template, description)
      }
      return nil
    case let .subscriberLapsed(status):
      guard status.isInGracePeriod else { return nil }
      if let expiration = status.expirationDate {
        let graceEnd = expiration.addingTimeInterval(3 * 24 * 60 * 60)
        let description = TrialFormatter.remainingDescription(endDate: graceEnd)
        let template = localized("purchase_status_grace_remaining")
        return String(format: template, description)
      } else {
        return localized("purchase_status_grace_generic")
      }
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
      onRefreshReceipt: {
        performRefreshReceipt()
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

  private func performRefreshReceipt() {
    Task { @MainActor in
      do {
        try await purchaseManager.refreshReceipt()
      } catch {
        handlePurchaseError(error, operation: .refreshReceipt)
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

  private func localized(_ key: String) -> String {
    L10n.string(key)
  }

  private var shouldShowPurchaseButton: Bool {
    !purchaseManager.hasActiveLicense
  }

  @ViewBuilder
  private var contentView: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(l10n: "general_settings_title")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 界面设置组
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "interface_group")
          .fontWeight(.medium)

        // 语言选择
        VStack(alignment: .leading, spacing: 8) {
          Text(l10n: "app_language_label")
            .fontWeight(.medium)
          Text(l10n: "app_language_description")
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

              Text(l10n: "language_restart_note")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
      }

      Divider()

      purchaseSection

      Spacer().frame(height: 20)

      // 重置按钮
      HStack {
        Spacer()
        Button(L10n.key("reset_defaults_button")) {
          withAnimation {
            appSettings.resetToDefaults(settingsTab: .general)
          }
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

// 预览
#Preview {
  GeneralSettingsView(appSettings: AppSettings())
    .environmentObject(PurchaseManager())
}
