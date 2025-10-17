//
//  AlertContent.swift
//
//  Created by Eric Cai on 2025/9/19.
//

import Foundation

/// 通用弹窗内容模型，用于跨视图共享标题与正文文案
struct AlertContent: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let message: String
}
