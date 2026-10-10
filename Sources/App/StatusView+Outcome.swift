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
  }

#endif
