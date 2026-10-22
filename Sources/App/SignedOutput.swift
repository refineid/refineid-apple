// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import Foundation

  /// Where signed documents are written.
  ///
  /// Asked for before the card is touched. The sandbox hands this app
  /// the documents that were dropped and not the folder around them,
  /// so writing beside them has to be granted, and a panel answered
  /// after signing could be cancelled with signatures already spent.
  @MainActor
  internal enum SignedOutput {
    /// Asks for the file one signature is written to.
    ///
    /// A container covering a set is proposed the signing instant and
    /// no name in front of it, because no one document in a set is
    /// the set: naming it after whichever was chosen first would be a
    /// guess wearing the look of a fact. The suffix is shown rather
    /// than silently appended, so the name on disk is the name in the
    /// field. One document is offered its own name, which is not a
    /// guess.
    internal static func chooseFile(
      for documents: [URL],
      format: SignatureFormat
    ) -> URL? {
      guard let first = documents.first else { return nil }
      #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let destIndex = args.firstIndex(of: "--unattended-sign-destination"),
          destIndex + 1 < args.count
        {
          let raw = args[destIndex + 1]
          let expanded = raw.hasPrefix("~/") ? NSHomeDirectory() + raw.dropFirst() : raw
          return URL(fileURLWithPath: expanded)
        }
      #endif
      let together = documents.count > 1
      // Captured before the panel, so the instant shown in the field
      // is the instant stamped on whatever comes back.
      let instant = Date()
      let panel = NSSavePanel()
      panel.allowedContentTypes = format.allowedContentTypes
      let defaultStem = String(
        localized: "output.multiple",
        defaultValue: "portfolio",
        table: "DocumentSigning"
      )
      panel.nameFieldStringValue =
        together
        ? SignedDocumentName.suggested(
          sourceNames: documents.map(\.lastPathComponent),
          format: format,
          at: instant
        )
        : SignDocumentModel.suggestedName(for: first, format: format)
      panel.directoryURL = first.deletingLastPathComponent()
      panel.message =
        together
        ? String(localized: "Where to keep the signed ASiC-E file.")
        : String(localized: "Where to keep the signed document.")
      panel.prompt = String(localized: "Sign")
      if together {
        // The default portfolio name (e.g. "salkku") is initially selected
        // so typing immediately replaces it while preserving the signing
        // instant suffix.
        DispatchQueue.main.async {
          (panel.firstResponder as? NSTextView)?
            .setSelectedRange(NSRange(location: 0, length: defaultStem.utf16.count))
        }
      }
      guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
      return together ? SignDocumentModel.stampedContainer(from: chosen, at: instant) : chosen
    }

    /// Asks for the folder a batch is written to, starting beside the
    /// first document.
    internal static func chooseFolder(startingAt origin: URL?) -> URL? {
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      panel.directoryURL = origin
      panel.message = String(localized: "Where to keep the signed documents.")
      panel.prompt = String(localized: "Sign")
      guard panel.runModal() == .OK else { return nil }
      return panel.url
    }
  }

#endif
