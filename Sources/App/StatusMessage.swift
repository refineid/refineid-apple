// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// What the window's status row says about document signing, in
  /// place of the holder's name, until it is acknowledged or the pile
  /// changes.
  ///
  /// A signature in flight says its step; a finished one what became of
  /// it. Nothing to say leaves the row to the identity.
  internal enum StatusMessage: Equatable {
    /// Why signing failed, in plain words, until acknowledged.
    case failure(String)

    /// A fact the holder must see beside the signed output.
    case notice(String)

    /// The step a signature or a card read is on.
    case progress(String)

    /// The signed file was written here.
    case signed(URL)

    /// What the row says for `signing`, nil when it says nothing.
    @MainActor
    internal init?(_ signing: SignDocumentModel) {
      if let note = StatusView.progressNote(signing) {
        self = .progress(note)
      } else if let failure = signing.unacknowledgedFailure {
        self = .failure(failure)
      } else if let notice = signing.notice {
        self = .notice(notice)
      } else if let signed = signing.signed {
        self = .signed(signed)
      } else {
        return nil
      }
    }
  }

#endif
