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
  @State private var purchasePrompt: UpgradePromptContext?
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
    .sheet(item: $purchasePrompt) { context in
      UpgradePromptSheet(
        context: context,
        onConfirmPurchase: {
          performPurchase()
        },
        onCancel: {
          purchasePrompt = nil
        }
      )
    }
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
              purchasePrompt = .purchase
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
    case .trial:
      return "purchase_status_trial_prefix".localized
    case .trialExpired:
      return "purchase_status_expired".localized
    case .purchased:
      return "purchase_status_purchased".localized
    case .unknown:
      return "purchase_status_unknown".localized
    }
  }

  private var purchaseStatusIcon: String {
    switch purchaseManager.state {
    case .trial:
      return "clock"
    case .trialExpired:
      return "lock.circle"
    case .purchased:
      return "checkmark.seal"
    case .unknown:
      return "questionmark.circle"
    }
  }

  private var trialRemainingText: String? {
    guard case let .trial(endDate) = purchaseManager.state else { return nil }
    let description = TrialFormatter.remainingDescription(endDate: endDate)
    return String(format: "purchase_status_trial_remaining".localized, description)
  }

  private func performPurchase() {
    Task { @MainActor in
      do {
        try await purchaseManager.purchaseFullVersion()
        purchasePrompt = nil
      } catch {
        let shouldDismiss = !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false)
        if shouldDismiss {
          purchasePrompt = nil
        }
        handlePurchaseError(error, operation: .purchase)
      }
    }
  }

  private func performRestore() {
    Task { @MainActor in
      do {
        try await purchaseManager.restorePurchases()
        purchasePrompt = nil
      } catch {
        let shouldDismiss = !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false)
        if shouldDismiss {
          purchasePrompt = nil
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

    alertContent = AlertContent(
      title: operation.failureTitle,
      message: error.purchaseDisplayMessage
    )
  }
}

// 预览
#Preview {
  GeneralSettingsView(appSettings: AppSettings())
    .environmentObject(PurchaseManager())
}
