// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Guidance showing the card specimen with CAN and QR code highlighted.
  internal struct CardAccessNumberGuidanceView: View {
    internal let containerWidth: CGFloat

    private var cardHeight: CGFloat {
      CardAccessNumberGuidanceLayout.cardHeight(containerWidth: containerWidth)
    }

    private var highlightRect: CGRect {
      CardAccessNumberGuidanceLayout.highlightRect(
        in: CGSize(width: containerWidth, height: cardHeight)
      )
    }

    internal var body: some View {
      VStack(spacing: CardAccessNumberGuidanceLayout.contentSpacing) {
        Text(
          String(
            localized:
              "The card access number (CAN) is also in the QR code, which you can read with the camera."
          )
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(CardAccessNumberGuidanceLayout.minimumTextScale)

        cardIllustration
      }
    }

    private var cardIllustration: some View {
      Image(.identityCardInstruction)
        .resizable()
        .scaledToFit()
        .frame(width: containerWidth, height: cardHeight)
        .overlay {
          highlightBox
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: CardAccessNumberGuidanceLayout.cardCornerRadius,
            style: .continuous
          )
        )
        .accessibilityHidden(true)
    }

    private var highlightBox: some View {
      RoundedRectangle(
        cornerRadius: CardAccessNumberGuidanceLayout.highlightCornerRadius,
        style: .continuous
      )
      .stroke(Color.green, lineWidth: CardAccessNumberGuidanceLayout.highlightLineWidth)
      .frame(width: highlightRect.width, height: highlightRect.height)
      .position(x: highlightRect.midX, y: highlightRect.midY)
    }
  }

#endif
