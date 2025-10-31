//
//  SettingsLayoutSupport.swift
//
//  Created by Eric Cai on 2025/10/25.
//

import SwiftUI

private struct SettingsMeasurementKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct SettingsShouldScrollKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  /// 标记当前视图是否用于窗口高度测量
  var isSettingsMeasurement: Bool {
    get { self[SettingsMeasurementKey.self] }
    set { self[SettingsMeasurementKey.self] = newValue }
  }

  /// 指示实际渲染是否应使用 ScrollView
  var settingsShouldScroll: Bool {
    get { self[SettingsShouldScrollKey.self] }
    set { self[SettingsShouldScrollKey.self] = newValue }
  }
}

private struct SettingsScrollContainer: ViewModifier {
  let explicitScrollEnabled: Bool?
  @Environment(\.settingsShouldScroll) private var defaultShouldScroll

  private var effectiveScroll: Bool {
    explicitScrollEnabled ?? defaultShouldScroll
  }

  func body(content: Content) -> some View {
    Group {
      if effectiveScroll {
        ScrollView {
          content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
        .scrollIndicators(.automatic)
      } else {
        content
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding()
      }
    }
  }
}

extension View {
  /// 为设置页面提供统一的滚动/布局容器
  func settingsContentContainer(scrollEnabled: Bool? = nil) -> some View {
    modifier(SettingsScrollContainer(explicitScrollEnabled: scrollEnabled))
  }
}
