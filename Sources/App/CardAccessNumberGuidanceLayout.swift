// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreGraphics
import Foundation

/// Geometry and sizing rules for the Card Access Number (CAN) guidance view.
internal enum CardAccessNumberGuidanceLayout {
  /// The reference pixel width of the identity card instruction asset.
  internal static let cardWidth: CGFloat = 800

  /// The reference pixel height of the identity card instruction asset.
  internal static let cardHeight: CGFloat = 500

  /// Aspect ratio of the card illustration (width / height).
  internal static let cardAspectRatio: CGFloat = cardWidth / cardHeight

  /// X-coordinate of the CAN and QR code bounding box in reference pixels.
  internal static let highlightX: CGFloat = 320

  /// Y-coordinate of the CAN and QR code bounding box in reference pixels.
  internal static let highlightY: CGFloat = 248

  /// Width of the CAN and QR code bounding box in reference pixels.
  internal static let highlightWidth: CGFloat = 96

  /// Height of the CAN and QR code bounding box in reference pixels.
  internal static let highlightHeight: CGFloat = 146

  /// Corner radius of the green highlight rectangle in points.
  internal static let highlightCornerRadius: CGFloat = 4

  /// Line width of the green highlight rectangle in points.
  internal static let highlightLineWidth: CGFloat = 2.5

  /// Corner radius of the card illustration in points.
  internal static let cardCornerRadius: CGFloat = 10

  /// Minimum scale factor for the guidance text under dynamic type.
  internal static let minimumTextScale: CGFloat = 0.8

  /// Spacing between guidance text and card illustration in points.
  internal static let contentSpacing: CGFloat = 16

  /// Computes the bounding rectangle for the CAN and QR code highlight within the rendered card size.
  internal static func highlightRect(in size: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else {
      return .zero
    }
    let scaleX = size.width / cardWidth
    let scaleY = size.height / cardHeight
    return CGRect(
      x: highlightX * scaleX,
      y: highlightY * scaleY,
      width: highlightWidth * scaleX,
      height: highlightHeight * scaleY
    )
  }

  /// Computes the proportional height of the card for a given container width.
  internal static func cardHeight(containerWidth: CGFloat) -> CGFloat {
    guard containerWidth > 0 else {
      return 0
    }
    return containerWidth / cardAspectRatio
  }
}
