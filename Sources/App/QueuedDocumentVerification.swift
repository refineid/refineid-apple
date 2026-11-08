// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// The verification of every document waiting in the Mac window, one
  /// `VerifyDocumentModel` per document, started together.
  ///
  /// It reads the documents and leaves the pile as it is, so a document
  /// verified here can be signed next without being dropped again.
  @MainActor
  internal final class QueuedDocumentVerification {
    /// One document and its verification.
    internal struct Item {
      /// Its place in the pile.
      internal let index: Int
      internal let document: URL
      internal let model: VerifyDocumentModel
    }

    internal let items: [Item]

    /// Starts verifying each of `documents` under `dependencies`.
    internal init(
      documents: [URL],
      dependencies: VerifyDocumentModel.Dependencies
    ) {
      items = documents.enumerated().map { index, document in
        Item(
          index: index, document: document, model: VerifyDocumentModel(dependencies: dependencies))
      }
      for item in items {
        item.model.verify(url: item.document)
      }
    }

    /// Whether the Verify button can run: a document is waiting and no
    /// signature is in flight.
    internal static func isAvailable(queued: [URL], signing working: Bool) -> Bool {
      !queued.isEmpty && !working
    }

    /// Stops every verification still running.
    internal func cancel() {
      for item in items {
        item.model.reset()
      }
    }
  }

#endif
