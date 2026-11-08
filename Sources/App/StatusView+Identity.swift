// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The identity row of the ready window.
  extension StatusView {
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
  }

#endif
