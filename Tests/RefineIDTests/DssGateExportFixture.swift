// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Synthetic document-signing helpers shared by `DssGateExportTests`.
  internal enum DssGateExportFixture {
    private static let containedFileName = "terms.txt"
    private static let containedFileText = "Terms agreed under the DSS gate."

    /// The PDF as `DocumentSigner.sign` finishes it after the card.
    internal static func signedPdf(_ authorities: DssGateAuthorities) async throws -> Data {
      let placeholder = try PdfIncrementalSigner.prepare(
        TimestampedPdfFixture.minimalPdf,
        revision: .signature(
          PdfIncrementalSigner.SignatureClaim(signedAt: Date(), reason: nil, location: nil)
        )
      )
      let attributes = QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: placeholder.digest(QualifiedDocumentCms.signingDigestAlgorithm),
        signerCertificate: authorities.holderCertificate
      )
      let signature = try Self.cardSignature(
        Data(SHA384.hash(data: attributes)),
        key: authorities.holderKey,
        algorithm: .rsaSignatureDigestPKCS1v15SHA384
      )
      return try await TimestampClient.forOneDocument {
        let token = try await TimestampClient.token(
          over: QualifiedDocumentCms.signatureTimestampDigest(signatureValue: signature)
        )
        let timestamped = try DocumentSigner.TimestampedSignature.verified(
          DocumentSigner.TimestampedSignatureInput(
            placeholder: placeholder,
            signedAttributes: attributes,
            signatureValue: signature,
            signerProfile: .rsa2048,
            signerCertificate: authorities.holderCertificate
          ),
          timestampTokens: [token]
        )
        return try await DocumentSigner.longTerm(
          timestamped,
          signerCertificate: authorities.holderCertificate,
          timestampTokens: [token],
          policy: .longTermOnly
        ).bytes
      }
    }

    /// The container as `AsicSigner.sign` finishes it after the card.
    internal static func signedContainer(
      _ authorities: DssGateAuthorities
    ) async throws -> Data {
      let objects = [
        AsicSigner.dataObject(
          Data(Self.containedFileText.utf8), named: Self.containedFileName
        )
      ]
      let plan = try #require(
        XadesSignature.plan(
          objects: objects,
          certificate: authorities.holderCertificate,
          profile: .rsa2048,
          signedAt: Date()
        ))
      let wire = try Self.cardSignature(
        plan.signedInfo,
        key: authorities.holderKey,
        algorithm: .rsaSignatureMessagePKCS1v15SHA384
      )
      let xmlSignature = try #require(CardKeyProfile.rsa2048.xmlSignature(fromWire: wire))
      return try await AsicSigner.evidenced(
        plan: plan,
        xmlSignature: xmlSignature,
        certificate: authorities.holderCertificate,
        objects: objects,
        completion: AsicSigner.Completion(sources: .live, policy: .longTermOnly)
      ).bytes
    }

    /// Runs `operation` with synthetic anchors and zero inter-document sleep
    /// against the in-memory gate responder.
    internal static func withSyntheticTimestampEnvironment<Value>(
      anchors: @escaping @Sendable (Date) -> [Data],
      operation: () async throws -> Value
    ) async rethrows -> Value {
      try await TimestampClient.$throttle.withValue(TimestampThrottle(spacing: .zero)) {
        try await TimestampClient.$anchorResolver.withValue(anchors) {
          try await operation()
        }
      }
    }

    /// What the card answers: one RSA PKCS #1 signature.
    private static func cardSignature(
      _ value: Data,
      key: SecKey,
      algorithm: SecKeyAlgorithm
    ) throws -> Data {
      try DebugTimestampAuthority.sign(value, key: key, algorithm: algorithm)
    }
  }

#endif
