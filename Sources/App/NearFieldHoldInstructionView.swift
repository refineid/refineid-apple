// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// What the holder sees behind the system NFC sheet during a hold.
  ///
  /// The sheet itself takes no views and covers everything below the
  /// card, so the instruction lives here: the card fills the top edge
  /// to edge, with the sentence overlaid on its lower area where the
  /// sheet cannot cover it. Shown for every hold, whatever operation
  /// started it.
  internal struct NearFieldHoldInstructionView: View {
    private enum Layout {
      static let captionCornerRadius: CGFloat = 12
      static let captionHorizontalPadding: CGFloat = 16
      static let captionScrimOpacity = 0.55
      static let captionBottomPadding: CGFloat = 12
      static let textHorizontalPadding: CGFloat = 16
      static let textVerticalPadding: CGFloat = 10
    }

    internal var body: some View {
      VStack(spacing: 0) {
        ZStack(alignment: .bottom) {
          Image(.identityCardInstruction)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
            .ignoresSafeArea(edges: .top)
            .frame(maxWidth: .infinity, alignment: .top)
          Text(
            String(
              localized:
                "Read the identity card by holding it against the back of the phone where the picture shows."
            )
          )
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Layout.textHorizontalPadding)
          .padding(.vertical, Layout.textVerticalPadding)
          .background(
            Color.black.opacity(Layout.captionScrimOpacity),
            in: RoundedRectangle(cornerRadius: Layout.captionCornerRadius)
          )
          .padding(.horizontal, Layout.captionHorizontalPadding)
          .padding(.bottom, Layout.captionBottomPadding)
        }
        Spacer(minLength: 0)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
  }
#endif
