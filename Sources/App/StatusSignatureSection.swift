// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI
  /// PIN 2 entry, optional stamp, and Sign button for ready documents.
  internal struct StatusSignatureSection: View {
    internal let signing: SignDocumentModel
    @Binding internal var format: SignatureFormat
    @Binding internal var pin2: String
    @Binding internal var accessNumber: String
    internal let asksLocalPin2: Bool
    internal let canSign: Bool
    internal let onSign: () -> Void
    @FocusState private var pinFocused: Bool

    internal var body: some View {
      if signing.pending != nil {
        let pinTitle = String(localized: "PIN 2")
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
          }
          #if FEATURE_PDF_STAMP
            if format == .pades {
              StampRow(signing: signing, accessNumber: $accessNumber)
            }
          #endif
          #if DEBUG
            if DebugRevokedDocumentSigning.isEnabled() {
              Text(DebugRevokedDocumentSigning.armedWarning)
                .foregroundStyle(.orange)
            }
          #endif
          actionRow
        }
        .onAppear { if asksLocalPin2 { pinFocused = true } }
      }
    }

    @ViewBuilder private var actionRow: some View {
      HStack {
        if let note = StatusView.progressNote(signing) {
          ProgressView().controlSize(.small)
          Text(note)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Sign…") { onSign() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!canSign)
          .accessibilityIdentifier("signDocument")
      }
      .announcesOutcome(StatusView.progressNote(signing))
    }
  }

#endif
