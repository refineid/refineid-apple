// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether the long-term validation data a document keeps answers a
/// signature's path (EN 319 142-1 and EN 319 132-1, clause 6.3).
///
/// The chain and its validity are judged with every piece of evidence
/// the document carries; the level asks only of the revocation values
/// kept where the profile keeps long-term data, so values carried
/// elsewhere, inside a CMS among them, raise no level.
extension DocumentVerification {
  /// The OCSP responses and CRLs one place in a document keeps.
  internal struct RevocationValues {
    internal let ocspResponses: [Data]
    internal let revocationLists: [Data]

    /// Whether there is no value at all.
    internal var isEmpty: Bool { ocspResponses.isEmpty && revocationLists.isEmpty }
  }

  /// One archive timestamp and the revocation values the revision it
  /// covers keeps; nil when it covers the signature's own long-term
  /// values, as an XAdES archive timestamp does.
  internal struct ArchiveCandidate {
    internal let state: TimestampState
    internal let covered: RevocationValues?
  }

  /// Judges revocation values alone against one anchored path.
  internal struct LongTermJudgement {
    /// The anchored path, empty when the chain is not anchored.
    internal let path: [Data]

    /// Every certificate the document carries; any of them may issue
    /// an answer.
    internal let certificates: [Data]

    /// The validation time.
    internal let validationTime: Date

    /// The verifier's clock.
    internal let now: Date

    /// Whether `values` alone answer every certificate below the
    /// anchor as good.
    internal func answers(_ values: RevocationValues) -> Bool {
      guard !path.isEmpty, !values.isEmpty else { return false }
      var evidence = ValidationEvidence()
      evidence.add(certificates: certificates)
      evidence.add(ocspResponses: values.ocspResponses, revocationLists: values.revocationLists)
      let links = RevocationJudge.links(
        ofPath: path, evidence: evidence, at: validationTime, now: now)
      guard case .good = RevocationJudge.combined(links) else { return false }
      return true
    }

    /// The archive timestamps that count: each over the signature's own
    /// long-term values, or over a revision whose values answer the
    /// path.
    internal func archives(_ candidates: [ArchiveCandidate]) -> [TimestampState] {
      candidates.filter { candidate in candidate.covered.map(answers) ?? true }.map(\.state)
    }

    /// The level `facts` reach with `archives` counted.
    internal func level(
      _ facts: SignatureFacts,
      archives: [TimestampState],
      proven: Bool
    ) -> SignatureLevel? {
      SignatureLevel.reached(
        verifies: facts.documentIntact && facts.signatureValid,
        timestamped: proven,
        carriesValidationData: answers(facts.longTermValues),
        archived: archives.contains { stamp in stamp.provenTime != nil }
      )
    }
  }
}
