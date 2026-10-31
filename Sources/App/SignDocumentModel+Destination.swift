// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  extension SignDocumentModel {
    /// Asks where a finished signature goes, proposing the name last
    /// typed when there is one.
    internal typealias DestinationChoice =
      @MainActor (SignedDocument, _ typedName: String?) async -> PlaceAnswer

    /// Asks for the folder a pile of finished signatures goes to.
    internal typealias FolderChoice = @MainActor () async -> URL?

    /// What a save panel answered.
    internal struct PlaceAnswer: Sendable {
      /// The chosen file, or nil when the panel was cancelled.
      internal let destination: URL?

      /// The name in the panel's field when it closed.
      internal let typedName: String?
    }

    /// The signed file's place beside the original.
    ///
    /// Stamped with the best signature time, colons replaced so the
    /// name is safe everywhere. The extension follows the format: the
    /// original's for a PAdES PDF, `.asice` for a container.
    nonisolated internal static func destination(
      for source: URL,
      at instant: Date,
      format: SignatureFormat
    ) -> URL {
      let name = source.deletingPathExtension().lastPathComponent
      return source.deletingLastPathComponent()
        .appendingPathComponent(name + SignedDocumentName.suffix(at: instant))
        .appendingPathExtension(format.outputPathExtension(for: source))
    }

    /// The name a signed document is offered under: the original's,
    /// with its best signature time.
    nonisolated internal static func suggestedName(
      for source: URL,
      format: SignatureFormat,
      at instant: Date
    ) -> String {
      Self.destination(for: source, at: instant, format: format)
        .lastPathComponent
    }

    /// The name the holder wrote for a container, stamped with the
    /// best signature time - unless they kept the proposed suffix,
    /// which already carries it.
    ///
    /// A name that comes back with the suffix is kept as it is; one
    /// where typing replaced it gets the same instant appended, so a
    /// second signature never overwrites the first.
    nonisolated internal static func stampedContainer(
      from chosen: URL,
      at instant: Date
    ) -> URL {
      let stem = chosen.deletingPathExtension().lastPathComponent
      guard !stem.hasSuffix(SignedDocumentName.suffix(at: instant)) else {
        return chosen.pathExtension.isEmpty
          ? chosen.appendingPathExtension("asice")
          : chosen
      }
      return Self.destination(for: chosen, at: instant, format: .asice)
    }
  }

#endif
