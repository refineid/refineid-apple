// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Attached content, SignerInfo cardinality, SignerFields, and SKI
/// SignerIdentifier checks on `CmsSignedData`.
extension CmsSignedDataTests {
  /// Reads the first DER element of `encoded` without wrapping a mutating
  /// `DerReader` call inside `#require`.
  private static func firstElement(in encoded: Data) throws -> DerReader.Element {
    var reader = DerReader(encoded)
    let element = reader.next()
    return try #require(element)
  }

  /// Minimal structurally valid X.509 certificate carrying `extensions`.
  private static func minimalCertificate(extensions: [Data]) -> Data {
    let publicKey = DerEncoder.sequence([
      DerEncoder.sequence([]),
      DerEncoder.tlv(
        DerValues.tagBitString,
        Data([DerValues.bitStringNoUnusedBits, UInt8(SignOids.cmsVersion)])
      ),
    ])
    let tbs = DerEncoder.sequence([
      DerEncoder.integer(SignOids.cmsVersion),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      publicKey,
      DerEncoder.tlv(
        DerValues.tagContext3Constructed,
        DerEncoder.sequence(extensions)
      ),
    ])
    return DerEncoder.sequence([tbs])
  }

  /// Empty `signerInfos` parses `CmsSignedData` while `soleSignerInfoElement`
  /// accepts only a single SEQUENCE signer.
  @Test
  internal func signerInfosCardinalityEnforcedBySoleSignerHelper() throws {
    let emptyEncoded = Self.contentInfo(Envelope(signerInfos: DerEncoder.setOf([])))
    let empty = try #require(CmsSignedData(in: emptyEncoded))
    #expect(empty.soleSignerInfoElement(in: emptyEncoded) == nil)

    let oneSigner = Self.signerInfo(SignerFixture())
    let soleEncoded = Self.contentInfo(
      Envelope(signerInfos: DerEncoder.setOf([oneSigner]))
    )
    let sole = try #require(CmsSignedData(in: soleEncoded))
    let element = try #require(sole.soleSignerInfoElement(in: soleEncoded))
    #expect(DerReader(soleEncoded).data(of: element) == oneSigner)

    let secondSigner = Self.signerInfo(
      SignerFixture(
        identifier: DerEncoder.tlv(
          DerValues.tagContext0Primitive,
          Data("other-key-id".utf8)
        )
      )
    )
    for rejectedSet in [
      DerEncoder.setOf([oneSigner, secondSigner]),
      DerEncoder.tlv(DerValues.tagSet, DerEncoder.null()),
      DerEncoder.tlv(DerValues.tagSet, oneSigner + Data([Self.trailingByte])),
    ] {
      let encoded = Self.contentInfo(Envelope(signerInfos: rejectedSet))
      let parsed = try #require(CmsSignedData(in: encoded))
      #expect(parsed.soleSignerInfoElement(in: encoded) == nil)
    }
  }

  /// `attachedOctetString` unwraps `[0] EXPLICIT OCTET STRING` and rejects
  /// detached, mismatched-OID, or trailing-byte shapes.
  @Test
  internal func attachedOctetStringValidatesContentTypeAndBounds() throws {
    let validEncapsulated = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.tstInfo),
      DerEncoder.tlv(
        DerValues.tagContext0Constructed,
        DerEncoder.octetString(Self.attachedPayload)
      ),
    ])
    let validEncoded = Self.contentInfo(Envelope(encapsulated: validEncapsulated))
    let valid = try #require(CmsSignedData(in: validEncoded))
    #expect(
      valid.attachedOctetString(contentType: SignOids.tstInfo, in: validEncoded)
        == Self.attachedPayload
    )
    #expect(
      valid.attachedOctetString(contentType: SignOids.data, in: validEncoded) == nil
    )

    for encapsulated in [
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.tstInfo)]),
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.tstInfo),
        DerEncoder.tlv(DerValues.tagContext0Constructed, DerEncoder.null()),
      ]),
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.tstInfo),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.octetString(Self.attachedPayload) + DerEncoder.null()
        ),
      ]),
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.tstInfo),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.octetString(Self.attachedPayload)
        ),
        DerEncoder.null(),
      ]),
    ] {
      let encoded = Self.contentInfo(Envelope(encapsulated: encapsulated))
      let parsed = try #require(CmsSignedData(in: encoded))
      #expect(
        parsed.attachedOctetString(contentType: SignOids.tstInfo, in: encoded) == nil
      )
    }
  }

  /// `signerFields` accepts 6-field and 7-field SignerInfos and rejects
  /// missing `[0] signedAttrs`, wrong `[1]` tags, or trailing bytes.
  @Test
  internal func signerFieldsParsesSignedAndOptionalUnsignedAttributes() throws {
    let sixField = Self.signerInfo(SignerFixture())
    let sixElement = try Self.firstElement(in: sixField)
    let parsedSix = try #require(
      CmsSignedData.signerFields(of: sixElement, in: sixField)
    )
    #expect(parsedSix.signatureValue == Self.signaturePayload)
    #expect(parsedSix.unsignedAttributes == nil)

    let unsigned = DerEncoder.tlv(
      DerValues.tagContext1Constructed,
      DerEncoder.sequence([])
    )
    let sevenField = Self.signerInfo(SignerFixture(unsignedAttributes: unsigned))
    let sevenElement = try Self.firstElement(in: sevenField)
    let parsedSeven = try #require(
      CmsSignedData.signerFields(of: sevenElement, in: sevenField)
    )
    #expect(parsedSeven.signatureValue == Self.signaturePayload)
    #expect(
      parsedSeven.unsignedAttributes.map { DerReader(sevenField).data(of: $0) }
        == unsigned
    )

    for rejected in [
      Self.signerInfo(SignerFixture(includeSignedAttributes: false)),
      Self.signerInfo(SignerFixture(unsignedAttributes: DerEncoder.sequence([]))),
      Self.signerInfo(
        SignerFixture(unsignedAttributes: unsigned, trailing: DerEncoder.null())
      ),
      Self.signerInfo(SignerFixture(trailing: Data([Self.trailingByte]))),
    ] {
      let element = try Self.firstElement(in: rejected)
      #expect(CmsSignedData.signerFields(of: element, in: rejected) == nil)
    }
  }

  /// Both CMS verifiers match `[0] SubjectKeyIdentifier` via `CertificateFacts`
  /// and reject absent, critical, or duplicate extensions.
  @Test
  internal func subjectKeyIdentifierSignerIdentifiersUseCertificateFacts() throws {
    let keyIdentifier = Data("cms-signer-key-id".utf8)
    let encodedIdentifier = DerEncoder.tlv(
      DerValues.tagContext0Primitive,
      keyIdentifier
    )
    let identifierElement = try Self.firstElement(in: encodedIdentifier)
    let signerIdentifier = CmsSignerVerification.SignerIdentifier
      .subjectKeyIdentifier(keyIdentifier)
    let validExtension = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.subjectKeyIdentifier),
      DerEncoder.octetString(DerEncoder.octetString(keyIdentifier)),
    ])
    let criticalExtension = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.subjectKeyIdentifier),
      DerEncoder.booleanTrue(),
      DerEncoder.octetString(DerEncoder.octetString(keyIdentifier)),
    ])

    let matching = Self.minimalCertificate(extensions: [validExtension])
    #expect(signerIdentifier.names(matching))
    #expect(
      TimestampCmsVerifier.identifier(
        identifierElement,
        in: encodedIdentifier,
        matches: matching
      )
    )

    for nonMatching in [
      Self.minimalCertificate(extensions: []),
      Self.minimalCertificate(extensions: [criticalExtension]),
      Self.minimalCertificate(extensions: [validExtension, validExtension]),
    ] {
      #expect(!signerIdentifier.names(nonMatching))
      #expect(
        !TimestampCmsVerifier.identifier(
          identifierElement,
          in: encodedIdentifier,
          matches: nonMatching
        )
      )
    }
  }
}
