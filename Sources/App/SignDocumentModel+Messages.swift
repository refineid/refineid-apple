// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import OSLog

  extension SignDocumentModel {
    /// A signed portrait QR could not be turned into a printable mark.
    internal enum StampPreparationFailure: Error {
      case rendering
    }

    #if DEBUG
      private static let logger = Logger(
        subsystem: "fi.refineid.ReFineID", category: "sign-document-model"
      )
    #endif

    /// One localized failure vocabulary, shared with iOS.
    internal static func message(for error: Error) -> String {
      if error is StampPreparationFailure {
        return String(
          localized: "error.stampRendering",
          defaultValue:
            "The signed portrait QR could not be rendered. Nothing was written.",
          table: "DocumentSigning")
      }
      return DocumentSigningMessage.message(for: error)
    }

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
      fail(message: Self.message(for: error))
    }
  }

#endif
