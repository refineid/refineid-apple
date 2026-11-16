// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// PAdES verification (EN 319 142-1).
extension DocumentVerification {
  /// One PDF document timestamp, where its range starts, and the
  /// revocation values of the document security store the revision it
  /// covers carries (EN 319 142-1 clause 5.5).
  private struct DocumentTimestamp {
    let judged: TimestampJudge.Judged
    var state: TimestampState { judged.state }
    let rangeStart: Int
    let coveredValues: RevocationValues
  }

  /// What every signature of one PDF is judged with.
  private struct PdfJudgement {
    let evidence: ValidationEvidence
    let anchors: TrustAnchors
    let now: Date
    let storeValues: RevocationValues
  }

  /// What one PDF signature is judged with, besides its own bytes.
  private struct SignatureCandidates {
    let creditedProofs: [ProvenTime]
    let archiveTimestamps: [ArchiveCandidate]
    let changesAfterSigning: [SignedContentChange]
  }

  /// Pre-verified CMS facts for one located signature dictionary.
  private struct PreparedSignature {
    let located: PdfSignatureReader.LocatedSignature
    let profile: CmsSignerVerification.Profile?
    let outcome: CmsSignerVerification.Outcome?
  }

  /// The revocation values of a document security store.
  private static func revocationValues(_ store: PdfValidationStore.Material) -> RevocationValues {
    RevocationValues(ocspResponses: store.ocspResponses, revocationLists: store.revocationLists)
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
    let located: [PdfSignatureReader.LocatedSignature]
    do {
      located = try PdfSignatureReader.locatedSignatures(
        in: document,
        maximumByteCount: PdfValues.maximumVerifiedDocumentByteCount
      )
    } catch let failure as PdfSigningError {
      throw failure == .notAPdf ? Failure.notAPdf : Failure.unreadable
    } catch {
      throw Failure.unreadable
    }
    guard located.contains(where: { item in item.signature.subFilter != .rfc3161 }) else {
      throw Failure.noSignatures
    }

    var documentEvidence = ValidationEvidence()
    let store = PdfDocumentSecurityStore.material(in: document)
    documentEvidence.add(store)
    for item in located {
      documentEvidence.add(cms: item.signature.cms)
    }
    let prepared = Self.prepareSignatures(located)
    let postCandidates = Self.postSignatureCandidates(from: prepared)
    let judgement = PdfJudgement(
      evidence: documentEvidence, anchors: anchors, now: now,
      storeValues: Self.revocationValues(store)
    )
    let found = located.map(\.signature)
    let documentTimestamps = Self.documentTimestamps(in: found, judgement)
    let signatures: [SignatureEntry] =
      prepared
      .filter { item in item.located.signature.subFilter != .rfc3161 }
      .map { item in
        Self.entry(
          of: item,
          document: document,
          judgement: judgement,
          documentTimestamps: documentTimestamps,
          postCandidates: postCandidates
        )
      }
    return DocumentReport(
      signatures: signatures,
      documentTimestamps: documentTimestamps.map(\.state)
    )
  }

  /// Evaluates `CmsSignerVerification` once per located signature.
  private static func prepareSignatures(
    _ located: [PdfSignatureReader.LocatedSignature]
  ) -> [PreparedSignature] {
    located.map { item in
      let profile = Self.profile(ofSubFilter: item.signature.subFilter)
      let outcome: CmsSignerVerification.Outcome?
      if let profile, item.signature.endsRevision {
        outcome = CmsSignerVerification.verify(
          cms: item.signature.cms,
          signedOctets: item.signature.signedSpans.signedOctets,
          profile: profile
        )
      } else {
        outcome = nil
      }
      return PreparedSignature(located: item, profile: profile, outcome: outcome)
    }
  }

  /// Converts prepared signatures into revision-analysis candidates.
  private static func postSignatureCandidates(
    from prepared: [PreparedSignature]
  ) -> [PdfSignedContentAnalysis.PostSignatureCandidate] {
    prepared.compactMap { item in
      guard item.located.signature.endsRevision else { return nil }
      let verified =
        item.outcome?.documentIntact == true
        && item.outcome?.signatureValid == true
      return PdfSignedContentAnalysis.PostSignatureCandidate(
        objectNumber: item.located.objectNumber,
        location: item.located.location,
        revisionEnd: item.located.signature.signedSpans.document.count,
        isTimestamp: item.located.signature.subFilter == .rfc3161,
        isCryptographicallyVerified: verified
      )
    }
  }

  /// The row one signature dictionary makes.
  private static func entry(
    of prepared: PreparedSignature,
    document: Data,
    judgement: PdfJudgement,
    documentTimestamps: [DocumentTimestamp],
    postCandidates: [PdfSignedContentAnalysis.PostSignatureCandidate]
  ) -> SignatureEntry {
    let signature = prepared.located.signature
    let covering = documentTimestamps.filter { stamp in
      signature.signedSpans.document.count <= stamp.rangeStart
    }
    let candidates = SignatureCandidates(
      creditedProofs: covering.compactMap(\.state.provenTime),
      archiveTimestamps: covering.map { stamp in
        ArchiveCandidate(
          state: stamp.state, covered: stamp.coveredValues, validUntil: stamp.judged.validUntil)
      },
      changesAfterSigning: PdfSignedContentAnalysis.changes(
        document: document,
        signedEnd: signature.signedSpans.document.count,
        candidates: postCandidates
      )
    )
    guard
      signature.endsRevision,
      let outcome = prepared.outcome,
      let report = Self.report(of: signature, outcome: outcome, candidates, judgement)
    else {
      return .unsupported
    }
    return .judged(report)
  }

  /// Every document timestamp of the found signatures, in document
  /// order.
  private static func documentTimestamps(
    in found: [PdfSignatureReader.FoundSignature],
    _ judgement: PdfJudgement
  ) -> [DocumentTimestamp] {
    found.filter { signature in signature.subFilter == .rfc3161 }
      .sorted { lhs, rhs in lhs.signedSpans.document.count < rhs.signedSpans.document.count }
      .map { signature in
        DocumentTimestamp(
          judged: Self.documentTimestampState(
            of: signature,
            evidence: judgement.evidence,
            anchors: judgement.anchors,
            now: judgement.now
          ),
          rangeStart: signature.signedSpans.contentsOpen,
          coveredValues: Self.revocationValues(
            PdfDocumentSecurityStore.material(in: signature.signedSpans.document))
        )
      }
  }

  /// What one document timestamp's token was found to be.
  private static func documentTimestampState(
    of signature: PdfSignatureReader.FoundSignature,
    evidence: ValidationEvidence,
    anchors: TrustAnchors,
    now: Date
  ) -> TimestampJudge.Judged {
    guard signature.endsRevision else {
      return TimestampJudge.Judged(state: .invalid, validUntil: nil)
    }
    return TimestampJudge.judged(
      signature.cms,
      imprintMatches: { digest, imprint in
        imprint == digest.hash(signature.signedSpans.signedOctets)
      },
      evidence: evidence,
      anchors: anchors,
      now: now
    )
  }

  /// What a signature subfilter requires, nil for one this verifier
  /// does not judge: PAdES baseline signatures need the ESS binding and
  /// carry no signing-time (EN 319 142-1 clause 6.3); PKCS #7 detached
  /// signatures need neither (EN 319 142-2 clause 4.2.3).
  internal static func profile(
    ofSubFilter subFilter: PdfSubFilter
  ) -> CmsSignerVerification.Profile? {
    switch subFilter {
    case .cades:
      CmsSignerVerification.Profile(requiresSigningCertificate: true, forbidsSigningTime: true)

    case .pkcs7:
      CmsSignerVerification.Profile(requiresSigningCertificate: false, forbidsSigningTime: false)

    case .rfc3161, .other:
      nil
    }
  }

  /// The report of one PDF signature whose CMS was already verified.
  private static func report(
    of signature: PdfSignatureReader.FoundSignature,
    outcome: CmsSignerVerification.Outcome,
    _ candidates: SignatureCandidates,
    _ judgement: PdfJudgement
  ) -> SignatureReport? {
    let anchors = judgement.anchors
    let now = judgement.now
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
        anchors: anchors,
        now: now
      )
    }
    return Self.report(
      SignatureFacts(
        signerCertificate: outcome.signerCertificate,
        documentIntact: outcome.documentIntact,
        signatureValid: outcome.signatureValid,
        timestamps: timestamps,
        creditedProofs: candidates.creditedProofs,
        coversWholeDocument: signature.coversWholeDocument,
        changesAfterSigning: candidates.changesAfterSigning,
        archiveTimestamps: candidates.archiveTimestamps,
        longTermValues: judgement.storeValues
      ),
      evidence: evidence,
      anchors: anchors,
      now: now
    )
  }
}
