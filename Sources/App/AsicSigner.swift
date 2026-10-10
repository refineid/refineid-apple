// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import OSLog
import Security
import UniformTypeIdentifiers

/// Signs a set of files into one ASiC-E container at level XAdES-LT.
///
/// The order is forced by what each step attests, exactly as in
/// `DocumentSigner`: the XAdES `SignedInfo` is prepared and signed
/// first; its timestamp proves the signature existed; and the
/// validation material proves the chain was good at that instant.
/// The container is only assembled once all the evidence is in the
/// signature document, because a container is one write - there is
/// no incremental revision to extend later.
///
/// The output is the `.asice` format ETSI EN 319 162-1 defines and
/// Estonian DigiDoc (BDOC 2.1) exchanges.
internal enum AsicSigner {
  /// Why a container could not be produced, beyond the shared
  /// card/network/validation failures reported through
  /// `DocumentSigner.Failure`.
  internal enum Failure: Error {
    /// The finished entries could not be described by the container
    /// format's 32-bit fields.
    case container

    /// The card session signed octets that do not match the
    /// signature rebuilt from its certificate.
    case signedOctetsChanged

    /// A file cannot be carried under the name it has: the container
    /// reserves some names, and two files cannot share one.
    case unusableName
  }

  #if DEBUG
    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "asic-signer"
    )
  #endif

  /// Fallback media type for a file no type database knows.
  private static let unknownMediaType = "application/octet-stream"

  /// One file as it will appear inside a container, with the media
  /// type the signature will attest for it.
  internal static func dataObject(
    _ content: Data,
    named name: String
  ) -> AsicContainer.DataObject {
    AsicContainer.DataObject(
      name: name,
      mimeType: Self.mediaType(forFileNamed: name),
      content: content
    )
  }

  /// Signs `objects` into one container covered by one signature.
  ///
  /// One signature over the whole set, which is what a set signed
  /// together means: one PIN 2 use, one timestamp, and one piece of
  /// revocation evidence, attesting the files as one act rather than
  /// as several that happen to share a minute.
  internal static func sign(
    _ objects: [AsicContainer.DataObject],
    pin2: String?,
    transport: CardMaintenance.Transport,
    cardAccessNumber: String?
  ) async throws -> Data {
    // Asked before the card is touched. A set that cannot be carried
    // is refused while a refusal is still free; discovering it after
    // signing would have spent a PIN attempt on nothing.
    guard !objects.isEmpty, AsicContainer.areNamesUsable(objects) else {
      throw Failure.unusableName
    }
    if await MainActor.run(body: { DocumentSigner.usesRappSigning }) {
      return try await Self.signRemotely(objects)
    }
    guard let pin2 else {
      throw DocumentSigner.Failure.card(.invalidEntry)
    }
    let signedAt = Date()
    let answer = await CardMaintenance.qualifiedSignature(
      pin2: pin2,
      expectedCertificate: nil,
      transport: transport,
      cardAccessNumber: cardAccessNumber
    ) { certificate in
      Self.plannedSignedInfo(
        objects: objects, certificate: certificate, signedAt: signedAt
      )
    }
    switch answer {
    case .refused(let outcome):
      throw DocumentSigner.Failure.card(outcome)

    case .signerCertificateMismatch:
      throw DocumentSigner.Failure.stampSignerChanged

    case .signed(let product):
      return try await Self.assembled(
        from: product, objects: objects, signedAt: signedAt
      )
    }
  }

  /// Signs canonical XAdES bytes through the selected phone.
  ///
  /// PIN 2 is entered on the authorizer and never crosses the RAPP
  /// boundary.
  private static func signRemotely(
    _ objects: [AsicContainer.DataObject]
  ) async throws -> Data {
    let signedAt = Date()
    let documentName = objects.count == 1 ? objects[0].name : "ASiC-E container"
    #if DEBUG
      logger.notice(
        "[AsicSigner] signRemotely: signing \(objects.count, privacy: .public) objects"
      )
    #endif
    let product = try await DocumentSigner.remoteQualifiedSignature(
      documentName: documentName,
      expectedCertificate: nil
    ) { certificate in
      Self.plannedSignedInfo(
        objects: objects, certificate: certificate, signedAt: signedAt
      )
    }
    #if DEBUG
      logger.notice(
        "[AsicSigner] signRemotely: received remote signature product, assembling container"
      )
    #endif
    return try await Self.assembled(
      from: product, objects: objects, signedAt: signedAt
    )
  }

  /// Timestamps the signature, collects the evidence, and writes the
  /// container.
  private static func assembled(
    from product: CardMaintenance.QualifiedProduct,
    objects: [AsicContainer.DataObject],
    signedAt: Date
  ) async throws -> Data {
    // The plan is rebuilt from the certificate the card answered
    // with; the card must have signed exactly these octets. A
    // mismatch means the deterministic rebuild does not describe
    // what was signed, and nothing downstream may proceed on it.
    guard
      let plan = XadesSignature.plan(
        objects: objects,
        certificate: product.certificate,
        profile: product.profile,
        signedAt: signedAt
      ),
      product.content == plan.signedInfo,
      let xmlSignature = product.profile.xmlSignature(
        fromWire: product.signature
      )
    else {
      throw Failure.signedOctetsChanged
    }
    let token: TimestampTokenVerifier.VerifiedToken
    do {
      token = try await TimestampClient.token(
        over: XadesSignature.timestampDigest(xmlSignature)
      )
    } catch {
      throw DocumentSigner.Failure.network(error)
    }
    let evidence: PdfValidationStore.Material
    do {
      evidence = try await ValidationMaterialCollector.collect(
        signerCertificate: product.certificate,
        timestampTokens: [token]
      )
    } catch {
      throw DocumentSigner.Failure.validation(error)
    }
    let document = plan.document(
      xmlSignature: xmlSignature,
      timestampTokens: [token.token],
      material: evidence
    )
    guard
      let archive = AsicContainer.container(
        objects: objects, signatureXml: document
      )
    else {
      throw Failure.container
    }
    return archive
  }

  /// The canonical `SignedInfo` octets for the card to sign, built
  /// inside the card session where the certificate first exists.
  ///
  /// Empty on a certificate whose key no profile matches; the
  /// deterministic rebuild in `assembled` then refuses the mismatch
  /// before any output exists.
  private static func plannedSignedInfo(
    objects: [AsicContainer.DataObject],
    certificate: Data,
    signedAt: Date
  ) -> Data {
    guard
      let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
      let profile = CardKeyProfile.resolve(fromCertificate: parsed)
    else {
      #if DEBUG
        logger.notice(
          "[AsicSigner] plannedSignedInfo: failed to parse certificate or resolve profile"
        )
      #endif
      return Data()
    }
    guard
      let plan = XadesSignature.plan(
        objects: objects,
        certificate: certificate,
        profile: profile,
        signedAt: signedAt
      )
    else {
      #if DEBUG
        let count = objects.count
        logger.notice(
          "[AsicSigner] plannedSignedInfo: XadesSignature.plan returned nil for \(count, privacy: .public) items"
        )
      #endif
      return Data()
    }
    #if DEBUG
      let infoCount = plan.signedInfo.count
      logger.notice(
        "[AsicSigner] plannedSignedInfo: generated signedInfo (\(infoCount, privacy: .public) bytes)"
      )
    #endif
    return plan.signedInfo
  }

  /// The media type recorded and signed for a file name.
  internal static func mediaType(forFileNamed name: String) -> String {
    let fileExtension = URL(fileURLWithPath: name).pathExtension
    guard !fileExtension.isEmpty,
      let type = UTType(filenameExtension: fileExtension),
      let mimeType = type.preferredMIMEType
    else {
      return Self.unknownMediaType
    }
    return mimeType
  }
}
