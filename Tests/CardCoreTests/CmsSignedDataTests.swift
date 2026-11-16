// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Direct structural checks for CMS ContentInfo and SignedData unwrapping
/// (RFC 5652 sections 3, 5.1, 5.2, and 5.3).
@Suite
internal struct CmsSignedDataTests {
  /// Configurable ContentInfo + SignedData test fixture.
  internal struct Envelope {
    internal var contentType = SignOids.signedData
    internal var version = DerEncoder.integer(SignOids.cmsVersion)
    internal var digestAlgorithms = DerEncoder.setOf([])
    internal var encapsulated = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.data)
    ])
    internal var certificates: Data?
    internal var revocations: Data?
    internal var signerInfos: Data? = DerEncoder.setOf([])
    internal var trailingInSignedData = Data()
    internal var trailingInExplicit = Data()
    internal var trailingInContentInfo = Data()
    internal var trailingOuter = Data()
  }

  /// Configurable SignerInfo test fixture.
  internal struct SignerFixture {
    internal var identifier = DerEncoder.tlv(
      DerValues.tagContext0Primitive,
      Data("key-id".utf8)
    )
    internal var includeSignedAttributes = true
    internal var unsignedAttributes: Data?
    internal var trailing = Data()
  }

  /// Synthetic payload octets for attached EncapsulatedContentInfo checks.
  internal static let attachedPayload = Data("timestamp-info-payload".utf8)

  /// Synthetic signature octets for SignerInfo structural checks.
  internal static let signaturePayload = Data("cms-signature-value".utf8)

  /// Synthetic trailing byte used to verify `isAtEnd` checks.
  internal static let trailingByte: UInt8 = 0

  /// Builds a ContentInfo wrapping a SignedData from `envelope`.
  internal static func contentInfo(_ envelope: Envelope) -> Data {
    var fields = [
      envelope.version,
      envelope.digestAlgorithms,
      envelope.encapsulated,
    ]
    if let certificates = envelope.certificates {
      fields.append(DerEncoder.tlv(DerValues.tagContext0Constructed, certificates))
    }
    if let revocations = envelope.revocations {
      fields.append(DerEncoder.tlv(DerValues.tagContext1Constructed, revocations))
    }
    if let signerInfos = envelope.signerInfos {
      fields.append(signerInfos)
    }
    let signedData = DerEncoder.tlv(
      DerValues.tagSequence,
      fields.reduce(Data(), +) + envelope.trailingInSignedData
    )
    let explicit = DerEncoder.tlv(
      DerValues.tagContext0Constructed,
      signedData + envelope.trailingInExplicit
    )
    let outer = DerEncoder.tlv(
      DerValues.tagSequence,
      DerEncoder.objectIdentifier(envelope.contentType)
        + explicit
        + envelope.trailingInContentInfo
    )
    return outer + envelope.trailingOuter
  }

  /// Builds a SignerInfo SEQUENCE from `fixture`.
  internal static func signerInfo(_ fixture: SignerFixture) -> Data {
    var fields = [
      DerEncoder.integer(SignOids.signerInfoVersion),
      fixture.identifier,
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha256)]),
    ]
    if fixture.includeSignedAttributes {
      fields.append(
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.sequence([
            DerEncoder.objectIdentifier(SignOids.contentType),
            DerEncoder.setOf([DerEncoder.objectIdentifier(SignOids.data)]),
          ])
        )
      )
    }
    fields.append(
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
    )
    fields.append(DerEncoder.octetString(Self.signaturePayload))
    if let unsigned = fixture.unsignedAttributes {
      fields.append(unsigned)
    }
    return DerEncoder.tlv(
      DerValues.tagSequence,
      fields.reduce(Data(), +) + fixture.trailing
    )
  }

  /// Optional `[0] certificates` and `[1] crls` combinations all parse cleanly.
  @Test
  internal func optionalCertificatesAndRevocationsCombinationsParse() throws {
    let certBody = DerEncoder.sequence([DerEncoder.integer(SignOids.cmsVersion)])
    let crlBody = DerEncoder.sequence([DerEncoder.null()])

    let neither = try #require(CmsSignedData(in: Self.contentInfo(Envelope())))
    #expect(neither.certificates == nil)
    #expect(neither.revocationChoices == nil)

    let certsOnlyEncoded = Self.contentInfo(Envelope(certificates: certBody))
    let certsOnly = try #require(CmsSignedData(in: certsOnlyEncoded))
    #expect(
      certsOnly.certificates.map { DerReader(certsOnlyEncoded).contentData(of: $0) }
        == certBody
    )
    #expect(certsOnly.revocationChoices == nil)

    let crlsOnlyEncoded = Self.contentInfo(Envelope(revocations: crlBody))
    let crlsOnly = try #require(CmsSignedData(in: crlsOnlyEncoded))
    #expect(crlsOnly.certificates == nil)
    #expect(
      crlsOnly.revocationChoices.map { DerReader(crlsOnlyEncoded).contentData(of: $0) }
        == crlBody
    )

    let bothEncoded = Self.contentInfo(
      Envelope(certificates: certBody, revocations: crlBody)
    )
    let both = try #require(CmsSignedData(in: bothEncoded))
    #expect(both.certificates != nil)
    #expect(both.revocationChoices != nil)
  }

  /// Trailing bytes at any DER nesting level fail closed.
  @Test
  internal func trailingBytesAreRejectedAtEveryNestingLevel() {
    let extra = DerEncoder.null()
    let oneByte = Data([Self.trailingByte])

    for envelope in [
      Envelope(trailingOuter: oneByte),
      Envelope(trailingOuter: extra),
      Envelope(trailingInContentInfo: oneByte),
      Envelope(trailingInContentInfo: extra),
      Envelope(trailingInExplicit: oneByte),
      Envelope(trailingInExplicit: extra),
      Envelope(trailingInSignedData: oneByte),
      Envelope(trailingInSignedData: extra),
    ] {
      #expect(CmsSignedData(in: Self.contentInfo(envelope)) == nil)
    }
  }

  /// Wrong OIDs, wrong tags, out-of-order optional fields, and missing
  /// `signerInfos` all return nil.
  @Test
  internal func malformedContentInfoAndSignedDataShapesReturnNil() {
    let emptyInteger = DerEncoder.tlv(DerValues.tagInteger, Data())
    let reversedOptionals = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(
        DerValues.tagContext0Constructed,
        DerEncoder.sequence([
          DerEncoder.integer(SignOids.cmsVersion),
          DerEncoder.setOf([]),
          DerEncoder.sequence([]),
          DerEncoder.tlv(DerValues.tagContext1Constructed, Data()),
          DerEncoder.tlv(DerValues.tagContext0Constructed, Data()),
          DerEncoder.setOf([]),
        ])
      ),
    ])

    #expect(CmsSignedData(in: Data()) == nil)
    #expect(CmsSignedData(in: DerEncoder.null()) == nil)
    #expect(CmsSignedData(in: reversedOptionals) == nil)
    for envelope in [
      Envelope(contentType: SignOids.data),
      Envelope(version: emptyInteger),
      Envelope(digestAlgorithms: DerEncoder.null()),
      Envelope(encapsulated: DerEncoder.null()),
      Envelope(signerInfos: DerEncoder.sequence([])),
      Envelope(certificates: Data(), signerInfos: nil),
    ] {
      #expect(CmsSignedData(in: Self.contentInfo(envelope)) == nil)
    }
  }
}
