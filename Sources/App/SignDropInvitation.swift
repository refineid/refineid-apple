// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The empty drop area: an invitation to drop documents, and the
  /// chooser for whoever prefers a panel.
  internal struct SignDropInvitation: View {
    private static let spacing: CGFloat = 6

    /// Whether a drag is over the area, which tints the invitation.
    internal let targeted: Bool

    /// Whether a card or phone can sign, so the invitation names
    /// signing too.
    internal let offersSigning: Bool

    /// Opens the chooser.
    internal let choose: () -> Void

    /// What the area invites the holder to do.
    private var invitation: Text {
      if offersSigning {
        Text("Drop documents here to sign or verify them.")
      } else {
        Text("Drop documents here to verify them.")
      }
    }

    internal var body: some View {
      VStack(spacing: Self.spacing) {
        Image(systemName: "doc.badge.plus")
          .font(.title)
          .foregroundStyle(
            targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
          )
          .accessibilityHidden(true)
        invitation
          .foregroundStyle(.secondary)
        Button("Choose…", action: choose)
          .buttonStyle(.link)
          .accessibilityIdentifier("signChooseDocument")
      }
    }
  }

#endif
