// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Judges the revocation evidence for certificates on a validated
/// path, offline.
internal enum RevocationJudge {
  /// One verified answer for one certificate.
  private enum Answer {
    case good(Date)
    case revoked(Date, RevocationReason?)
  }

  /// One certificate below the anchor, its issuer on the path, and
  /// the status its evidence establishes.
  internal struct Link: Sendable {
    internal let certificate: Data
    internal let issuer: Data
    internal let state: RevocationState
  }

  /// How far an answer may be dated past the verifier's clock before
  /// it speaks for nothing.
  private static let maximumClockSkew = OcspResponse.maximumClockSkew

  /// Each certificate below the anchor of `path`, with its status.
  ///
  /// Statuses are judged at `validationTime`. A path of one, an anchor
  /// itself, has none.
  internal static func links(
    ofPath path: [Data],
    evidence: ValidationEvidence,
    at validationTime: Date,
    now: Date
  ) -> [Link] {
    guard path.count > 1 else { return [] }
    return (0..<(path.count - 1)).map { position in
      Link(
        certificate: path[position],
        issuer: path[position + 1],
        state: Self.status(
          of: path[position],
          issuer: path[position + 1],
          evidence: evidence,
          at: validationTime,
          now: now
        )
      )
    }
  }

  /// The status of a path from its links.
  ///
  /// Any revocation is reported, a compromise first and then the
  /// earliest; otherwise any link
  /// without an answer leaves the path unavailable; otherwise the path
  /// is good at the signer's evidence time. A path without links, an
  /// anchor itself, is unavailable.
  internal static func combined(_ links: [Link]) -> RevocationState {
    var revocation: RevocationState?
    for link in links {
      if case .revoked = link.state {
        revocation = Self.graver(revocation, link.state)
      }
    }
    if let revocation { return revocation }
    guard
      let signer = links.first,
      !links.contains(where: { link in link.state == .unavailable })
    else {
      return .unavailable
    }
    return signer.state
  }

  /// The status of the path's certificates below the anchor at
  /// `validationTime`, combined as `combined(_:)` does.
  internal static func status(
    ofPath path: [Data],
    evidence: ValidationEvidence,
    at validationTime: Date,
    now: Date
  ) -> RevocationState {
    Self.combined(
      Self.links(ofPath: path, evidence: evidence, at: validationTime, now: now))
  }

  /// The status of one certificate under its issuer at
  /// `validationTime`.
  ///
  /// OCSP and CRL answers are weighed together: a verified revoked
  /// answer outweighs good ones; among good answers the latest
  /// evidence time is reported. A good answer counts only when its
  /// window covers the validation time, or when it was issued after
  /// the validation time while the certificate was still valid, and
  /// never when it is dated past the verifier's clock (EN 319 102-1
  /// clauses 5.2.5 and 5.6.2).
  internal static func status(
    of certificate: Data,
    issuer: Data,
    evidence: ValidationEvidence,
    at validationTime: Date,
    now: Date
  ) -> RevocationState {
    guard let validity = CertificateValidity.window(inDer: certificate) else {
      return .unavailable
    }
    var answers: [Answer] = []
    for response in evidence.ocspResponses {
      guard
        let answer = try? OcspResponse.evidence(
          response: response, certificate: certificate, issuerCertificate: issuer
        )
      else { continue }
      switch answer.status {
      case .revoked(let revokedAt, let reason):
        answers.append(.revoked(revokedAt, reason))

      case .good:
        if Self.windowAccepted(
          thisUpdate: answer.thisUpdate,
          nextUpdate: answer.nextUpdate,
          notAfter: validity.notAfter,
          at: validationTime,
          now: now
        ) {
          answers.append(.good(answer.producedAt))
        }
      }
    }
    for list in evidence.revocationLists {
      guard
        let answer = try? CertificateRevocationList.evidence(
          crl: list, certificate: certificate, issuerCertificate: issuer
        )
      else { continue }
      if let revoked = answer.revocation {
        answers.append(.revoked(revoked.revokedAt, revoked.reason))
      } else if Self.windowAccepted(
        thisUpdate: answer.thisUpdate,
        nextUpdate: answer.nextUpdate,
        notAfter: validity.notAfter,
        at: validationTime,
        now: now
      ) {
        answers.append(.good(answer.thisUpdate))
      }
    }
    return Self.strongest(answers)
  }

  /// Whether a good answer with this window speaks for the validation
  /// time.
  private static func windowAccepted(
    thisUpdate: Date,
    nextUpdate: Date?,
    notAfter: Date,
    at validationTime: Date,
    now: Date
  ) -> Bool {
    let postDated = thisUpdate > now.addingTimeInterval(Self.maximumClockSkew)
    let containsValidationTime =
      thisUpdate <= validationTime && validationTime <= (nextUpdate ?? thisUpdate)
    let issuedAfterWhileValid = validationTime <= thisUpdate && thisUpdate <= notAfter
    return !postDated && (containsValidationTime || issuedAfterWhileValid)
  }

  /// A revoked answer outweighs good ones; the latest good evidence
  /// time is reported otherwise.
  private static func strongest(_ answers: [Answer]) -> RevocationState {
    var good: Date?
    var revocation: RevocationState?
    for answer in answers {
      switch answer {
      case .good(let evidenceTime):
        good = max(good ?? evidenceTime, evidenceTime)

      case .revoked(let revokedAt, let reason):
        revocation = Self.graver(revocation, .revoked(revokedAt, reason))
      }
    }
    if let revocation { return revocation }
    return good.map(RevocationState.good) ?? .unavailable
  }

  /// Of two revocations, the one to report: a compromise before any
  /// other, then the earlier.
  private static func graver(
    _ known: RevocationState?,
    _ candidate: RevocationState
  ) -> RevocationState {
    guard
      case .revoked(let knownAt, let knownReason) = known,
      case .revoked(let candidateAt, let candidateReason) = candidate
    else {
      return candidate
    }
    let knownCompromise = knownReason?.isCompromise == true
    let candidateCompromise = candidateReason?.isCompromise == true
    if knownCompromise != candidateCompromise {
      return candidateCompromise ? candidate : known ?? candidate
    }
    return candidateAt < knownAt ? candidate : known ?? candidate
  }
}
