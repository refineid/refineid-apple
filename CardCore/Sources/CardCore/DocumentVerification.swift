// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Verifies the signatures of a signed PDF or ASiC container
/// (EN 319 102-1).
///
/// The verdict is computed offline from the file and the trust
/// anchors: document integrity, the signature over its signed data,
/// the signer's path to a certificate-issuing anchor, every timestamp
/// against the time-stamping anchors, and the revocation evidence the
/// document carries. A signature still without revocation status may
/// later take a live answer through `SignatureReport.withLiveRevocation`.
public enum DocumentVerification {
  /// One signature's verified facts.
  public struct SignatureReport: Sendable {
    /// The signer certificate's subject commonName exactly as the
    /// certificate carries it, empty when it carries none.
    public let signerCommonName: String

    /// The electronic identifier the signer certificate carries.
    public let signerIdentifier: String

    /// The signer certificate, for revocation checks.
    public let signerCertificate: Data

    /// Whether every byte the signature claims to cover digests to the
    /// value it states.
    public let documentIntact: Bool

    /// Whether the signature verifies over its signed data.
    public let signatureValid: Bool

    /// The signer's path to a certificate-issuing anchor at the
    /// validation time.
    public let chain: ChainStatus

    /// Every signature timestamp, in encoding order.
    public let timestamps: [TimestampState]

    /// The proof of existence, or the verifier's clock without one; the
    /// chain and revocation are judged at this time.
    public let validationTime: ValidationTime

    /// The revocation status of each certificate below the anchor.
    internal let revocationLinks: [RevocationJudge.Link]

    /// Whether the signature's byte ranges cover the whole file.
    public let coversWholeDocument: Bool

    /// Whether the signer is fit to sign and anchored.
    public var chainVerified: Bool { chain.isAnchored }

    /// The certificate that issued the signer.
    public var issuerCertificate: Data? { chain.issuerCertificate }

    /// The earliest time an anchored timestamp proves, its own or a
    /// document timestamp covering it.
    public var proofOfExistence: Date? { validationTime.proofOfExistence }

    /// The revocation status of the signer's path.
    public var revocation: RevocationState {
      chainVerified ? RevocationJudge.combined(revocationLinks) : .unavailable
    }

    /// The one-line verdict of the facts above.
    public var isValid: Bool {
      documentIntact && signatureValid && chainVerified
        && !revocation.invalidates(proofOfExistence: proofOfExistence)
    }

    /// The time a verifying timestamp claims when none is anchored.
    public var claimedTime: Date? {
      timestamps.compactMap(\.claimedTime).min()
    }

    /// Whether any timestamp of this signature failed or could not be
    /// judged.
    public var hasInvalidTimestamp: Bool {
      timestamps.contains(.invalid) || timestamps.contains(.unsupported)
    }

    /// The path certificates whose status the document left
    /// unavailable, which a live answer may give.
    public var pendingRevocationQueries: [RevocationQuery] {
      guard chainVerified else { return [] }
      return revocationLinks.filter { link in link.state == .unavailable }
        .map { link in RevocationQuery(certificate: link.certificate, issuer: link.issuer) }
    }

    /// The report with live revocation answers applied.
    ///
    /// Each path certificate still unavailable takes the live answer
    /// that speaks for it, judged at `now`; a chain that is not
    /// anchored takes none.
    public func withLiveRevocation(
      ocspResponses: [Data],
      revocationLists: [Data],
      now: Date
    ) -> Self {
      guard chainVerified else { return self }
      var evidence = ValidationEvidence()
      evidence.add(ocspResponses: ocspResponses, revocationLists: revocationLists)
      let links = revocationLinks.map { link in
        guard link.state == .unavailable else { return link }
        return RevocationJudge.Link(
          certificate: link.certificate,
          issuer: link.issuer,
          state: RevocationJudge.status(
            of: link.certificate, issuer: link.issuer, evidence: evidence, at: now, now: now)
        )
      }
      return Self(
        signerCommonName: signerCommonName,
        signerIdentifier: signerIdentifier,
        signerCertificate: signerCertificate,
        documentIntact: documentIntact,
        signatureValid: signatureValid,
        chain: chain,
        timestamps: timestamps,
        validationTime: validationTime,
        revocationLinks: links,
        coversWholeDocument: coversWholeDocument
      )
    }
  }

  /// One path certificate and its issuer, for a live revocation check.
  public struct RevocationQuery: Sendable, Equatable {
    /// The certificate whose status is asked.
    public let certificate: Data

    /// The certificate that issued it on the path.
    public let issuer: Data
  }

  /// One signature found in the document.
  public enum SignatureEntry: Sendable {
    /// A signature the verifier judged.
    case judged(SignatureReport)

    /// A signature the verifier cannot read: another profile,
    /// algorithm or structure, a counter-signature, or a range that
    /// does not end a revision.
    case unsupported
  }

  /// Why a document yielded no report.
  public enum Failure: Error, Sendable {
    case noSignatures
    case notAPdf
    case unreadable
    case unsupportedProfile
  }

  /// The complete verification of one document.
  public struct DocumentReport: Sendable {
    /// Every signature found, in document order.
    public let signatures: [SignatureEntry]

    /// Every PDF document timestamp, in document order.
    public let documentTimestamps: [TimestampState]

    /// Whether the document has a signature, every signature is valid,
    /// and none is unsupported.
    public var isValid: Bool {
      !signatures.isEmpty
        && signatures.allSatisfy { entry in
          guard case .judged(let report) = entry else { return false }
          return report.isValid
        }
    }
  }

  /// The facts of one signature before its chain is judged.
  internal struct SignatureFacts {
    internal let signerCertificate: Data
    internal let documentIntact: Bool
    internal let signatureValid: Bool
    internal let timestamps: [TimestampState]
    internal let creditedProofs: [ProvenTime]
    internal let coversWholeDocument: Bool
  }

  /// Verifies every signature and document timestamp of the document
  /// under `anchors`, with `now` as the current time.
  public static func verify(
    document: Data,
    anchors: TrustAnchors = .pinned,
    now: Date = Date()
  ) throws -> DocumentReport {
    if ZipReader.hasZipSignature(document) {
      return try AsicVerification.verify(container: document, anchors: anchors, now: now)
    }
    return try Self.verifyPdf(document, anchors: anchors, now: now)
  }

  /// Judges the chain and revocation of one signature whose other
  /// facts are known.
  internal static func report(
    _ facts: SignatureFacts,
    evidence documentEvidence: ValidationEvidence,
    anchors: TrustAnchors,
    now: Date
  ) -> SignatureReport? {
    guard let subject = CertificateFacts(der: facts.signerCertificate)?.subjectName else {
      return nil
    }
    let proofs = facts.timestamps.compactMap(\.provenTime) + facts.creditedProofs
    let validationTime = proofs.min().map(ValidationTime.proven) ?? .currentClock(now)
    var evidence = ValidationEvidence()
    evidence.addCardReadCertificates(issuing: facts.signerCertificate)
    evidence.add(certificates: documentEvidence.certificates)
    evidence.add(
      ocspResponses: documentEvidence.ocspResponses,
      revocationLists: documentEvidence.revocationLists
    )
    let path = CertificatePath.anchored(
      facts.signerCertificate,
      candidates: evidence.certificates,
      anchors: anchors.certificateIssuing,
      at: validationTime.date
    )
    let chain: ChainStatus =
      !path.isEmpty && CertificatePath.isFitToSign(facts.signerCertificate)
      ? .anchored(path: path)
      : .unanchored(
        directIssuer: CertificatePath.directIssuer(
          of: facts.signerCertificate, candidates: evidence.certificates,
          at: validationTime.date))
    let links =
      chain.isAnchored
      ? RevocationJudge.links(
        ofPath: path, evidence: evidence, at: validationTime.date, now: now)
      : []
    return SignatureReport(
      signerCommonName: DistinguishedName.commonName(inName: subject) ?? "",
      signerIdentifier: DistinguishedName.identifier(inName: subject) ?? "",
      signerCertificate: facts.signerCertificate,
      documentIntact: facts.documentIntact,
      signatureValid: facts.signatureValid,
      chain: chain,
      timestamps: facts.timestamps,
      validationTime: validationTime,
      revocationLinks: links,
      coversWholeDocument: facts.coversWholeDocument
    )
  }
}
