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
    if purchaseManager.isTrialBannerDismissed || purchaseManager.hasOwnedLicense {
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
            title: localized("trial_expired_title", fallback: "试用已结束"),
            message: localized("trial_expired_subtitle", fallback: "试用已结束，请升级解锁全部功能。"),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .subscriberLapsed:
        let fallbackTitle = "订阅已到期"
        let fallbackMessage = "订阅已到期，请续订或恢复购买以继续使用高级功能。"
        bannerContainer {
          TrialExpiredBanner(
            title: localized("subscription_lapsed_title", fallback: fallbackTitle),
            message: localized("subscription_lapsed_subtitle", fallback: fallbackMessage),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .revoked:
        let fallbackTitle = "权限已撤销"
        let fallbackMessage = "检测到账户存在异常，已暂时停用高级功能，请尝试恢复购买或联系支持。"
        bannerContainer {
          TrialExpiredBanner(
            title: localized("purchase_revoked_title", fallback: fallbackTitle),
            message: localized("purchase_revoked_subtitle", fallback: fallbackMessage),
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
