// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import Foundation

  /// Where signed documents are written.
  ///
  /// Asked once the signature is finished in memory, so the name in
  /// the field carries its best signature time. The sandbox hands this
  /// app the documents that were dropped and not the folder around
  /// them, so writing beside them is granted through the panel. Each
  /// panel is a sheet on the status window.
  @MainActor
  internal enum SignedOutput {
    /// Asks for the file one signature is written to.
    ///
    /// A container covering a set is proposed the default stem and the
    /// suffix, with the stem selected so typing replaces it. One
    /// document is offered its own name. A name the holder typed in an
    /// earlier panel for the same signature is proposed instead. The
    /// suffix is shown rather than silently appended, so the name on
    /// disk is the name in the field.
    internal static func chooseFile(
      for documents: [URL],
      format: SignatureFormat,
      signed: SignedDocument,
      typedName: String?
    ) async -> SignDocumentModel.PlaceAnswer {
      guard let first = documents.first else {
        return SignDocumentModel.PlaceAnswer(destination: nil, typedName: typedName)
      }
      #if DEBUG
        if let unattended = Self.unattendedDestination() {
          return SignDocumentModel.PlaceAnswer(destination: unattended, typedName: nil)
        }
      #endif
      let together = documents.count > 1
      let instant = signed.bestSignatureTime
      let panel = NSSavePanel()
      panel.allowedContentTypes = format.allowedContentTypes
      let defaultStem = String(
        localized: "output.multiple",
        defaultValue: "portfolio",
        table: "DocumentSigning"
      )
      let proposed =
        together
        ? SignedDocumentName.suggested(
          sourceNames: documents.map(\.lastPathComponent),
          format: format,
          at: instant
        )
        : SignDocumentModel.suggestedName(for: first, format: format, at: instant)
      panel.nameFieldStringValue = typedName ?? proposed
      panel.directoryURL = first.deletingLastPathComponent()
      panel.message =
        together
        ? String(localized: "Where to keep the signed ASiC-E file.")
        : String(localized: "Where to keep the signed document.")
      panel.prompt = String(localized: "Save")
      let response = await Self.run(panel) {
        // The panel selects the whole name before its extension; a
        // proposed container name selects the default stem alone, so
        // typing replaces it and keeps the suffix.
        guard together, typedName == nil else { return }
        (panel.firstResponder as? NSTextView)?
          .setSelectedRange(NSRange(location: 0, length: defaultStem.utf16.count))
      }
      let typed = panel.nameFieldStringValue
      guard response == .OK, let chosen = panel.url else {
        return SignDocumentModel.PlaceAnswer(destination: nil, typedName: typed)
      }
      return SignDocumentModel.PlaceAnswer(
        destination: together
          ? SignDocumentModel.stampedContainer(from: chosen, at: instant) : chosen,
        typedName: typed
      )
    }

    /// Asks for the folder a batch is written to, starting beside the
    /// first document.
    internal static func chooseFolder(startingAt origin: URL?) async -> URL? {
      #if DEBUG
        if let unattended = Self.unattendedDestination() {
          return unattended
        }
      #endif
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      panel.directoryURL = origin
      panel.message = String(localized: "Where to keep the signed documents.")
      panel.prompt = String(localized: "Save")
      guard await Self.run(panel, presented: nil) == .OK else { return nil }
      return panel.url
    }

    /// Runs `panel` as a sheet on the status window, or as its own
    /// window when there is none, calling `presented` once it shows.
    private static func run(
      _ panel: NSSavePanel,
      presented: (@MainActor () -> Void)?
    ) async -> NSApplication.ModalResponse {
      let window = NSApp.windows.first { window in
        window.identifier?.rawValue == RefineIDApp.statusWindowID && window.isVisible
      }
      return await withCheckedContinuation { continuation in
        if let window {
          panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        } else {
          panel.begin { continuation.resume(returning: $0) }
        }
        if let presented {
          DispatchQueue.main.async { presented() }
        }
      }
    }

    #if DEBUG
      /// The destination given by `--unattended-sign-destination`, if any.
      internal static func unattendedDestination() -> URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let destIndex = args.firstIndex(of: "--unattended-sign-destination"),
          destIndex + 1 < args.count
        else { return nil }
        let raw = args[destIndex + 1]
        let expanded = raw.hasPrefix("~/") ? NSHomeDirectory() + raw.dropFirst() : raw
        return URL(fileURLWithPath: expanded)
      }
    #endif
  }

#endif
