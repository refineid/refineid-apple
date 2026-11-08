// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The Verify button, below everything else in the window, and the
  /// sheet it opens.
  internal struct StatusVerifySection: View {
    internal let signing: SignDocumentModel

    /// Whether the button can run.
    internal let enabled: Bool

    /// The verification the button opened, shown in a sheet.
    @State private var verification: QueuedDocumentVerification?

    internal var body: some View {
      Section {
        HStack {
          Spacer()
          Button("Verify…") { verifyQueued() }
            .disabled(!enabled)
            .accessibilityIdentifier("verifyQueuedDocuments")
        }
      }
      .presentsVerification($verification)
    }

    /// Verifies every waiting document, leaving the pile to be signed.
    private func verifyQueued() {
      guard enabled else { return }
      verification = QueuedDocumentVerification(documents: signing.queued, dependencies: .live)
    }
  }

#endif
