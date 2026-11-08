// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The status row of the ready window: where the app talks to the
  /// holder about signing, and otherwise whose identity is offered.
  extension StatusView {
    /// Which document controls the window shows now.
    internal var documentControls: StatusDocumentControls {
      StatusDocumentControls(
        availability: availability, queued: signingModel.queued, signing: signingModel.working)
    }

    /// Whose identity the card or phone offers, or what to attach.
    internal var identityRow: some View {
      IdentityStateView(
        availability: availability,
        warnsUnavailableCard: activation.warnsUnavailableCard
      )
      // The card stays the one chosen while it is being used.
      .disabled(signingModel.working || signingModel.readingStamp)
      .accessibilityIdentifier("loginIdentityStatus")
    }

    /// What signing has to say, or the identity row when it says
    /// nothing and the identity is shown.
    @ViewBuilder
    internal func statusRow(showsIdentity: Bool) -> some View {
      if let message = StatusMessage(signingModel) {
        StatusMessageRow(message: message) { signingModel.acknowledgeOutcome() }
      } else if showsIdentity {
        identityRow
      }
    }
  }

#endif
