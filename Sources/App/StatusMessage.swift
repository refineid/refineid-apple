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
    /// Why signing failed, in plain words, until acknowledged. It comes
    /// first, before the step it interrupted.
    case failure(String)

    /// What the last action left: a notice the holder must see, the
    /// files it wrote, or both, shown together.
    case outcome(notice: String?, signed: [URL])

    /// The step a signature or a card read is on.
    case progress(String)

    /// What the row says for `signing`, nil when it says nothing.
    @MainActor
    internal init?(_ signing: SignDocumentModel) {
      if let failure = signing.unacknowledgedFailure {
        self = .failure(failure)
      } else if let note = StatusView.progressNote(signing) {
        self = .progress(note)
      } else if signing.notice != nil || !signing.signedFiles.isEmpty {
        self = .outcome(notice: signing.notice, signed: signing.signedFiles)
      } else {
        return nil
      }
    }

    /// The sentence for `count` signed and saved files.
    internal static func savedSentence(count: Int) -> String {
      count == 1
        ? String(localized: "Signed and saved.")
        : String(localized: "Signed and saved \(count) documents.")
    }
  }

#endif
