//
//  ImageCropper.swift
//  Pixor
//
//  Pure utility to crop image files and save results.
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageCropperError: Error {
  case cannotOpenSource
  case cannotReadImage
  case invalidCropRect
  case cannotCreateDestination
  case cannotFinalize
}

enum ImageCropper {
  /// 从源 URL 裁剪原图（按像素坐标，原始方向），返回 NSImage
  static func crop(url: URL, cropRect: CGRect) throws -> NSImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw ImageCropperError.cannotOpenSource
    }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
      throw ImageCropperError.cannotReadImage
    }

    // 将输入矩形夹取到有效范围
    let imageRect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
    let r = cropRect.integral.intersection(imageRect)
    guard !r.isEmpty else { throw ImageCropperError.invalidCropRect }

    guard let cropped = cg.cropping(to: r) else {
      throw ImageCropperError.invalidCropRect
    }

    return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
  }

  /// 保存图像到指定 URL（维持原扩展名格式，或按 URL 扩展名推断）
  static func save(image: NSImage, to destURL: URL) throws {
    let ext = destURL.pathExtension.lowercased()

    // 优先处理 HEIC：用 ImageIO 按 UTI 写入
    if ext == "heic" {
      if #available(macOS 11.0, *) {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let dst = CGImageDestinationCreateWithURL(destURL as CFURL, UTType.heic.identifier as CFString, 1, nil) {
          CGImageDestinationAddImage(dst, cg, nil)
          if CGImageDestinationFinalize(dst) { return }
        }
      }
      // 若 HEIC 写入不可用，则抛错让上层处理
      throw ImageCropperError.cannotFinalize
    }

    // 其他常见格式使用 NSBitmapImageRep
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      throw ImageCropperError.cannotReadImage
    }

    let fileType: NSBitmapImageRep.FileType = {
      switch ext {
      case "jpg", "jpeg": return .jpeg
      case "png": return .png
      case "gif": return .gif
      case "tiff", "tif": return .tiff
      case "bmp": return .bmp
      case "jp2", "jpf", "j2k", "jpeg2000": return .jpeg2000
      default: return .png
      }
    }()

    guard let data = rep.representation(using: fileType, properties: [:]) else {
      throw ImageCropperError.cannotFinalize
    }
    try data.write(to: destURL)
  }
}
