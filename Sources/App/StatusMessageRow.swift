// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import SwiftUI

  /// The status row while it speaks about document signing: the step
  /// with a progress indicator, or the outcome with its actions.
  internal struct StatusMessageRow: View {
    internal let message: StatusMessage

    /// Acknowledges the outcome, which returns the row to the identity.
    internal let acknowledge: () -> Void

    internal var body: some View {
      HStack {
        content
        Spacer()
        actions
      }
      .accessibilityIdentifier("statusMessage")
      .announcesOutcome(Self.spoken(message))
    }

    @ViewBuilder private var content: some View {
      switch message {
      case .progress(let note):
        ProgressView().controlSize(.small)
        Text(verbatim: note)

      case .failure(let failure):
        CredentialOutcomeText(message: failure, tone: .failure)

      case .notice(let notice):
        CredentialOutcomeText(message: notice, tone: .notice)

      case .signed:
        Label("Signed and saved.", systemImage: "checkmark.seal")
      }
    }

    @ViewBuilder private var actions: some View {
      switch message {
      case .progress:
        EmptyView()

      case .signed(let file):
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        .accessibilityIdentifier("statusShowInFinder")
        acknowledgeButton

      case .failure, .notice:
        acknowledgeButton
      }
    }

    private var acknowledgeButton: some View {
      Button("OK") { acknowledge() }
        .accessibilityIdentifier("statusAcknowledge")
    }

    /// What VoiceOver announces when the row changes.
    private static func spoken(_ message: StatusMessage) -> String? {
      switch message {
      case .progress(let text), .failure(let text), .notice(let text):
        text

      case .signed:
        String(localized: "Signed and saved.")
      }
    }
  }

#endif
