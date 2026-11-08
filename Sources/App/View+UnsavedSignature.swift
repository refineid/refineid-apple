// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The alert for a finished signature whose save panel was
  /// cancelled. Progress and outcomes speak in the status row
  /// (`StatusMessage`).
  extension View {
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
