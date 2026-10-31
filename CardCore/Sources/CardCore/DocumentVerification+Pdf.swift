// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// PAdES verification (EN 319 142-1).
extension DocumentVerification {
  /// One PDF document timestamp and where its range starts.
  private struct DocumentTimestamp {
    let state: TimestampState
    let rangeStart: Int
  }

  /// What every signature of one PDF is judged with.
  private struct PdfJudgement {
    let evidence: ValidationEvidence
    let anchors: TrustAnchors
    let now: Date
  }

  /// Verifies every signature dictionary and document timestamp of a
  /// PDF.
  ///
  /// Every signature dictionary is a row: one with another subfilter,
  /// a CMS this verifier does not read, or a range that does not end a
  /// revision is an unsupported row.
  internal static func verifyPdf(
    _ document: Data,
    anchors: TrustAnchors,
    now: Date
  ) throws -> DocumentReport {
    let found: [PdfSignatureReader.FoundSignature]
    do {
      found = try PdfSignatureReader.signatures(in: document)
    } catch let failure as PdfSigningError {
      throw failure == .notAPdf ? Failure.notAPdf : Failure.unreadable
    } catch {
      throw Failure.unreadable
    }
    guard !found.isEmpty else { throw Failure.noSignatures }

    var documentEvidence = ValidationEvidence()
    documentEvidence.add(PdfDocumentSecurityStore.material(in: document))
    for signature in found {
      documentEvidence.add(cms: signature.cms)
    }
    let judgement = PdfJudgement(evidence: documentEvidence, anchors: anchors, now: now)
    let documentTimestamps = Self.documentTimestamps(in: found, judgement)
    let signatures: [SignatureEntry] = found.filter { signature in
      signature.subFilter != .rfc3161
    }
    .map { signature in
      let credited = documentTimestamps.filter { stamp in
        signature.signedSpans.document.count <= stamp.rangeStart
      }
      .compactMap(\.state.provenTime)
      guard
        let profile = Self.profile(ofSubFilter: signature.subFilter),
        signature.endsRevision,
        let report = Self.report(
          of: signature, profile: profile, creditedProofs: credited, judgement
        )
      else {
        return .unsupported
      }
      return .judged(report)
    }
    return DocumentReport(
      signatures: signatures,
      documentTimestamps: documentTimestamps.map(\.state)
    )
  }

  /// Every document timestamp of the found signatures.
  private static func documentTimestamps(
    in found: [PdfSignatureReader.FoundSignature],
    _ judgement: PdfJudgement
  ) -> [DocumentTimestamp] {
    found.filter { signature in signature.subFilter == .rfc3161 }
      .map { signature in
        DocumentTimestamp(
          state: Self.documentTimestampState(
            of: signature,
            evidence: judgement.evidence,
            anchors: judgement.anchors,
            now: judgement.now
          ),
          rangeStart: signature.signedSpans.contentsOpen
        )
      }
  }

  /// What one document timestamp's token was found to be.
  ///
  /// The imprint is taken under the token's own messageImprint hash
  /// algorithm (RFC 3161 section 2.4.2) over the byte ranges; a range
  /// that does not end a revision cannot be judged and is invalid.
  private static func documentTimestampState(
    of signature: PdfSignatureReader.FoundSignature,
    evidence: ValidationEvidence,
    anchors: TrustAnchors,
    now: Date
  ) -> TimestampState {
    guard signature.endsRevision else { return .invalid }
    return TimestampJudge.state(
      of: signature.cms,
      imprintMatches: { digest, imprint in
        imprint == digest.hash(signature.signedSpans.signedOctets)
      },
      evidence: evidence,
      anchors: anchors.timeStamping,
      now: now
    )
  }

  /// What a signature subfilter requires, nil for one this verifier
  /// does not judge: PAdES baseline signatures need the ESS binding and
  /// carry no signing-time (EN 319 142-1 clause 6.3); PKCS #7 detached
  /// signatures need neither (EN 319 142-2 clause 4.2.3).
  private static func profile(ofSubFilter subFilter: PdfSubFilter) -> CmsSignerVerification.Profile?
  {
    switch subFilter {
    case .cades:
      CmsSignerVerification.Profile(requiresSigningCertificate: true, forbidsSigningTime: true)

    case .pkcs7:
      CmsSignerVerification.Profile(requiresSigningCertificate: false, forbidsSigningTime: false)

    case .rfc3161, .other:
      nil
    }
  }

  /// The report of one PDF signature, or nil when its CMS or signer
  /// cannot be read.
  private static func report(
    of signature: PdfSignatureReader.FoundSignature,
    profile: CmsSignerVerification.Profile,
    creditedProofs: [ProvenTime],
    _ judgement: PdfJudgement
  ) -> SignatureReport? {
    let anchors = judgement.anchors
    let now = judgement.now
    guard
      let outcome = CmsSignerVerification.verify(
        cms: signature.cms,
        signedOctets: signature.signedSpans.signedOctets,
        profile: profile
      )
    else {
      return nil
    }
    var evidence = judgement.evidence
    evidence.add(certificates: outcome.embeddedCertificates)
    for token in outcome.timestampTokens {
      evidence.add(cms: token)
    }
    let timestamps = outcome.timestampTokens.map { token in
      TimestampJudge.state(
        of: token,
        imprintMatches: { digest, imprint in
          imprint == digest.hash(outcome.signatureValue)
        },
        evidence: evidence,
        anchors: anchors.timeStamping,
        now: now
      )
    }
    return Self.report(
      SignatureFacts(
        signerCertificate: outcome.signerCertificate,
        documentIntact: outcome.documentIntact,
        signatureValid: outcome.signatureValid,
        timestamps: timestamps,
        creditedProofs: creditedProofs,
        coversWholeDocument: signature.coversWholeDocument
      ),
      evidence: evidence,
      anchors: anchors,
      now: now
    )
  }

}
