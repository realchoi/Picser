//
//  ContentView+TrialBanner.swift
//
//  Created by Eric Cai on 2025/9/19.
//

import SwiftUI

@MainActor
extension ContentView {
  /// 根据订阅状态展示试用提醒条
  @ViewBuilder
  var trialBannerInset: some View {
    if purchaseManager.isTrialBannerDismissed || purchaseManager.hasActiveLicense {
      EmptyView()
    } else {
      switch purchaseManager.state {
      case let .trial(status):
        bannerContainer {
          TrialStatusBanner(status: status) {
            withAnimation { purchaseManager.dismissTrialBanner() }
          }
        }
      case .trialExpired:
        bannerContainer {
          TrialExpiredBanner(
            title: localized("trial_expired_title"),
            message: localized("trial_expired_subtitle"),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case let .subscriberLapsed(status):
        bannerContainer {
          SubscriptionGraceBanner(
            status: status,
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .revoked:
        bannerContainer {
          TrialExpiredBanner(
            title: localized("purchase_revoked_title"),
            message: localized("purchase_revoked_subtitle"),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .subscriber, .lifetime, .onboarding, .unknown:
        EmptyView()
      }
    }
  }
}

private extension ContentView {
  @ViewBuilder
  func bannerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack {
      Spacer()
      content()
        .frame(maxWidth: 520)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 20)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}
