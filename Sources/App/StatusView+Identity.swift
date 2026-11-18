// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The status row of the ready window: where the app talks to the
  /// holder about signing, and otherwise whose identity is offered.
  extension StatusView {
    private static let identityBoxSpacing: CGFloat = 12
    private static let identityBoxPaddingHorizontal: CGFloat = 8
    private static let pinCodesBoxPaddingHorizontal: CGFloat = 12
    private static let boxCornerRadius: CGFloat = 6
    private static let boxBorderWidth: CGFloat = 1
    private static let boxBorderOpacity: Double = 0.2

    /// Which document controls the window shows now.
    internal var documentControls: StatusDocumentControls {
      StatusDocumentControls(
        availability: availability,
        queued: signingModel.queued,
        signing: signingModel.working,
        readingCard: signingModel.readingStamp,
        failureShown: signingModel.unacknowledgedFailure != nil,
        offersVerification: StatusDocumentControls.defaultOffersVerification
      )
    }

    /// Whose identity the card or phone offers, or what to attach.
    internal var identityRow: some View {
      #if REFINEID_REMOTE_CARD
        IdentityStateView(
          availability: availability,
          warnsUnavailableCard: activation.warnsUnavailableCard
        )
        .frame(minHeight: statusRowHeight)
        // The card stays the one chosen while it is being used.
        .disabled(signingModel.working || signingModel.readingStamp)
        .accessibilityIdentifier("loginIdentityStatus")
      #else
        HStack(spacing: Self.identityBoxSpacing) {
          IdentityStateView(
            availability: availability,
            warnsUnavailableCard: activation.warnsUnavailableCard
          )
          .accessibilityIdentifier("loginIdentityStatus")
          .padding(.horizontal, Self.identityBoxPaddingHorizontal)
          .frame(maxWidth: .infinity, minHeight: statusRowHeight, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: Self.boxCornerRadius))
          .overlay(
            RoundedRectangle(cornerRadius: Self.boxCornerRadius).stroke(
              Color.secondary.opacity(Self.boxBorderOpacity), lineWidth: Self.boxBorderWidth))

          PinCodesButton()
            .padding(.horizontal, Self.pinCodesBoxPaddingHorizontal)
            .frame(minHeight: statusRowHeight)
            .clipShape(RoundedRectangle(cornerRadius: Self.boxCornerRadius))
            .overlay(
              RoundedRectangle(cornerRadius: Self.boxCornerRadius).stroke(
                Color.secondary.opacity(Self.boxBorderOpacity), lineWidth: Self.boxBorderWidth))
        }
        // The card stays the one chosen while it is being used.
        .disabled(signingModel.working || signingModel.readingStamp)
      #endif
    }

    /// What signing has to say, or the identity row when it says
    /// nothing and the identity is shown.
    @ViewBuilder
    internal func statusRow(showsIdentity: Bool) -> some View {
      if let message = StatusMessage(signingModel) {
        StatusMessageRow(message: message) { signingModel.acknowledgeOutcome() }
          .frame(minHeight: statusRowHeight)
      } else if showsIdentity {
        identityRow
      }
    }
  }

#endif
