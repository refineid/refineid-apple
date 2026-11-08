// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI
  /// The signing configuration for ready documents.
  ///
  /// The format, PIN 2 entry and the optional stamp; its action is in
  /// the button bar.
  internal struct StatusSignatureSection: View {
    internal let signing: SignDocumentModel
    @Binding internal var format: SignatureFormat
    @Binding internal var pin2: String
    @Binding internal var accessNumber: String
    internal let asksLocalPin2: Bool
    /// Where the card operations go; nowhere while several cards wait
    /// for the holder's choice.
    internal let target: ReaderTarget
    internal let onSign: () -> Void
    @FocusState private var pinFocused: Bool

    /// Whether a card is there to type for.
    private var acceptsEntry: Bool {
      target != .unchosen
    }

    internal var body: some View {
      if signing.pending != nil {
        let pinTitle = CredentialLabels.name(for: .pin2)
        Section {
          SignatureFormatRow(documents: signing.queued, format: $format)
          if asksLocalPin2 {
            CredentialSecretField(
              name: pinTitle,
              text: $pin2,
              revealIdentifier: "signPin2Reveal"
            ) {
              SecureField(pinTitle, text: $pin2)
                .onChange(of: pin2) { _, typed in
                  pin2 = LimitedDigits.pin(typed)
                }
                .focused($pinFocused)
                .onSubmit { onSign() }
                .accessibilityIdentifier("signPin2")
            }
            .disabled(!acceptsEntry)
          }
          #if FEATURE_PDF_STAMP
            if format == .pades {
              StampRow(signing: signing, accessNumber: $accessNumber)
                .disabled(!acceptsEntry)
            }
          #endif
        }
        .onAppear { if asksLocalPin2, acceptsEntry { pinFocused = true } }
        .onChange(of: target) { used, _ in
          // What was typed or read belongs to the card used before.
          if case .slot = used, !signing.working {
            signing.cardRemoved()
            pin2 = ""
            accessNumber = ""
          }
          if asksLocalPin2, acceptsEntry { pinFocused = true }
        }
      }
    }
  }

#endif
