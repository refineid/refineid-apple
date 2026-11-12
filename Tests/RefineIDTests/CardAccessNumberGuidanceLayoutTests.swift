// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreGraphics
import Testing

@testable import RefineIDTestHost

/// Tests the geometric calculations for the Card Access Number (CAN) guidance view.
@Suite
internal struct CardAccessNumberGuidanceLayoutTests {
  private static let iPhoneSeCardWidth: CGFloat = 343
  private static let iPhone15ProCardWidth: CGFloat = 361
  private static let iPhoneProMaxCardWidth: CGFloat = 398

  private static let zeroDimension: CGFloat = 0
  private static let negativeDimension: CGFloat = -100
  private static let unscaledText: CGFloat = 1
  private static let tolerance: CGFloat = 0.001

  @Test("Card aspect ratio reflects the illustration dimensions")
  internal func cardAspectRatio() {
    let expectedRatio =
      CardAccessNumberGuidanceLayout.cardWidth / CardAccessNumberGuidanceLayout.cardHeight
    #expect(abs(CardAccessNumberGuidanceLayout.cardAspectRatio - expectedRatio) < Self.tolerance)
  }

  @Test("Minimum text scale is within valid range")
  internal func minimumTextScale() {
    #expect(CardAccessNumberGuidanceLayout.minimumTextScale > Self.zeroDimension)
    #expect(CardAccessNumberGuidanceLayout.minimumTextScale <= Self.unscaledText)
  }

  @Test("Highlight rect fits strictly within full card dimensions")
  internal func highlightWithinFullCardBounds() {
    let fullSize = CGSize(
      width: CardAccessNumberGuidanceLayout.cardWidth,
      height: CardAccessNumberGuidanceLayout.cardHeight
    )
    let rect = CardAccessNumberGuidanceLayout.highlightRect(in: fullSize)

    #expect(rect.origin.x >= Self.zeroDimension)
    #expect(rect.origin.y >= Self.zeroDimension)
    #expect(rect.maxX <= CardAccessNumberGuidanceLayout.cardWidth)
    #expect(rect.maxY <= CardAccessNumberGuidanceLayout.cardHeight)
    #expect(rect.width == CardAccessNumberGuidanceLayout.highlightWidth)
    #expect(rect.height == CardAccessNumberGuidanceLayout.highlightHeight)
  }

  @Test("Highlight rect scales proportionally across iPhone device sizes")
  internal func highlightScalesAcrossDevices() {
    let widths = [
      Self.iPhoneSeCardWidth,
      Self.iPhone15ProCardWidth,
      Self.iPhoneProMaxCardWidth,
    ]

    for width in widths {
      let height = CardAccessNumberGuidanceLayout.cardHeight(containerWidth: width)
      #expect(height > Self.zeroDimension)

      let size = CGSize(width: width, height: height)
      let rect = CardAccessNumberGuidanceLayout.highlightRect(in: size)

      #expect(rect.origin.x >= Self.zeroDimension)
      #expect(rect.origin.y >= Self.zeroDimension)
      #expect(rect.maxX <= width + Self.tolerance)
      #expect(rect.maxY <= height + Self.tolerance)
      #expect(rect.width > Self.zeroDimension)
      #expect(rect.height > Self.zeroDimension)

      let expectedScaleX = width / CardAccessNumberGuidanceLayout.cardWidth
      let expectedWidth = CardAccessNumberGuidanceLayout.highlightWidth * expectedScaleX
      #expect(abs(rect.width - expectedWidth) < Self.tolerance)
    }
  }

  @Test("Zero or negative bounds return zero rect")
  internal func zeroOrNegativeBounds() {
    let zeroSize = CGSize(width: Self.zeroDimension, height: Self.zeroDimension)
    #expect(CardAccessNumberGuidanceLayout.highlightRect(in: zeroSize) == .zero)

    let negativeSize = CGSize(width: Self.negativeDimension, height: Self.negativeDimension)
    #expect(CardAccessNumberGuidanceLayout.highlightRect(in: negativeSize) == .zero)

    #expect(
      CardAccessNumberGuidanceLayout.cardHeight(containerWidth: Self.zeroDimension)
        == Self.zeroDimension
    )
    #expect(
      CardAccessNumberGuidanceLayout.cardHeight(containerWidth: Self.negativeDimension)
        == Self.zeroDimension
    )
  }
}
