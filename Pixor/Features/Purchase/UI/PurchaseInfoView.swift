import SwiftUI

/// 展示订阅和买断方案的购买信息页面
struct PurchaseInfoView: View {
  @EnvironmentObject private var purchaseManager: PurchaseManager
  @Environment(\.openURL) private var openURL

  let context: UpgradePromptContext?
  let onPurchase: (PurchaseProductKind) -> Void
  let onRestore: () -> Void
  let onRefreshReceipt: () -> Void
  let onClose: () -> Void

  private let featureItems: [PurchaseFeatureItem] = [
    PurchaseFeatureItem(icon: "sparkles", titleKey: "purchase_info_feature_full_access_title", descriptionKey: "purchase_info_feature_full_access_desc"),
    PurchaseFeatureItem(icon: "crop", titleKey: "purchase_info_feature_crop_title", descriptionKey: "purchase_info_feature_crop_desc"),
    PurchaseFeatureItem(icon: "doc.text.magnifyingglass", titleKey: "purchase_info_feature_exif_title", descriptionKey: "purchase_info_feature_exif_desc"),
  ]

  private let legalItems: [PurchaseLegalItem] = [
    PurchaseLegalItem(titleKey: "purchase_info_legal_terms", url: URL(string: "https://soyotube.vercel.app/terms")!),
    PurchaseLegalItem(titleKey: "purchase_info_legal_privacy", url: URL(string: "https://soyotube.vercel.app/privacy")!),
  ]

  private var linkColor: Color {
    #if os(macOS)
    Color(nsColor: .linkColor)
    #else
    Color(uiColor: .link)
    #endif
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          contextSection
          headerSection
          featureSection
          offeringSection
          legalSection
          actionSection
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

      Button(action: {
        onClose()
        onPurchase(offering.kind)
      }) {
        Text(buttonTitle(for: offering.kind))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    )
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

  private var actionSection: some View {
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

  private func buttonTitle(for kind: PurchaseProductKind) -> String {
    switch kind {
    case .subscription:
      return "purchase_button_subscribe".localized
    case .lifetime:
      return "purchase_button_lifetime".localized
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

