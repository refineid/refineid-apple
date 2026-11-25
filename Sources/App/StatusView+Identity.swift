// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import RappRequester
  import SwiftUI

  /// The status row of the ready window: where the app talks to the
  /// holder about signing, and otherwise whose identity is offered.
  extension StatusView {
    private static let identityBoxPaddingHorizontal: CGFloat = 10
    private static let pinCodesBoxPaddingHorizontal: CGFloat = 12
    private static let identityToKeySpacing: CGFloat = 4
    private static let boxCornerRadius: CGFloat = 10
    private static let boxBorderWidth: CGFloat = 1

    /// Whether the card in this Mac's reader still requires changing its
    /// initial PIN 2 before document signing is possible (EstEID 2025).
    internal var signingBlockedByInitialPin2: Bool {
      !DocumentSigner.usesRappSigning
        && availability == .ready
        && retryHealth.pin2RequiresChangeBeforeSigning
    }

    /// Ready when a document is waiting and PIN 2 has been entered for
    /// it: PIN 2 is asked for every signature or batch and kept no longer
    /// (RAPP v26.11.8 §11 item 2).
    internal var canSign: Bool {
      availability == .ready
        && !signingBlockedByInitialPin2
        && !selection.awaitsChoice
        && signingModel.pending != nil
        && !signingModel.working
        // Not while the card is being read for the stamp: it is one
        // card, and asking it to sign mid-read is asking it to be in
        // two places.
        && !signingModel.readingStamp
    }

    /// Which document controls the window shows now.
    internal var documentControls: StatusDocumentControls {
      StatusDocumentControls(
        availability: availability,
        queued: signingModel.queued,
        signing: signingModel.working,
        readingCard: signingModel.readingStamp,
        failureShown: signingModel.unacknowledgedFailure != nil,
        offersVerification: StatusDocumentControls.defaultOffersVerification,
        signingAvailable: !signingBlockedByInitialPin2
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
        HStack(spacing: Self.identityToKeySpacing) {
          identityBox(for: availability)

          PinCodesButton()
            .padding(.horizontal, Self.pinCodesBoxPaddingHorizontal)
            .frame(minHeight: statusRowHeight)
            .clipShape(RoundedRectangle(cornerRadius: Self.boxCornerRadius))
            .overlay(
              RoundedRectangle(cornerRadius: Self.boxCornerRadius).strokeBorder(
                Color.secondary, lineWidth: Self.boxBorderWidth))
        }
        // The card stays the one chosen while it is being used.
        .disabled(signingModel.working || signingModel.readingStamp)
      #endif
    }

    internal func identityBox(for state: IdentityAvailability) -> some View {
      statusBox {
        IdentityStateView(
          availability: state, warnsUnavailableCard: activation.warnsUnavailableCard
        )
        .accessibilityIdentifier("loginIdentityStatus")
      }
    }

    private func statusBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
      content()
        .padding(.horizontal, Self.identityBoxPaddingHorizontal)
        .frame(maxWidth: .infinity, minHeight: statusRowHeight, alignment: .leading)
        .overlay {
          RoundedRectangle(cornerRadius: Self.boxCornerRadius)
            .strokeBorder(.secondary, lineWidth: Self.boxBorderWidth)
            .allowsHitTesting(false)
        }
    }

    /// What signing has to say, or the identity row when it says
    /// nothing and the identity is shown.
    @ViewBuilder
    internal func statusRow(showsIdentity: Bool) -> some View {
      if let message = StatusMessage(signingModel) {
        statusBox {
          StatusMessageRow(
            message: message, requiresAcknowledgement: signingModel.acknowledgement != nil
          ) { signingModel.acknowledgeOutcome() }
        }
      } else if showsIdentity {
        identityRow
      }
    }
  }

#endif
