// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// Signing everything that was dropped, in one pass.
  extension SignDocumentModel {
    /// One sentence for every document of a pile that was not signed.
    ///
    /// A cause shared by every failed document is said once.
    nonisolated internal static func pileFailure(
      _ failures: [(name: String, message: String)]
    ) -> String? {
      guard let first = failures.first else { return nil }
      if failures.allSatisfy({ $0.message == first.message }) {
        let names = failures.map(\.name).joined(separator: "\n")
        return names + "\n\n" + first.message
      }
      return failures.map { "\($0.name): \($0.message)" }.joined(separator: "\n")
    }

    /// One ASiC-E signature over every file in `sources`, no visible
    /// stamp - the container carries the files unchanged, so there is
    /// no signed revision to draw a mark into.
    ///
    /// The files are read before the card is touched, so a container
    /// attests bytes that were all present at one instant.
    internal func signContainer(
      _ sources: [URL],
      pin2: String,
      to destination: URL
    ) async throws {
      let objects = try sources.map { source in
        AsicSigner.dataObject(
          try Data(contentsOf: source), named: source.lastPathComponent
        )
      }
      let container = try await AsicSigner.sign(
        objects,
        pin2: pin2,
        transport: .reader,
        cardAccessNumber: nil)
      try container.write(to: destination, options: .atomic)
    }

    /// Signs everything queued into one container.
    ///
    /// The whole pile under one signature, which is the shape ASiC-E
    /// exists for: a submission of several files that one signature
    /// covers. A PAdES batch stays several signatures, because a PDF
    /// carries its own and cannot carry another PDF's.
    internal func signTogether(pin2: String, to destination: URL) async {
      let sources = queued
      guard !sources.isEmpty, !working else { return }
      // Replacing any original is refused for the same reason a single
      // signature refuses it: it destroys the only unsigned copy of a
      // file the signature attests.
      let originals = Set(sources.map(\.standardizedFileURL))
      guard !originals.contains(destination.standardizedFileURL) else {
        report(
          String(
            localized: "The signed container cannot replace one of the originals."
          )
        )
        return
      }
      let appearance = beginSigning()
      defer { endSigning() }
      if DemoMode.shared.isActive, let first = sources.first {
        await signWithVirtualCard(
          pin2: pin2,
          from: first,
          to: destination,
          appearance: appearance
        )
        return
      }
      do {
        try await signContainer(sources, pin2: pin2, to: destination)
        complete(with: destination)
      } catch {
        report(error, from: appearance)
      }
    }

    /// Signs every queued document into `directory`.
    ///
    /// The folder is granted once, before the card is touched, for the
    /// same reason a single signature asks for its file first: a panel
    /// answered after signing could be cancelled with a signature
    /// already spent.
    ///
    /// One document failing does not stop the rest. Each leaves a
    /// sentence behind, because a batch that reports only that it
    /// finished hides which documents were signed.
    internal func signAll(
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      intoDirectory directory: URL
    ) async {
      let instant = Date()
      guard !working else { return }
      let documents = queued
      var outcomes: [String] = []
      var failures: [(name: String, message: String)] = []
      beginPile()
      for source in documents {
        focus(on: source)
        let destination = directory.appendingPathComponent(
          Self.destination(for: source, at: instant, format: format).lastPathComponent
        )
        await sign(
          pin2: pin2, accessNumber: accessNumber, format: format, to: destination
        )
        if let failure {
          outcomes.append("\(source.lastPathComponent): \(failure)")
          failures.append((source.lastPathComponent, failure))
        } else {
          outcomes.append(
            String(localized: "\(source.lastPathComponent) signed")
          )
        }
      }
      record(batch: outcomes)
      endPile(failing: Self.pileFailure(failures))
      if let first = documents.first {
        focus(on: first)
      }
    }
  }

#endif
