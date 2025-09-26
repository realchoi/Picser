//
//  ContentView+Transform.swift
//  Pixor
//
//  Created by Codex on 2025/2/14.
//

import SwiftUI

@MainActor
extension ContentView {
  /// 逆时针旋转当前图片 90 度
  func rotateCCW() {
    performIfEntitled(.transform) {
      imageTransform.rotation = imageTransform.rotation.rotated(by: -90)
    }
  }

  /// 顺时针旋转当前图片 90 度
  func rotateCW() {
    performIfEntitled(.transform) {
      imageTransform.rotation = imageTransform.rotation.rotated(by: 90)
    }
  }

  /// 水平镜像当前图片
  func mirrorHorizontal() {
    performIfEntitled(.transform) {
      imageTransform.mirrorH.toggle()
    }
  }

  /// 垂直镜像当前图片
  func mirrorVertical() {
    performIfEntitled(.transform) {
      imageTransform.mirrorV.toggle()
    }
  }

  /// 重置当前图片的所有几何变换
  func resetTransform() {
    imageTransform = .identity
  }
}
