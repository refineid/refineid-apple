// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation

  @testable import CardCore

  /// RFC 3161 CMS construction for the generated test authority.
  extension DebugTimestampAuthority {
    /// The signed TSTInfo bound to the card signature value.
    private static func tstInfo(imprint: Data, nonce: Data) -> Data {
      DerEncoder.sequence([
        DerEncoder.integer(SignOids.tstInfoVersion),
        DerEncoder.objectIdentifier(Self.testPolicyOid),
        DerEncoder.sequence([
          DerEncoder.sequence([
            DerEncoder.objectIdentifier(SignOids.sha384)
          ]),
          DerEncoder.octetString(imprint),
        ]),
        DerEncoder.integer(Self.timestampSerial),
        DerEncoder.tlv(
          DerValues.tagGeneralizedTime,
          Data(Self.generationTime.utf8)
        ),
        DerEncoder.unsignedInteger(nonce),
      ])
    }

    /// CMS attributes signed by the timestamp authority.
    private static func signedAttributes(
      tstInfo: Data,
      certificate: Data
    ) -> Data {
      let certificateIdentifier = DerEncoder.sequence([
        DerEncoder.octetString(Data(SHA256.hash(data: certificate)))
      ])
      return DerEncoder.setOf([
        Self.attribute(
          SignOids.contentType,
          value: DerEncoder.objectIdentifier(SignOids.tstInfo)
        ),
        Self.attribute(
          SignOids.messageDigest,
          value: DerEncoder.octetString(Data(SHA256.hash(data: tstInfo)))
        ),
        Self.attribute(
          SignOids.signingCertificateV2,
          value: DerEncoder.sequence([
            DerEncoder.sequence([certificateIdentifier])
          ])
        ),
      ])
    }

    /// Complete RFC 3161 CMS ContentInfo.
    private static func token(
      tstInfo: Data,
      attributes: Data,
      signature: Data,
      certificate: Data,
      issuerName: Data
    ) -> Data {
      let signer = DerEncoder.sequence([
        DerEncoder.integer(SignOids.signerInfoVersion),
        DerEncoder.sequence([
          issuerName,
          DerEncoder.integer(Self.certificateSerial),
        ]),
        Self.sha256Algorithm,
        DerEncoder.retagged(
          attributes,
          to: DerValues.tagContext0Constructed
        ),
        Self.ecdsaSha256Algorithm,
        DerEncoder.octetString(signature),
      ])
      let signedData = DerEncoder.sequence([
        DerEncoder.integer(Self.signedDataVersion),
        DerEncoder.setOf([Self.sha256Algorithm]),
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.tstInfo),
          DerEncoder.tlv(
            DerValues.tagContext0Constructed,
            DerEncoder.octetString(tstInfo)
          ),
        ]),
        DerEncoder.retagged(
          DerEncoder.setOf([certificate]),
          to: DerValues.tagContext0Constructed
        ),
        DerEncoder.setOf([signer]),
      ])
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.signedData),
        DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
      ])
    }

    /// One CMS attribute with exactly one value.
    private static func attribute(_ oid: String, value: Data) -> Data {
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(oid),
        DerEncoder.setOf([value]),
      ])
    }

    /// Builds an RFC 3161 token and its TimeStampResp wrapper.
    internal func response(
      imprint: Data,
      nonce: Data
    ) throws -> (token: Data, response: Data) {
      let information = Self.tstInfo(imprint: imprint, nonce: nonce)
      let attributes = Self.signedAttributes(
        tstInfo: information,
        certificate: certificate
      )
      let signature = try Self.sign(
        attributes,
        key: key,
        algorithm: .ecdsaSignatureMessageX962SHA256
      )
      let token = Self.token(
        tstInfo: information,
        attributes: attributes,
        signature: signature,
        certificate: certificate,
        issuerName: name
      )
      return (
        token,
        DerEncoder.sequence([
          DerEncoder.sequence([DerEncoder.integer(Self.grantedStatus)]),
          token,
        ])
      )
    }
  }

#endif
