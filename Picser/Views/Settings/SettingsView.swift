//
//  SettingsView.swift
//
//  Created by Eric Cai on 2025/8/19.
//

import SwiftUI

struct SettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @EnvironmentObject private var tagService: TagService
  @State private var validationErrors: [String] = []
  @State private var selectedTab: SettingsTab = .general
  @State private var desiredContentHeight: CGFloat = 0
  @State private var tabHeights: [SettingsTab: CGFloat] = [:]
  @State private var validationAreaHeight: CGFloat = 0
  @State private var tabScrollNeeds: [SettingsTab: Bool] = [:]

  private let minWindowHeight: CGFloat = 360
  /// 大部分标签页使用的默认最大高度
  private let defaultMaxWindowHeight: CGFloat = 720
  /// 标签管理页面控件较多，需要更高的目标高度
  private let tagsMaxWindowHeight: CGFloat = 860
  private let fallbackHeight: CGFloat = 420
  private let tabBarHeight: CGFloat = 48

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $selectedTab) {
        // 通用设置页面
        IntrinsicTabContainer(tab: .general, shouldScroll: {
          tabScrollNeeds[.general] ?? false
        }) {
          GeneralSettingsView(appSettings: appSettings)
        }
        .tag(SettingsTab.general)
          .tabItem {
            Label(
              L10n.string("general_tab"),
              systemImage: "gearshape")
          }

        // 快捷键设置页面
        IntrinsicTabContainer(tab: .keyboard, shouldScroll: {
          tabScrollNeeds[.keyboard] ?? false
        }) {
          KeyboardSettingsView(appSettings: appSettings)
        }
        .tag(SettingsTab.keyboard)
          .tabItem {
            Label(
              L10n.string("keyboard_tab"),
              systemImage: "keyboard")
          }

        // 显示设置页面
        IntrinsicTabContainer(tab: .display, shouldScroll: {
          tabScrollNeeds[.display] ?? false
        }) {
          DisplaySettingsView(appSettings: appSettings)
        }
        .tag(SettingsTab.display)
          .tabItem {
            Label(
              L10n.string("display_tab"), systemImage: "display"
            )
          }

        // 标签管理页面
        IntrinsicTabContainer(tab: .tags, shouldScroll: {
          tabScrollNeeds[.tags] ?? false
        }) {
          TagSettingsView(tagService: tagService)
        }
        .tag(SettingsTab.tags)
          .tabItem {
            Label(
              L10n.string("tag_settings_tab"),
              systemImage: "tag"
            )
          }

        // 缓存管理页面
        IntrinsicTabContainer(tab: .cache, shouldScroll: {
          tabScrollNeeds[.cache] ?? false
        }) {
          CacheSettingsView()
        }
        .tag(SettingsTab.cache)
          .tabItem {
            Label(
              L10n.string("cache_tab"),
              systemImage: "externaldrive"
            )
          }

        // 关于页面
        IntrinsicTabContainer(tab: .about, shouldScroll: {
          tabScrollNeeds[.about] ?? false
        }) {
          AboutView()
        }
        .tag(SettingsTab.about)
          .tabItem {
            Label(
              L10n.string("about_tab"),
              systemImage: "person.circle"
            )
          }
      }
      .tabViewStyle(.automatic)

      if !validationErrors.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          ForEach(validationErrors, id: \.self) { err in
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
              Text(err)
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
        }
        .padding(12)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(key: ValidationHeightKey.self, value: proxy.size.height)
          }
        )
      }
    }
    .frame(minWidth: 400, idealWidth: 480, maxWidth: 560)
    .background(
      SettingsWindowResizer(
        targetContentHeight: desiredContentHeight == 0 ? fallbackHeight : desiredContentHeight,
        minContentHeight: minWindowHeight,
        maxContentHeight: maxHeight(for: selectedTab),
        animate: true,
        animationDuration: 0.3
      )
    )
    .onPreferenceChange(TabContentHeightKey.self) { heights in
      tabHeights.merge(heights) { _, new in new }
      recalcScrollNeeds()
      syncDesiredContentHeight()
    }
    .onPreferenceChange(ValidationHeightKey.self) { height in
      validationAreaHeight = height
      recalcScrollNeeds()
      syncDesiredContentHeight()
    }
    .onAppear {
      validateSettings()
      selectedTab = .general
      validationAreaHeight = 0
      recalcScrollNeeds()
      syncDesiredContentHeight()
    }
    .onChange(of: selectedTab) { _, newTab in
      syncDesiredContentHeight(for: newTab)
    }
    .onChange(of: validationErrors.isEmpty) { _, isEmpty in
      if isEmpty {
        validationAreaHeight = 0
        syncDesiredContentHeight()
      }
    }
    .onChange(of: appSettings.zoomSensitivity) { validateSettings() }
    .onChange(of: appSettings.minZoomScale) { validateSettings() }
    .onChange(of: appSettings.maxZoomScale) { validateSettings() }
    .onChange(of: appSettings.appLanguage) { validateSettings() }
  }

  /// 校验设置项并收集需要提示给用户的错误信息
  private func validateSettings() {
    validationErrors = appSettings.validateSettings()
  }

  /// 计算目标内容高度并通知窗口重置尺寸
  private func syncDesiredContentHeight(for tab: SettingsTab? = nil) {
    let targetTab = tab ?? selectedTab
    guard let contentHeight = tabHeights[targetTab] else { return }
    let maxWindowHeight = maxHeight(for: targetTab)
    let totalHeight = contentHeight + validationAreaHeight + tabBarHeight
    let clamped = max(minWindowHeight, min(totalHeight, maxWindowHeight))
    desiredContentHeight = clamped
    tabScrollNeeds[targetTab] = totalHeight > maxWindowHeight
  }

  /// 根据测量数据决定每个标签页是否需要在真实渲染时启用滚动
  private func recalcScrollNeeds() {
    for (tab, height) in tabHeights {
      let maxHeight = maxHeight(for: tab)
      tabScrollNeeds[tab] = height + validationAreaHeight + tabBarHeight > maxHeight
    }
  }

  /// 针对不同标签页返回优先的窗口高度上限
  private func maxHeight(for tab: SettingsTab) -> CGFloat {
    switch tab {
    case .tags:
      return tagsMaxWindowHeight
    default:
      return defaultMaxWindowHeight
    }
  }
}

// 预览
#Preview {
  SettingsView(appSettings: AppSettings())
    .environmentObject(PurchaseManager())
    .environmentObject(TagService())
}

// MARK: - 动态尺寸
private struct TabContentHeightKey: PreferenceKey {
  static var defaultValue: [SettingsTab: CGFloat] = [:]
  static func reduce(value: inout [SettingsTab: CGFloat], nextValue: () -> [SettingsTab: CGFloat]) {
    value.merge(nextValue()) { _, new in new }
  }
}

private struct ValidationHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(0, nextValue())
  }
}

private struct IntrinsicTabContainer<Content: View>: View {
  let tab: SettingsTab
  let shouldScroll: () -> Bool
  let content: () -> Content

  init(tab: SettingsTab, shouldScroll: @escaping () -> Bool, @ViewBuilder content: @escaping () -> Content) {
    self.tab = tab
    self.shouldScroll = shouldScroll
    self.content = content
  }

  var body: some View {
    content()
      .environment(\.isSettingsMeasurement, false)
      .environment(\.settingsShouldScroll, shouldScroll())
      .overlay(alignment: .topLeading) {
        MeasurementOverlay(tab: tab, content: content)
      }
  }
}

private struct MeasurementOverlay<Content: View>: View {
  let tab: SettingsTab
  let content: () -> Content

  var body: some View {
    content()
      .environment(\.isSettingsMeasurement, true)
      .environment(\.settingsShouldScroll, false)
      .settingsContentContainer(scrollEnabled: false)
      .fixedSize(horizontal: false, vertical: true)
      .background(
        GeometryReader { proxy in
          Color.clear
            .preference(key: TabContentHeightKey.self, value: [tab: proxy.size.height])
        }
      )
      .hidden()
      .allowsHitTesting(false)
  }
}
