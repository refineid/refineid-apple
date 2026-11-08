// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The window's one button bar, centred below every panel: "Verify…"
  /// and, while a card or phone can sign, the default "Sign…".
  internal struct StatusActionBar: View {
    internal let signing: SignDocumentModel
    internal let controls: StatusDocumentControls
    internal let canSign: Bool
    internal let onSign: () -> Void

    /// The verification "Verify…" opened, shown in a sheet.
    @State private var verification: QueuedDocumentVerification?

    internal var body: some View {
      HStack {
        ForEach(controls.actions, id: \.self) { action in
          switch action {
          case .verify:
            Button("Verify…") { verifyQueued() }
              .disabled(!controls.verifyEnabled)
              .accessibilityIdentifier("verifyQueuedDocuments")

          case .sign:
            Button("Sign…") { onSign() }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(!canSign)
              .accessibilityIdentifier("signDocument")
          }
        }
      }
      .frame(maxWidth: .infinity)
      .presentsVerification($verification)
    }

    /// Verifies every waiting document, leaving the pile to be signed.
    private func verifyQueued() {
      guard controls.verifyEnabled else { return }
      verification = QueuedDocumentVerification(documents: signing.queued, dependencies: .live)
    }
  }

#endif
