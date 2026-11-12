// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreGraphics

/// Dimensions and geometry calculations for the NFC hold instruction view.
///
/// Behind the system NFC sheet, the card illustration fills the top
/// edge to edge, and the instruction sentence is centered in the
/// visible gap between the card illustration and the sheet.
internal enum NearFieldHoldLayout {
  internal static let cardPixelWidth: CGFloat = 800
  internal static let cardPixelHeight: CGFloat = 500
  internal static let cardAspectRatio: CGFloat = cardPixelWidth / cardPixelHeight
  internal static let textHorizontalPadding: CGFloat = 24
  internal static let minimumTextScale: CGFloat = 0.8
  internal static let minimumGapHeight: CGFloat = 0
  internal static let spacerMinLength: CGFloat = 0

  /// The height of the system CoreNFC sheet content, excluding the
  /// home indicator safe area inset.
  internal static let nfcSheetBaseHeight: CGFloat = 338

  /// The height of the card illustration scaled to fit the given container width.
  internal static func cardHeight(containerWidth: CGFloat) -> CGFloat {
    containerWidth / cardAspectRatio
  }

  /// The total height occupied by the system CoreNFC sheet including safe area inset.
  internal static func nfcSheetHeight(safeAreaBottomInset: CGFloat) -> CGFloat {
    nfcSheetBaseHeight + safeAreaBottomInset
  }

  /// The vertical space between the bottom of the card illustration
  /// and the top of the system CoreNFC sheet.
  internal static func visibleGapHeight(
    containerWidth: CGFloat,
    containerHeight: CGFloat,
    safeAreaBottomInset: CGFloat
  ) -> CGFloat {
    let card = cardHeight(containerWidth: containerWidth)
    let sheet = nfcSheetHeight(safeAreaBottomInset: safeAreaBottomInset)
    return max(minimumGapHeight, containerHeight - card - sheet)
  }
}
