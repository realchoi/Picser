//
//  AboutView.swift
//
//  Created by Eric Cai on 2025/10/31.
//

import SwiftUI

/// 关于页面：展示应用简介、作者信息与联系方式。
struct AboutView: View {
  /// 关于信息中左侧标签的标准宽度。
  private let labelWidth: CGFloat = 90

  /// 作者/团队信息配置。
  private let authorName = "Eric Cai (Soyotube)"
  private let websiteURL = URL(string: "https://soyotube.com")!
  private let contactEmailAddress = "mallocai@foxmail.com"
  private var contactEmailURL: URL? {
    URL(string: "mailto:\(contactEmailAddress)")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(l10n: "about_title")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      infoContent

      Spacer(minLength: 0)
    }
    .settingsContentContainer()
  }

  private var infoContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(l10n: "about_tagline")
        .font(.body)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 10) {
        infoRow(labelKey: "about_author_label") {
          Text(authorName)
        }

        infoRow(labelKey: "about_website_label") {
          Link(websiteURL.absoluteString, destination: websiteURL)
        }

        infoRow(labelKey: "about_contact_label") {
          if let url = contactEmailURL {
            Link(contactEmailAddress, destination: url)
          } else {
            Text(contactEmailAddress)
          }
        }
      }
      .padding(.top, 6)
    }
  }

  @ViewBuilder
  private func infoRow<Content: View>(labelKey: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(l10n: labelKey)
        .font(.subheadline)
        .fontWeight(.medium)
        .frame(width: labelWidth, alignment: .leading)

      content()
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
