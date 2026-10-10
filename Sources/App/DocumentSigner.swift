// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Dispatch
import Foundation
import Security

/// Signs one PDF at the archival level (PAdES-B-LTA).
///
/// The order is forced by what each step attests. The signature is
/// prepared and taken first; its timestamp proves the signature
/// existed; the validation material proves the chain was good; and
/// the archive timestamp, taken last over everything, proves all of
/// it existed before the algorithms or certificates age. Nothing
/// below that level is offered: a signature that cannot outlive its
/// certificates is not what this is for.
internal enum DocumentSigner {
  // MARK: Nested Types

  /// Why a document could not be signed.
  internal enum Failure: Error {
    /// The card refused, or its qualified slot is unusable.
    case card(CardMaintenance.Outcome)

    /// The document could not be prepared.
    case document(PdfSigningError)

    /// A network step an archival signature cannot omit failed.
    case network(Error)

    /// The paired phone's answer could not be used.
    case remote(RemoteFailure)

    /// A different card was present after the visible stamp was read.
    case stampSignerChanged

    /// Complete, authenticated LT evidence could not be collected.
    case validation(Error)
  }

  /// Why a paired phone's answer could not become a signature.
  internal enum RemoteFailure: Equatable, Sendable {
    /// The answer was not a signature.
    case noSignature

    /// The certificate names no key this app signs with.
    case unusableCertificate

    /// The returned signature does not verify against the certificate.
    case unverifiedSignature
  }

  /// A visible mark bound to the certificate identity it states.
  internal struct VisibleStamp: Sendable {
    /// What is drawn into the signed revision.
    internal let mark: StampMark

    /// The exact DER certificate whose subject is drawn in the mark.
    internal let signerCertificate: Data
  }

  /// How one signing operation reaches the card and authorizes it.
  internal struct SigningAccess {
    /// The authorizing PIN2, when the surface collected one.
    internal let pin2: String?

    /// The route the card session takes.
    internal let transport: CardMaintenance.Transport

    /// The card access number, when the route needs one.
    internal let cardAccessNumber: String?
  }

  /// What one card session produced.
  internal struct CardMaterial {
    /// The prepared document and its reserved hole.
    internal let placeholder: PdfSignaturePlaceholder

    /// The exact attribute bytes the card signed.
    internal let signedAttributes: Data

    /// The locally verified signature value over them.
    internal let signature: Data

    /// The qualified certificate, for the CMS and the chain walk.
    internal let certificate: Data

    /// The certificate-bound card profile written to CMS.
    internal let profile: CardKeyProfile
  }

  // MARK: Static Computed Properties

  // MARK: Static Functions

  /// Signs `document`, answering the finished bytes.
  internal static func sign(
    _ document: Data,
    named name: String,
    reason: String?,
    location: String?,
    access: SigningAccess
  ) async throws -> Product {
    try await Self.sign(
      document,
      named: name,
      claim: PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(), reason: reason, location: location
      ),
      stamp: nil,
      access: access
    )
  }

  /// The same operation with one instant shared by the QR and PDF.
  ///
  /// A stamp's page is written in the signature's own revision, so it
  /// is inside what the signature covers. Adding it afterwards would
  /// leave a document that validators report as changed after
  /// signing.
  internal static func sign(
    _ document: Data,
    named name: String,
    claim: PdfIncrementalSigner.SignatureClaim,
    stamp: VisibleStamp?,
    access: SigningAccess
  ) async throws -> Product {
    let material = try await Self.cardMaterial(
      document: document,
      named: name,
      claim: claim,
      stamp: stamp,
      access: access
    )
    let verifiedTokens = try await Self.timestamped(material.signature)
    let timestamped = try TimestampedSignature.verified(
      TimestampedSignatureInput(
        placeholder: material.placeholder,
        signedAttributes: material.signedAttributes,
        signatureValue: material.signature,
        signerProfile: material.profile,
        signerCertificate: material.certificate
      ),
      timestampTokens: verifiedTokens
    )
    let evidence: PdfValidationStore.Material
    do {
      evidence = try await ValidationMaterialCollector.collect(
        signerCertificate: material.certificate,
        timestampTokens: verifiedTokens
      )
    } catch {
      #if DEBUG && os(macOS)
        if let product = DebugRevokedDocumentSigning.product(
          timestamped: timestamped,
          after: error,
          enabled: DebugRevokedDocumentSigning.isEnabled()
        ) {
          return product
        }
      #endif
      throw Failure.validation(error)
    }
    let withEvidence = try PdfValidationStore.appended(
      to: timestamped.bytes, material: evidence
    )
    return Product(
      bytes: try await Self.archiveTimestamped(withEvidence),
      completion: .archival
    )
  }

  /// A detached raw signature over the stamp's compact claim.
  ///
  /// This card operation comes first because its bytes are drawn into
  /// the revision the document signature covers. The leaf certificate
  /// stays in the PDF CMS; a twelve-hex key ID selects it without
  /// making the QR several kilobytes larger.
  internal static func attestation(
    over claim: StampAttestation.Claim,
    pin2: String,
    expectedCertificate: Data
  ) async throws -> Data {
    let answer = await CardMaintenance.qualifiedSignature(
      pin2: pin2,
      expectedCertificate: expectedCertificate,
      transport: .reader,
      cardAccessNumber: nil
    ) { _ in
      claim.bytes
    }
    switch answer {
    case .signerCertificateMismatch:
      throw Failure.stampSignerChanged

    case .refused(let outcome):
      throw Failure.card(outcome)

    case .signed(let product):
      return StampAttestation.payload(
        claim: claim,
        signerCertificate: product.certificate,
        signature: product.signature
      )
    }
  }

  /// Reads the qualified certificate, verifies PIN2 and signs, in
  /// one exclusive card session.
  private static func cardMaterial(
    document: Data,
    named name: String,
    claim: PdfIncrementalSigner.SignatureClaim,
    stamp: VisibleStamp?,
    access: SigningAccess
  ) async throws -> CardMaterial {
    let prepared: PdfSignaturePlaceholder
    let stampMark = stamp?.mark ?? PdfStampRenderer.stampMark()
    do {
      prepared = try PdfIncrementalSigner.prepare(
        document, revision: .signature(claim), appending: stampMark
      )
    } catch let error as PdfSigningError {
      throw Failure.document(error)
    }
    let digest = prepared.digest
    if await MainActor.run(body: { Self.usesRappSigning }) {
      return try await Self.remoteCardMaterial(
        prepared: prepared,
        documentName: name,
        byteRangeDigest: digest,
        expectedCertificate: stamp?.signerCertificate
      )
    }
    guard let pin2 = access.pin2 else {
      throw Failure.card(.invalidEntry)
    }
    let answer = await CardMaintenance.qualifiedSignature(
      pin2: pin2,
      expectedCertificate: stamp?.signerCertificate,
      transport: access.transport,
      cardAccessNumber: access.cardAccessNumber
    ) { certificate in
      QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: digest, signerCertificate: certificate
      )
    }
    switch answer {
    case .signerCertificateMismatch:
      throw Failure.stampSignerChanged

    case .signed(let product):
      return CardMaterial(
        placeholder: prepared,
        signedAttributes: product.content,
        signature: product.signature,
        certificate: product.certificate,
        profile: product.profile
      )

    case .refused(let outcome):
      throw Failure.card(outcome)
    }
  }

  /// One signature timestamp; an archival signature cannot skip it.
  private static func timestamped(
    _ signatureValue: Data
  ) async throws -> [TimestampTokenVerifier.VerifiedToken] {
    let imprint = try QualifiedDocumentCms.signatureTimestampDigest(
      signatureValue: signatureValue
    )
    do {
      return [
        try await TimestampClient.token(over: imprint)
      ]
    } catch {
      throw Failure.network(error)
    }
  }

  /// The archive timestamp over the finished file.
  private static func archiveTimestamped(_ document: Data) async throws -> Data {
    let prepared: PdfSignaturePlaceholder
    do {
      prepared = try PdfIncrementalSigner.prepare(
        document, revision: .documentTimestamp
      )
    } catch let error as PdfSigningError {
      throw Failure.document(error)
    }
    do {
      let token = try await TimestampClient.token(over: prepared.digest)
      return try prepared.filled(with: token.token)
    } catch let error as PdfSigningError {
      throw Failure.document(error)
    } catch {
      throw Failure.network(error)
    }
  }
}
