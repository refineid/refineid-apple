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

  /// One archive timestamp and the validation material its imprint covers.
  internal struct ArchiveCandidate {
    internal let state: TimestampState
    internal let covered: RevocationValues
    internal let coveredCertificates: [Data]

    /// Until when it keeps proving its time, when anchored.
    internal let validUntil: Date?
  }

  /// Judges revocation values alone against one anchored path.
  internal struct LongTermJudgement {
    /// The signer certificate at the leaf of the path.
    internal let signerCertificate: Data

    /// The anchored path, empty when the chain is not anchored.
    internal let path: [Data]

    /// Every certificate the document carries; any of them may issue
    /// an answer for baseline B-LT.
    internal let certificates: [Data]

    /// The validation time.
    internal let validationTime: Date

    /// The verifier's clock.
    internal let now: Date

    /// The validity end of the last anchored archive timestamp among
    /// `archives`, nil without one.
    ///
    /// `archives` are in document order: the one added last covers the
    /// others, whatever times their clocks name.
    internal static func validUntil(of archives: [ArchiveCandidate]) -> Date? {
      archives.last { stamp in stamp.state.provenTime != nil }?.validUntil
    }

    /// Whether `values` and `candidateCertificates` alone answer every certificate below the anchor as good.
    internal func answers(_ values: RevocationValues, certificates candidateCertificates: [Data])
      -> Bool
    {
      guard !path.isEmpty, !values.isEmpty else { return false }
      var evidence = ValidationEvidence()
      evidence.addCardReadCertificates(issuing: signerCertificate)
      evidence.add(certificates: candidateCertificates)
      let coveredCertificates = Set(evidence.certificates)
      guard path.dropFirst().dropLast().allSatisfy(coveredCertificates.contains) else {
        return false
      }
      evidence.add(certificates: path)
      evidence.add(ocspResponses: values.ocspResponses, revocationLists: values.revocationLists)
      let links = RevocationJudge.links(
        ofPath: path, evidence: evidence, at: validationTime, now: now)
      guard case .good = RevocationJudge.combined(links) else { return false }
      return true
    }

    /// The archive timestamps that count: each over material whose values answer the path.
    internal func archives(_ candidates: [ArchiveCandidate]) -> [ArchiveCandidate] {
      candidates.filter { candidate in
        answers(candidate.covered, certificates: candidate.coveredCertificates)
      }
    }

    /// The level `facts` reach with `archives` counted.
    internal func level(
      _ facts: SignatureFacts,
      archives: [ArchiveCandidate],
      proven: Bool
    ) -> SignatureLevel? {
      SignatureLevel.reached(
        verifies: facts.documentIntact && facts.signatureValid,
        timestamped: proven,
        carriesValidationData: answers(facts.longTermValues, certificates: certificates),
        archived: archives.contains { stamp in stamp.state.provenTime != nil }
      )
    }
  }
}
