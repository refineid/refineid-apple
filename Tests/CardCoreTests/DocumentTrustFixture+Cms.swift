// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// The detached CMS SignedData the fixture signs.
  extension DocumentTrustFixture {
    /// The signature-timestamp unsigned attributes, or nil without
    /// timestamps.
    private func unsignedAttributes(
      signature: Data,
      _ contents: Contents
    ) throws -> Data? {
      let imprint = try QualifiedDocumentCms.signatureTimestampDigest(
        signatureValue: signature, digestAlgorithm: .sha384
      )
      let tokens = try contents.timestampTimes.map { time in
        try authority.token(imprint: imprint, generalizedTime: time)
      }
      guard !tokens.isEmpty else { return nil }
      let attribute = DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.signatureTimestampToken),
        DerEncoder.setOf(tokens),
      ])
      return DerEncoder.retagged(
        DerEncoder.setOf([attribute]), to: DerValues.tagContext1Constructed)
    }

    /// The signed attributes over `byteRangeDigest`, as `contents`
    /// asks.
    private func signedAttributes(byteRangeDigest: Data, _ contents: Contents) -> Data {
      func attribute(_ oid: String, _ value: Data) -> Data {
        DerEncoder.sequence([DerEncoder.objectIdentifier(oid), DerEncoder.setOf([value])])
      }
      var attributes = [
        contents.duplicatesContentTypeValue
          ? DerEncoder.sequence([
            DerEncoder.objectIdentifier(SignOids.contentType),
            DerEncoder.tlv(
              DerValues.tagSet,
              DerEncoder.objectIdentifier(SignOids.data)
                + DerEncoder.objectIdentifier(SignOids.data)),
          ])
          : attribute(SignOids.contentType, DerEncoder.objectIdentifier(SignOids.data)),
        attribute(SignOids.messageDigest, DerEncoder.octetString(byteRangeDigest)),
      ]
      if !contents.omitsSigningCertificate {
        let essCertId = DerEncoder.sequence([
          DerEncoder.octetString(
            DocumentDigestAlgorithm.sha256.hash(contents.boundCertificate ?? signer.certificate))
        ])
        attributes.append(
          attribute(
            SignOids.signingCertificateV2,
            DerEncoder.sequence([DerEncoder.sequence([essCertId])])))
      }
      if contents.carriesSigningTime {
        attributes.append(
          attribute(
            SignOids.signingTime,
            DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(Self.signingTime.utf8))))
      }
      return DerEncoder.setOf(attributes)
    }

    /// The SignerInfo signature algorithm and value over `attributes`.
    private func signature(over attributes: Data) throws -> (algorithm: Data, value: Data) {
      let algorithm: Data
      let secAlgorithm: SecKeyAlgorithm
      if kind == .rsaSha256 {
        algorithm = DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.sha256WithRsa), DerEncoder.null(),
        ])
        secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
      } else {
        algorithm = DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
        secAlgorithm = .ecdsaSignatureMessageX962SHA256
      }
      var error: Unmanaged<CFError>?
      let value = try #require(
        SecKeyCreateSignature(signer.privateKey, secAlgorithm, attributes as CFData, &error)
          as Data?)
      return (algorithm, value)
    }

    /// A detached SignedData over the placeholder's byte ranges.
    internal func cms(
      over placeholder: PdfSignaturePlaceholder,
      _ contents: Contents
    ) throws -> Data {
      let attributes = self.signedAttributes(
        byteRangeDigest: placeholder.digest(.sha256), contents)
      let signature = try self.signature(over: attributes)
      let digestIdentifier = QualifiedDocumentCmsTests.digestIdentifier(SignOids.sha256)
      var signerFields = [
        DerEncoder.integer(SignOids.signerInfoVersion),
        DerEncoder.sequence([
          CertificateRevocationListFixtures.name(
            CertificateRevocationListFixtures.issuerCommonName),
          DerEncoder.unsignedInteger(contents.identifierSerial ?? signerSerial),
        ]),
        digestIdentifier,
        DerEncoder.retagged(attributes, to: DerValues.tagContext0Constructed),
        signature.algorithm,
        DerEncoder.octetString(signature.value),
      ]
      if let unsigned = try self.unsignedAttributes(signature: signature.value, contents) {
        signerFields.append(unsigned)
      }
      var signedDataFields = [
        DerEncoder.integer(SignOids.cmsVersion),
        DerEncoder.setOf([digestIdentifier]),
        DerEncoder.sequence(
          [DerEncoder.objectIdentifier(SignOids.data)]
            + (contents.encapsulatesContent
              ? [
                DerEncoder.tlv(
                  DerValues.tagContext0Constructed, DerEncoder.octetString(Self.encapsulatedContent)
                )
              ] : [])),
        DerEncoder.retagged(
          DerEncoder.setOf([signer.certificate] + contents.cmsCertificates),
          to: DerValues.tagContext0Constructed
        ),
      ]
      if !contents.cmsRevocationLists.isEmpty {
        signedDataFields.append(
          DerEncoder.retagged(
            DerEncoder.setOf(contents.cmsRevocationLists),
            to: DerValues.tagContext1Constructed
          )
        )
      }
      signedDataFields.append(DerEncoder.setOf([DerEncoder.sequence(signerFields)]))
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.signedData),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed, DerEncoder.sequence(signedDataFields)),
      ])
    }
  }

#endif
