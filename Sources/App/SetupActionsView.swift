// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// The three actions a fresh install offers, before any card is set up.
  ///
  /// Each button names its whole job in short: verifying a document
  /// needs no card, while signing one and logging in both read the card
  /// over NFC. Once an identity exists the regular sections take over
  /// and this is gone.
  ///
  /// A plain stack, never form rows: several links in one list row
  /// share the row's tap target and misroute taps, and the row draws
  /// disclosure chevrons the buttons do not want.
  internal struct SetupActionsView: View {
    private enum Layout {
      static let stackSpacing: CGFloat = 12
    }

    internal var body: some View {
      VStack(spacing: Layout.stackSpacing) {
        verifyButton
        signButton
        authenticateButton
      }
    }

    private var verifyButton: some View {
      NavigationLink(value: CardCredentialsView.Route.verifyDocuments) {
        SetupActionLabel(
          title: String(localized: "Verify document"),
          systemImage: CardCredentialsView.verificationSymbolName
        )
      }
      .accessibilityIdentifier("verifyDocuments")
    }

    private var signButton: some View {
      NavigationLink(value: CardCredentialsView.Route.signDocuments) {
        SetupActionLabel(
          title: String(localized: "Sign document"),
          systemImage: "signature"
        )
      }
      .accessibilityIdentifier("signDocuments")
    }

    private var authenticateButton: some View {
      NavigationLink(value: CardCredentialsView.Route.authenticate) {
        SetupActionLabel(
          title: String(localized: "Login website"),
          systemImage: "person.badge.key.fill"
        )
      }
      .accessibilityIdentifier("setupAuthenticate")
    }
  }
#endif
