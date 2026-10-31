// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// What the window says when signing went wrong.
  ///
  /// A failure is an alert the holder dismisses, so it never outlives
  /// the attempt it describes. Success says nothing: the pile empties
  /// and the file is where it was asked for, and a readout naming one
  /// output cannot speak for a batch that wrote several.
  extension StatusView {
    @ViewBuilder internal var outcomeSection: some View {
      if let note = signingModel.notice {
        Section {
          CredentialOutcomeText(message: note, tone: .notice)
        }
      }
    }
  }

  extension View {
    /// Presents the signing failure as a window-modal alert until it is
    /// acknowledged.
    internal func acknowledgesFailure(of signing: SignDocumentModel) -> some View {
      let failure = signing.unacknowledgedFailure
      return alert(
        DocumentSigningMessage.title,
        isPresented: Binding(
          get: { signing.unacknowledgedFailure != nil },
          set: { presented in
            if !presented { signing.acknowledgeFailure() }
          }
        ),
        presenting: failure
      ) { _ in
        Button(String(localized: "OK")) {
          signing.acknowledgeFailure()
        }
      } message: { message in
        Text(verbatim: message)
      }
    }

    /// Asks what becomes of a finished signature whose save panel
    /// was cancelled.
    ///
    /// Going away without an answer counts as the default, which opens
    /// the panel again.
    internal func asksAboutUnsaved(for signing: SignDocumentModel) -> some View {
      let subject = signing.unsaved
      return alert(
        subject?.title ?? "",
        isPresented: Binding(
          get: { signing.unsaved != nil },
          set: { presented in
            // A button's own answer runs first; a dismissal without
            // one is answered on the next turn.
            if !presented {
              Task { @MainActor in signing.dismissUnsaved() }
            }
          }
        ),
        presenting: subject
      ) { subject in
        Button(subject.forgetTitle, role: .destructive) {
          signing.answerUnsaved(forget: true)
        }
        Button(subject.saveTitle) {
          signing.answerUnsaved(forget: false)
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }

#endif
