// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// App-private storage for cached card photos read from smart card DG2.
///
/// Photos are cached in memory and in the app's cache directory keyed by
/// the holder identity line (and bare name without identifier).
/// Card access numbers are never persisted here; only released photo bytes are.
@MainActor
internal enum CardPhotoStore {
  // MARK: - Constants

  private static let directoryName = "CardPhotos"
  private static let fileExtension = ".jpg"
  private static let photoWidth = 130
  private static let photoHeight = 160
  private static let bitsPerComponent = 8
  private static let bytesPerPixel = 4
  private static let headRadiusRatio: CGFloat = 0.18
  private static let headCenterVerticalRatio: CGFloat = 0.58
  private static let shoulderVerticalRatio: CGFloat = 0.12
  private static let shoulderHeightRatio: CGFloat = 0.32
  private static let shoulderWidthRatio: CGFloat = 0.64
  private static let shoulderHorizontalRatio: CGFloat = 0.18
  private static let backgroundRed: CGFloat = 0.88
  private static let backgroundGreen: CGFloat = 0.90
  private static let backgroundBlue: CGFloat = 0.94
  private static let silhouetteRed: CGFloat = 0.40
  private static let silhouetteGreen: CGFloat = 0.45
  private static let silhouetteBlue: CGFloat = 0.55
  private static let fullAlpha: CGFloat = 1.0
  private static let halfFactor: CGFloat = 0.5
  private static let circleTurns: CGFloat = 2.0
  private static let fullTurnRadians: CGFloat = .pi * circleTurns

  // MARK: - State

  private static var cache: [String: Data] = [:]

  private static var storageDirectory: URL? {
    guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      return nil
    }
    let dir = cacheDir.appendingPathComponent(directoryName, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func sanitizedKey(_ key: String) -> String {
    key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
  }

  // MARK: - API

  internal static func getPhoto(for holder: String) -> Data? {
    if let data = cache[holder] {
      return data
    }
    let parts = holder.split(separator: " ")
    if parts.count > 1, let last = parts.last, last.contains(where: \.isNumber) {
      let bare = String(parts.dropLast().joined(separator: " "))
      if let data = cache[bare] {
        return data
      }
    }
    guard let dir = storageDirectory else { return nil }
    let file = dir.appendingPathComponent(sanitizedKey(holder) + fileExtension)
    if let data = try? Data(contentsOf: file) {
      cache[holder] = data
      return data
    }
    if parts.count > 1, let last = parts.last, last.contains(where: \.isNumber) {
      let bare = String(parts.dropLast().joined(separator: " "))
      let bareFile = dir.appendingPathComponent(sanitizedKey(bare) + fileExtension)
      if let data = try? Data(contentsOf: bareFile) {
        cache[holder] = data
        return data
      }
    }
    return nil
  }

  internal static func savePhoto(_ data: Data, for holder: String) {
    cache[holder] = data
    let parts = holder.split(separator: " ")
    if parts.count > 1, let last = parts.last, last.contains(where: \.isNumber) {
      let bare = String(parts.dropLast().joined(separator: " "))
      cache[bare] = data
    }
    guard let dir = storageDirectory else { return }
    let file = dir.appendingPathComponent(sanitizedKey(holder) + fileExtension)
    try? data.write(to: file, options: .atomic)
  }

  internal static func photoFileURL(for holder: String) -> URL? {
    guard let dir = storageDirectory else { return nil }
    let file = dir.appendingPathComponent(sanitizedKey(holder) + fileExtension)
    if FileManager.default.fileExists(atPath: file.path) {
      return file
    }
    if let data = getPhoto(for: holder) {
      try? data.write(to: file, options: .atomic)
      return file
    }
    return nil
  }

  internal static func deletePhoto(for holder: String) {
    cache.removeValue(forKey: holder)
    let parts = holder.split(separator: " ")
    if parts.count > 1, let last = parts.last, last.contains(where: \.isNumber) {
      let bare = String(parts.dropLast().joined(separator: " "))
      cache.removeValue(forKey: bare)
      if let dir = storageDirectory {
        try? FileManager.default.removeItem(
          at: dir.appendingPathComponent(sanitizedKey(bare) + fileExtension))
      }
    }
    if let dir = storageDirectory {
      try? FileManager.default.removeItem(
        at: dir.appendingPathComponent(sanitizedKey(holder) + fileExtension))
    }
  }

  internal static func clear() {
    cache.removeAll()
    if let dir = storageDirectory {
      try? FileManager.default.removeItem(at: dir)
    }
  }

  private static func drawSilhouette(in context: CGContext, width: Int, height: Int) {
    context.setFillColor(
      red: silhouetteRed,
      green: silhouetteGreen,
      blue: silhouetteBlue,
      alpha: fullAlpha
    )
    let headRadius = CGFloat(width) * headRadiusRatio
    let headCenter = CGPoint(
      x: CGFloat(width) * halfFactor,
      y: CGFloat(height) * headCenterVerticalRatio
    )
    context.addArc(
      center: headCenter,
      radius: headRadius,
      startAngle: 0,
      endAngle: fullTurnRadians,
      clockwise: false
    )
    context.fillPath()

    let shoulderRect = CGRect(
      x: CGFloat(width) * shoulderHorizontalRatio,
      y: CGFloat(height) * shoulderVerticalRatio,
      width: CGFloat(width) * shoulderWidthRatio,
      height: CGFloat(height) * shoulderHeightRatio
    )
    context.addEllipse(in: shoulderRect)
    context.fillPath()
  }

  /// Generates a synthetic photo for demonstration and unit test environments.
  internal static func syntheticSamplePhoto(name: String) -> Data {
    _ = name
    let width = photoWidth
    let height = photoHeight
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return Data()
    }

    context.setFillColor(
      red: backgroundRed,
      green: backgroundGreen,
      blue: backgroundBlue,
      alpha: fullAlpha
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawSilhouette(in: context, width: width, height: height)

    guard let image = context.makeImage() else { return Data() }
    let mutableData = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        mutableData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      return Data()
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return mutableData as Data
  }
}
