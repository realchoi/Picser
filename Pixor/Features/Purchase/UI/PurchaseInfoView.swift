import SwiftUI

/// 展示订阅和买断方案的购买信息页面
struct PurchaseInfoView: View {
  @EnvironmentObject private var purchaseManager: PurchaseManager
  @Environment(\.openURL) private var openURL
  @ObservedObject private var localizationManager = LocalizationManager.shared

  let context: UpgradePromptContext?
  let onPurchase: (PurchaseProductKind) -> Void
  let onRestore: () -> Void
  let onRefreshReceipt: () -> Void
  let onClose: () -> Void

  @State private var selectedProductKind: PurchaseProductKind?

  private let featureItems: [PurchaseFeatureItem] = [
    PurchaseFeatureItem(icon: "sparkles", titleKey: "purchase_info_feature_full_access_title", descriptionKey: "purchase_info_feature_full_access_desc"),
    PurchaseFeatureItem(icon: "crop", titleKey: "purchase_info_feature_crop_title", descriptionKey: "purchase_info_feature_crop_desc"),
    PurchaseFeatureItem(icon: "doc.text.magnifyingglass", titleKey: "purchase_info_feature_exif_title", descriptionKey: "purchase_info_feature_exif_desc"),
  ]

  private let legalItems: [PurchaseLegalItem] = [
    PurchaseLegalItem(titleKey: "purchase_info_legal_terms", url: URL(string: "https://soyotube.vercel.app/terms")!),
    PurchaseLegalItem(titleKey: "purchase_info_legal_privacy", url: URL(string: "https://soyotube.vercel.app/privacy")!),
  ]

  private var selectedOffering: PurchaseOffering? {
    guard let selectedProductKind else {
      return purchaseManager.offerings.first
    }
    return purchaseManager.offerings.first(where: { $0.kind == selectedProductKind })
  }

  private var isSubscriptionTrialAvailable: Bool {
    guard let subscription = purchaseManager.subscriptionOffering,
          subscription.configuration.introductoryTrialDuration != nil else {
      return false
    }

    switch purchaseManager.state {
    case .unknown, .onboarding, .trial:
      return true
    case .trialExpired, .subscriber, .subscriberLapsed, .lifetime, .revoked:
      return false
    }
  }

  private var linkColor: Color {
    #if os(macOS)
    Color(nsColor: .linkColor)
    #else
    Color(uiColor: .link)
    #endif
  }

  private func ensureValidSelection() {
    guard !purchaseManager.offerings.isEmpty else {
      if selectedProductKind != nil {
        selectedProductKind = nil
      }
      return
    }

    if let selectedProductKind,
       purchaseManager.offerings.contains(where: { $0.kind == selectedProductKind }) {
      return
    }

    selectedProductKind = purchaseManager.offerings.first?.kind
  }

  private func primaryActionTitle(for offering: PurchaseOffering) -> String {
    switch offering.kind {
    case .subscription:
      return isSubscriptionTrialAvailable ? "purchase_primary_trial_button".localized : "purchase_primary_subscribe_button".localized
    case .lifetime:
      return "purchase_primary_lifetime_button".localized
    }
  }

  private func primaryActionSubtitle(for offering: PurchaseOffering) -> String? {
    switch offering.kind {
    case .subscription:
      if isSubscriptionTrialAvailable {
        return String(format: "purchase_primary_trial_subtitle".localized, offering.product.displayPrice)
      } else {
        return String(format: "purchase_primary_subscribe_subtitle".localized, offering.product.displayPrice)
      }
    case .lifetime:
      return String(format: "purchase_primary_lifetime_subtitle".localized, offering.product.displayPrice)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          contextSection
          headerSection
          featureSection
          offeringSection
          primaryActionSection
          legalSection
          supportActionSection
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .padding(.top, 16)
      }
      .navigationTitle("purchase_info_title".localized)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("close_button".localized) { onClose() }
        }
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: 420, minHeight: 540)
    .onAppear { ensureValidSelection() }
    .onChange(of: purchaseManager.offerings) {
      ensureValidSelection()
    }
  }

  @ViewBuilder
  private var contextSection: some View {
    if let context {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "lightbulb")
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 28, height: 28)
        Text(context.message)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.accentColor.opacity(0.12))
      )
      .accessibilityElement(children: .combine)
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("purchase_info_headline".localized)
        .font(.title2)
        .fontWeight(.semibold)
      Text("purchase_info_description".localized)
        .font(.body)
        .foregroundStyle(.secondary)
    }
  }

  private var featureSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("purchase_info_features_title".localized)
        .font(.headline)
      ForEach(featureItems) { item in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: item.icon)
            .font(.title3)
            .foregroundStyle(Color.accentColor)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
              .font(.subheadline)
              .fontWeight(.medium)
            Text(item.description)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var offeringSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("purchase_info_offerings_title".localized)
        .font(.headline)

      if purchaseManager.offerings.isEmpty {
        HStack(spacing: 12) {
          ProgressView()
          Text("purchase_product_loading".localized)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(purchaseManager.offerings) { offering in
            offeringRow(for: offering)
          }
        }
      }
    }
  }

  private func offeringRow(for offering: PurchaseOffering) -> some View {
    let isSelected = offering.kind == selectedProductKind || (selectedProductKind == nil && offering.id == purchaseManager.offerings.first?.id)

    return Button(action: {
      withAnimation(.easeInOut(duration: 0.2)) {
        selectedProductKind = offering.kind
      }
    }) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(offering.product.displayName)
            .font(.subheadline)
            .fontWeight(.semibold)
          Spacer()
          Text(offering.product.displayPrice)
            .font(.subheadline)
        }

        if let trialDescription = trialText(for: offering) {
          Text(trialDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 16)
      .padding(.horizontal, 16)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var primaryActionSection: some View {
    if let offering = selectedOffering {
      VStack(alignment: .leading, spacing: 12) {
        Button(action: {
          onClose()
          onPurchase(offering.kind)
        }) {
          Text(primaryActionTitle(for: offering))
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        if let subtitle = primaryActionSubtitle(for: offering) {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .contain)
    }
  }

  private var legalSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("purchase_info_legal_title".localized)
        .font(.headline)

      ForEach(legalItems) { item in
        Button(action: { openURL(item.url) }) {
          Text(item.title)
            .font(.footnote)
            .underline()
            .foregroundStyle(linkColor)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var supportActionSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("purchase_info_restore_button".localized) {
        onRestore()
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)

      Button("purchase_info_refresh_receipt_button".localized) {
        onRefreshReceipt()
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)

      Text("purchase_info_restore_note".localized)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Text("purchase_info_refresh_receipt_note".localized)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func trialText(for offering: PurchaseOffering) -> String? {
    guard offering.kind == .subscription,
          let duration = offering.configuration.introductoryTrialDuration else {
      return nil
    }

    let days = max(Int(duration / (24 * 60 * 60)), 0)
    guard days > 0 else { return nil }
    return String(format: "purchase_info_trial_note".localized, days)
  }

}

private struct PurchaseFeatureItem: Identifiable {
  let id = UUID()
  let icon: String
  let titleKey: String
  let descriptionKey: String

  var title: String { titleKey.localized }
  var description: String { descriptionKey.localized }
}

private struct PurchaseLegalItem: Identifiable {
  let id = UUID()
  let titleKey: String
  let url: URL

  var title: String { titleKey.localized }
}

