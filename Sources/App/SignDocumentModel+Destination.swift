// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  extension SignDocumentModel {
    /// The signed file's place beside the original.
    ///
    /// Stamped with the UTC instant, colons replaced so the name is
    /// safe everywhere. The extension follows the format: the
    /// original's for a PAdES PDF, `.asice` for a container.
    nonisolated internal static func destination(
      for source: URL,
      at instant: Date,
      format: SignatureFormat
    ) -> URL {
      let name = source.deletingPathExtension().lastPathComponent
      return source.deletingLastPathComponent()
        .appendingPathComponent(name + Self.signedNameSuffix(at: instant))
        .appendingPathExtension(format.outputPathExtension(for: source))
    }

    /// The suffix every signed output's name carries: the word for
    /// signing in the app's language, then the UTC instant.
    ///
    /// The instant itself stays in the engineering form in every
    /// language - a name a Finnish holder mails abroad still sorts
    /// and reads the same - and only the word is translated.
    nonisolated internal static func signedNameSuffix(at instant: Date) -> String {
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime]
      let instantText = formatter.string(from: instant)
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "+00-00", with: "Z")
      let word = String(
        localized: "output.signed",
        defaultValue: "signed",
        table: "DocumentSigning")
      return " - \(word) \(instantText)"
    }

    /// The name a signed document should be offered under: the
    /// original's, with the instant it was signed.
    nonisolated internal static func suggestedName(
      for source: URL,
      format: SignatureFormat
    ) -> String {
      Self.destination(for: source, at: Date(), format: format)
        .lastPathComponent
    }

    /// The name the holder wrote for a container, stamped with the
    /// signing instant - unless they kept the proposed one, which
    /// already carries it.
    ///
    /// No document in a set is the set, so no document's name is
    /// suggested: the panel proposes the suffix alone and the holder
    /// writes the beginning. When the suffix comes back it is kept as
    /// it is; when typing replaced it, the same instant is appended
    /// again, so the stamp survives without having to be defended and
    /// a second signature can never overwrite the first.
    nonisolated internal static func stampedContainer(
      from chosen: URL,
      at instant: Date
    ) -> URL {
      let stem = chosen.deletingPathExtension().lastPathComponent
      guard !stem.hasSuffix(Self.signedNameSuffix(at: instant)) else {
        return chosen.pathExtension.isEmpty
          ? chosen.appendingPathExtension("asice")
          : chosen
      }
      return Self.destination(for: chosen, at: instant, format: .asice)
    }
  }

#endif
