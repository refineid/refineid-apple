// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Verifies the signatures of a signed PDF in the profile this suite
/// produces.
///
/// The verdict is computed entirely offline: document integrity from
/// the declared byte ranges, the signature over the canonical signed
/// attributes, the ESS-bound signer certificate, its chain step to the
/// issuer, and every signature timestamp against the token's
/// own authenticated chain. Revocation is deliberately not answered
/// here; the caller holds the signer and issuer and decides which
/// evidence basis to consult.
public enum DocumentVerification {
  /// One signature's verified facts.
  public struct SignatureReport: Sendable {
    /// The holder the signer certificate names.
    public let signerName: String

    /// The electronic identifier the signer certificate carries.
    public let signerIdentifier: String

    /// The signer certificate, for revocation checks.
    public let signerCertificate: Data

    /// The issuer the chain step was proven against, when one
    /// matched.
    public let issuerCertificate: Data?

    /// Whether the byte-range digest equals the signed message digest.
    public let documentIntact: Bool

    /// Whether the signature verifies over the canonical attributes.
    public let signatureValid: Bool

    /// Whether the signer is directly issued by the issuer.
    public let chainVerified: Bool

    /// The earliest verified signature-timestamp time.
    public let timestampedAt: Date?

    /// Whether every present timestamp token verified and matched the
    /// signature it timestamps.
    ///
    /// False when none is present.
    public let timestampsValid: Bool

    /// Whether the signature's byte ranges cover the whole file.
    public let coversWholeDocument: Bool

    /// The one-line verdict of the facts above.
    public var isValid: Bool {
      documentIntact && signatureValid && chainVerified && timestampsValid
    }
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
    /// Every signature's verified facts, in document order.
    public let signatures: [SignatureReport]

    /// The generation times of the verified document timestamps.
    public let documentTimestampedAt: [Date]
  }

  /// The subfilter of the one CMS signature profile this verifier reads.
  private static let signatureSubFilter = "ETSI.CAdES.detached"

  /// The subfilter of a PAdES document timestamp.
  private static let documentTimestampSubFilter = "ETSI.RFC3161"

  /// Verifies every signature and document timestamp of the document.
  public static func verify(
    document: Data
  ) throws -> DocumentReport {
    if AsicVerification.isAsicContainer(document) {
      return try AsicVerification.verify(container: document)
    }
    let found: [PdfSignatureReader.FoundSignature]
    do {
      found = try PdfSignatureReader.signatures(in: document)
    } catch let failure as PdfSigningError {
      throw failure == .notAPdf ? Failure.notAPdf : Failure.unreadable
    } catch {
      throw Failure.unreadable
    }
    let signatures =
      try found
      .filter { $0.subFilter == Self.signatureSubFilter }
      .map { try report(of: $0) }
    guard !signatures.isEmpty else {
      throw found.isEmpty ? Failure.noSignatures : Failure.unsupportedProfile
    }
    let timestamps =
      found
      .filter { $0.subFilter == Self.documentTimestampSubFilter }
      .compactMap(documentTimestamp(of:))
    return DocumentReport(
      signatures: signatures,
      documentTimestampedAt: timestamps
    )
  }

  /// The generation time of one verified document timestamp whose
  /// imprint matches the byte ranges it covers.
  private static func documentTimestamp(
    of signature: PdfSignatureReader.FoundSignature
  ) -> Date? {
    guard
      let verified = try? TimestampTokenVerifier.verify(signature.cms),
      let contents = try? RfcTimestamp.contents(in: signature.cms),
      let binding = try? RfcTimestamp.binding(in: contents.tstInfo),
      binding.digest == signature.byteRangeDigest
    else {
      return nil
    }
    return verified.generatedAt
  }

  private static func report(
    of signature: PdfSignatureReader.FoundSignature
  ) throws -> SignatureReport {
    let read: QualifiedDocumentCms.ReadSignature
    do {
      read = try QualifiedDocumentCms.read(signature.cms)
    } catch {
      throw Failure.unsupportedProfile
    }
    guard let signer = signerContext(of: read.signerCertificate) else {
      throw Failure.unsupportedProfile
    }

    let documentIntact = read.messageDigest == signature.byteRangeDigest
    let signatureValid =
      (try? QualifiedDocumentCms.validate(
        signedAttributesSet: read.signedAttributesSet,
        signatureValue: read.signatureValue,
        signerProfile: signer.profile,
        signerCertificate: read.signerCertificate
      )) != nil

    let timestamps = verifiedTimestamps(
      of: read.timestampTokens,
      signatureValue: read.signatureValue
    )
    let timestampedAt = timestamps.min()
    let issuer = chainIssuer(
      of: read.signerCertificate,
      at: timestampedAt ?? Date()
    )

    return SignatureReport(
      signerName: DistinguishedName.personalName(
        inName: signer.facts.subjectName)
        ?? DistinguishedName.commonName(inName: signer.facts.subjectName)
        ?? "",
      signerIdentifier: DistinguishedName.identifier(
        inName: signer.facts.subjectName) ?? "",
      signerCertificate: read.signerCertificate,
      issuerCertificate: issuer,
      documentIntact: documentIntact,
      signatureValid: signatureValid,
      chainVerified: issuer != nil,
      timestampedAt: timestampedAt,
      timestampsValid: !read.timestampTokens.isEmpty
        && timestamps.count == read.timestampTokens.count,
      coversWholeDocument: signature.coversWholeDocument
    )
  }

  /// The parsed facts and card key profile of one signer certificate.
  private static func signerContext(
    of certificate: Data
  ) -> (facts: CertificateFacts, profile: CardKeyProfile)? {
    guard
      let facts = CertificateFacts(der: certificate),
      let secCertificate = SecCertificateCreateWithData(
        nil,
        certificate as CFData
      ),
      let profile = CardKeyProfile.resolve(fromCertificate: secCertificate)
    else {
      return nil
    }
    return (facts, profile)
  }

  /// The issuer that provably issued the signer, or nil when
  /// no cached issuer matches or the chain step fails.
  private static func chainIssuer(
    of signer: Data,
    at referenceTime: Date
  ) -> Data? {
    guard
      let issuer = IssuerCertificate.der(matching: signer),
      CertificateIssuer.isDirectlyIssued(signer, by: issuer, at: referenceTime)
    else {
      return nil
    }
    return issuer
  }

  /// The generation times of the tokens that verify and imprint the
  /// signature value; a failing token contributes nothing.
  private static func verifiedTimestamps(
    of tokens: [Data],
    signatureValue: Data
  ) -> [Date] {
    let expected = try? QualifiedDocumentCms.signatureTimestampDigest(
      signatureValue: signatureValue)
    guard let expected else { return [] }
    return tokens.compactMap { token in
      guard
        let verified = try? TimestampTokenVerifier.verify(token),
        let contents = try? RfcTimestamp.contents(in: token),
        let binding = try? RfcTimestamp.binding(in: contents.tstInfo),
        binding.digest == expected
      else {
        return nil
      }
      return verified.generatedAt
    }
  }
}
