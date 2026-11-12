// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreGraphics
import Testing

@testable import RefineIDTestHost

/// Tests the geometric calculations that center the instruction text in
/// the visible gap between the card illustration and the system NFC sheet.
@Suite
internal struct NearFieldHoldLayoutTests {
  private static let iPhoneSeWidth: CGFloat = 375
  private static let iPhoneSeHeight: CGFloat = 667
  private static let iPhoneSeBottomInset: CGFloat = 0

  private static let iPhone15ProWidth: CGFloat = 393
  private static let iPhone15ProHeight: CGFloat = 852
  private static let iPhone15ProBottomInset: CGFloat = 34

  private static let iPhoneProMaxWidth: CGFloat = 430
  private static let iPhoneProMaxHeight: CGFloat = 932
  private static let iPhoneProMaxBottomInset: CGFloat = 34

  private static let zeroScale: CGFloat = 0
  private static let unscaledText: CGFloat = 1
  private static let tolerance: CGFloat = 0.5

  @Test("Card aspect ratio reflects the illustration dimensions")
  internal func cardAspectRatio() {
    let expectedRatio = NearFieldHoldLayout.cardPixelWidth / NearFieldHoldLayout.cardPixelHeight
    #expect(NearFieldHoldLayout.cardAspectRatio == expectedRatio)
  }

  @Test("Minimum text scale allows compact dynamic type shrinkage")
  internal func minimumTextScale() {
    #expect(NearFieldHoldLayout.minimumTextScale > Self.zeroScale)
    #expect(NearFieldHoldLayout.minimumTextScale <= Self.unscaledText)
  }

  @Test("NFC sheet height includes home indicator safe area inset")
  internal func nfcSheetHeight() {
    #expect(
      NearFieldHoldLayout.nfcSheetHeight(safeAreaBottomInset: Self.iPhoneSeBottomInset)
        == NearFieldHoldLayout.nfcSheetBaseHeight
    )
    #expect(
      NearFieldHoldLayout.nfcSheetHeight(safeAreaBottomInset: Self.iPhone15ProBottomInset)
        == NearFieldHoldLayout.nfcSheetBaseHeight + Self.iPhone15ProBottomInset
    )
  }

  @Test("Visible gap is positive across supported iPhone dimensions")
  internal func visibleGapAcrossDevices() {
    let seGap = NearFieldHoldLayout.visibleGapHeight(
      containerWidth: Self.iPhoneSeWidth,
      containerHeight: Self.iPhoneSeHeight,
      safeAreaBottomInset: Self.iPhoneSeBottomInset
    )
    #expect(seGap > NearFieldHoldLayout.minimumGapHeight)

    let proGap = NearFieldHoldLayout.visibleGapHeight(
      containerWidth: Self.iPhone15ProWidth,
      containerHeight: Self.iPhone15ProHeight,
      safeAreaBottomInset: Self.iPhone15ProBottomInset
    )
    #expect(proGap > NearFieldHoldLayout.minimumGapHeight)

    let maxGap = NearFieldHoldLayout.visibleGapHeight(
      containerWidth: Self.iPhoneProMaxWidth,
      containerHeight: Self.iPhoneProMaxHeight,
      safeAreaBottomInset: Self.iPhoneProMaxBottomInset
    )
    #expect(maxGap > proGap)
  }
}
