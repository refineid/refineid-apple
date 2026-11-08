// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import SwiftUI

  /// The status row while it speaks about document signing: the step
  /// with a progress indicator, or the outcome with its actions.
  ///
  /// A failure takes the default action for "OK", so Return reads it
  /// away before anything signs again, and every message is announced
  /// as it arrives.
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

      case .outcome(let notice, let signed):
        VStack(alignment: .leading) {
          if !signed.isEmpty {
            Label(StatusMessage.savedSentence(count: signed.count), systemImage: "checkmark.seal")
          }
          if let notice {
            CredentialOutcomeText(message: notice, tone: .notice)
          }
        }
      }
    }

    @ViewBuilder private var actions: some View {
      switch message {
      case .progress:
        EmptyView()

      case .failure:
        Button("OK") { acknowledge() }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("statusAcknowledge")

      case .outcome(_, let signed):
        if !signed.isEmpty {
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(signed)
          }
          .accessibilityIdentifier("statusShowInFinder")
        }
        Button("OK") { acknowledge() }
          .accessibilityIdentifier("statusAcknowledge")
      }
    }

    /// What VoiceOver announces when the row changes.
    private static func spoken(_ message: StatusMessage) -> String {
      switch message {
      case .progress(let text), .failure(let text):
        text

      case .outcome(let notice, let signed):
        ([signed.isEmpty ? nil : StatusMessage.savedSentence(count: signed.count), notice]
          .compactMap(\.self)).joined(separator: " ")
      }
    }
  }

#endif
