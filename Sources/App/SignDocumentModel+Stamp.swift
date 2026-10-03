// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// The visible stamp built from the identity the card supplied.
  extension SignDocumentModel {
    /// The placed mark advising verification of the electronic signature.
    internal func visibleStamp(on document: Data) -> DocumentSigner.VisibleStamp? {
      guard let state = stampState else { return nil }
      let rendered = PdfStampRenderer.stampMark()
      guard let placed = StampPlacement.placed(rendered, on: document) else {
        return nil
      }
      return DocumentSigner.VisibleStamp(
        mark: placed,
        signerCertificate: state.signerCertificate
      )
    }

    /// One PAdES signature, with the optional visible stamp.
    internal func signPdf(
      _ source: URL,
      pin2: String,
      accessNumber: String,
      to destination: URL
    ) async throws {
      let stampStyle = DocumentStampStyle.load()
      // The card is read for the mark here, where the holder has
      // asked for a signature - not while they were still typing the
      // number that unlocks it.
      await readStamp(accessNumber: accessNumber, style: stampStyle)
      let document = try Data(contentsOf: source)
      let signedAt = Date()
      let visibleStamp = self.visibleStamp(on: document)
      #if DEBUG
        let reason =
          DebugRevokedDocumentSigning.isEnabled()
          ? DebugRevokedDocumentSigning.reason : nil
      #else
        let reason: String? = nil
      #endif
      let pdfClaim = PdfIncrementalSigner.SignatureClaim(
        signedAt: signedAt,
        reason: reason,
        location: nil
      )
      let result = try await DocumentSigner.sign(
        document,
        claim: pdfClaim,
        stamp: visibleStamp,
        access: DocumentSigner.SigningAccess(
          pin2: pin2,
          transport: .reader,
          cardAccessNumber: nil
        )
      )
      try result.bytes.write(to: destination, options: .atomic)
      #if DEBUG
        if result.completion == .revokedSignerTest {
          setNotice(DebugRevokedDocumentSigning.warning)
        }
      #endif
    }
  }

#endif
