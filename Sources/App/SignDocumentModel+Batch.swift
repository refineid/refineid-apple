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

    /// The sentence for a document that was not signed: its failure,
    /// or the general one when the failure was withdrawn with the card.
    nonisolated internal static func refusal(after failure: String?) -> String {
      failure ?? DocumentSigningMessage.message(for: DocumentSigner.Failure.card(.noCard))
    }

    /// One sentence per document of a pile, in the pile's order.
    nonisolated private static func outcomes(
      of documents: [URL],
      failures: [URL: String],
      written: Set<URL>
    ) -> [String] {
      documents.compactMap { source in
        let name = source.lastPathComponent
        if let failure = failures[source] {
          return "\(name): \(failure)"
        }
        return written.contains(source) ? String(localized: "\(name) signed") : nil
      }
    }

    /// One ASiC-E signature over every file in `sources`, no visible
    /// stamp - the container carries the files unchanged, so there is
    /// no signed revision to draw a mark into.
    ///
    /// The files are read before the card is touched, so a container
    /// attests bytes that were all present at one instant.
    internal func signContainer(
      _ sources: [URL],
      pin2: String
    ) async throws -> SignedDocument {
      let objects = try sources.map { source in
        AsicSigner.dataObject(
          try Data(contentsOf: source), named: source.lastPathComponent
        )
      }
      let container = try await reportingPhases {
        try await AsicSigner.sign(
          objects,
          pin2: pin2,
          transport: .reader,
          cardAccessNumber: nil)
      }
      return SignedDocument(
        bytes: container.bytes, signatureTimestampTime: container.signatureTimestampTime
      )
    }

    /// Signs everything queued into one container, then asks `choose`
    /// where it goes.
    ///
    /// The whole pile under one signature, which is the shape ASiC-E
    /// exists for: a submission of several files that one signature
    /// covers. A PAdES batch stays several signatures, because a PDF
    /// carries its own and cannot carry another PDF's.
    internal func signTogether(pin2: String, destination choose: DestinationChoice) async {
      let sources = queued
      guard !sources.isEmpty, !working else { return }
      let appearance = beginSigning()
      defer { endSigning() }
      let finished: SignedDocument
      if DemoMode.shared.isActive, let first = sources.first {
        guard
          let simulated = await signWithVirtualCard(
            pin2: pin2, from: first, appearance: appearance
          )
        else { return }
        finished = simulated
      } else {
        do {
          finished = try await signContainer(sources, pin2: pin2)
        } catch {
          report(error, from: appearance)
          return
        }
      }
      show(nil)
      _ = await save(
        finished,
        originals: sources,
        refusal: String(
          localized: "The signed ASiC-E file cannot replace one of the originals."
        ),
        choose: choose
      )
    }

    /// Signs every queued document, then asks `choose` for the folder
    /// they all go to.
    ///
    /// Each output is named by its own best signature time. One
    /// document failing does not stop the rest. Each leaves a sentence
    /// behind, because a batch that reports only that it finished
    /// hides which documents were signed.
    internal func signAll(
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      folder choose: FolderChoice
    ) async {
      guard !working else { return }
      let documents = queued
      var signatures: [URL: SignedDocument] = [:]
      var refusals: [URL: String] = [:]
      _ = beginSigning()
      defer { endSigning() }
      beginPile()
      for source in documents {
        focus(on: source)
        let appearance = beginDocument()
        if let finished = await signature(
          of: source,
          pin2: pin2,
          accessNumber: accessNumber,
          format: format,
          appearance: appearance
        ) {
          signatures[source] = finished
        } else {
          refusals[source] = Self.refusal(after: failure)
        }
      }
      show(nil)
      endPile(failing: nil)
      let (failures, written) = await save(
        signatures, refusals: refusals, of: documents, format: format, choose: choose
      )
      record(batch: Self.outcomes(of: documents, failures: failures, written: written))
      if let message = Self.pileFailure(
        documents.compactMap { source in
          failures[source].map { (source.lastPathComponent, $0) }
        })
      {
        fail(message: message)
      }
      if let first = documents.first {
        focus(on: first)
      }
    }

    /// Writes a pile's finished signatures into a chosen folder,
    /// answering the sentence for every document that failed and the
    /// documents written.
    ///
    /// A file already in the folder is never overwritten; that
    /// document is reported. Any other failed write is shown and the
    /// folder is asked again for the documents still unwritten. A
    /// declined folder, once the holder forgets the signatures, leaves
    /// only the refusals.
    private func save(
      _ signatures: [URL: SignedDocument],
      refusals: [URL: String],
      of documents: [URL],
      format: SignatureFormat,
      choose: FolderChoice
    ) async -> (failures: [URL: String], written: Set<URL>) {
      var failures = refusals
      var written: Set<URL> = []
      var unwritten = documents.filter { signatures[$0] != nil }
      while !unwritten.isEmpty, let folder = await askedFolder(choose: choose) {
        var retry: [URL] = []
        var lastError: String?
        for source in unwritten {
          guard let finished = signatures[source] else { continue }
          focus(on: source)
          let destination = folder.appendingPathComponent(
            Self.suggestedName(for: source, format: format, at: finished.bestSignatureTime)
          )
          if Self.isOriginal(destination, among: documents) {
            failures[source] = String(
              localized: "The signed document cannot replace the original."
            )
            continue
          }
          do {
            try finished.bytes.write(to: destination, options: .withoutOverwriting)
            complete(with: destination)
            written.insert(source)
          } catch let error as CocoaError where error.code == .fileWriteFileExists {
            failures[source] = error.localizedDescription
          } catch {
            retry.append(source)
            lastError = error.localizedDescription
          }
        }
        unwritten = retry
        if let lastError {
          await failAndWait(lastError)
        }
      }
      return (failures, written)
    }
  }

#endif
