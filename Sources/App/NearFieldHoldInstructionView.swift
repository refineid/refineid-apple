// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// What the holder sees behind the system NFC sheet during a hold.
  ///
  /// The system NFC sheet covers the lower portion of the screen, while
  /// the card illustration fills the top edge to edge. The instruction
  /// sentence is centered in the visible gap between the card illustration
  /// and the top of the system sheet. Shown for every hold, whatever
  /// operation started it.
  internal struct NearFieldHoldInstructionView: View {
    internal var body: some View {
      GeometryReader { geometry in
        let cardHeight = NearFieldHoldLayout.cardHeight(containerWidth: geometry.size.width)

        VStack(spacing: 0) {
          Image(.identityCardInstruction)
            .resizable()
            .scaledToFit()
            .frame(width: geometry.size.width, height: cardHeight, alignment: .top)
            .accessibilityHidden(true)

          Spacer(minLength: NearFieldHoldLayout.spacerMinLength)

          Text(
            String(
              localized:
                "Read the identity card by holding it against the back of the phone where the picture shows."
            )
          )
          .font(.body)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(NearFieldHoldLayout.minimumTextScale)
          .padding(.horizontal, NearFieldHoldLayout.textHorizontalPadding)

          Spacer(minLength: NearFieldHoldLayout.spacerMinLength)

          Color.clear
            .frame(height: NearFieldHoldLayout.nfcSheetBaseHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .ignoresSafeArea(edges: .top)
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
  }
#endif
