// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The empty drop area: an invitation to drop documents, and the
  /// chooser for whoever prefers a panel.
  internal struct SignDropInvitation: View {
    private static let spacing: CGFloat = 6

    /// Whether a drag is over the area, which tints the invitation.
    internal let targeted: Bool

    /// Opens the chooser.
    internal let choose: () -> Void

    internal var body: some View {
      VStack(spacing: Self.spacing) {
        Image(systemName: "doc.badge.plus")
          .font(.title)
          .foregroundStyle(
            targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
          )
          .accessibilityHidden(true)
        Text("Drop documents here to sign them.")
          .foregroundStyle(.secondary)
        Button("Choose…", action: choose)
          .buttonStyle(.link)
          .accessibilityIdentifier("signChooseDocument")
      }
    }
  }

#endif
