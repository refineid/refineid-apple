// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if !FEATURE_CARD_ACTIVATION

  import SwiftUI

  /// What an unactivated card is told in a build that does not activate.
  ///
  /// The setup flow still routes an unactivated card to the activation
  /// destination, because the card's state is the card's state; what the
  /// gate changes is the answer waiting there. A dead end would describe
  /// the app as broken rather than the version as limited, so the section
  /// names what the card needs and says plainly that this version does
  /// not provide it (Documentation/decisions.md, 2026-08-21).
  internal struct CardActivationUnavailableSection: View {
    internal var body: some View {
      Section {
        Text("This identity card has not been activated yet.")
        Text("Activating a card is not part of this version of RefineID.")
          .foregroundStyle(.secondary)
        Text("Activate the card first, then return here to take it into use.")
          .foregroundStyle(.secondary)
      } header: {
        Text("Identity card activation")
      }
    }
  }

#endif
