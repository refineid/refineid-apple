// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The window's one button bar, centred below every panel: "Verify…"
  /// when verification is compiled in, and the default "Sign…" while a
  /// card or phone can sign.
  internal struct StatusActionBar: View {
    internal let signing: SignDocumentModel
    internal let controls: StatusDocumentControls
    internal let canSign: Bool
    internal let onSign: () -> Void

    #if FEATURE_DOCUMENT_VERIFICATION
      /// The verification "Verify…" opened, shown in a sheet.
      @State private var verification: QueuedDocumentVerification?
    #endif

    internal var body: some View {
      #if FEATURE_DOCUMENT_VERIFICATION
        actionRow.presentsVerification($verification)
      #else
        actionRow
      #endif
    }

    private var actionRow: some View {
      HStack {
        ForEach(controls.actions, id: \.self) { action in
          switch action {
          case .verify:
            #if FEATURE_DOCUMENT_VERIFICATION
              Button("Verify…") { verifyQueued() }
                .disabled(!controls.verifyEnabled)
                .accessibilityIdentifier("verifyQueuedDocuments")
            #else
              EmptyView()
            #endif

          case .sign:
            Button("Sign…") { onSign() }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(controls.awaitsAcknowledgement ? nil : .defaultAction)
              .disabled(!controls.allowsSigning(cardReady: canSign))
              .accessibilityIdentifier("signDocument")
          }
        }
      }
      .frame(maxWidth: .infinity)
    }

    #if FEATURE_DOCUMENT_VERIFICATION
      /// Verifies every waiting document, leaving the pile to be signed.
      private func verifyQueued() {
        guard controls.verifyEnabled else { return }
        verification = QueuedDocumentVerification(documents: signing.queued, dependencies: .live)
      }
    #endif
  }

#endif
