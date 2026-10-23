// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import OSLog

  extension SignDocumentModel {
    #if DEBUG
      private static let logger = Logger(
        subsystem: "fi.refineid.ReFineID", category: "sign-document-model"
      )
    #endif

    /// Reports a failure raised before the card was reached.
    internal func report(_ message: String) {
      fail(message: message)
    }

    /// Publishes a signing failure only while its card is still present.
    internal func report(_ error: Error, from appearance: Int) {
      #if DEBUG
        Self.logger.error(
          "[SignDocumentModel] signing failed: \(String(describing: error), privacy: .public)"
        )
      #endif
      guard appearance == cardAppearance else { return }
      fail(message: DocumentSigningMessage.message(for: error))
    }
  }

#endif
