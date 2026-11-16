// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for DER wire values used by document signing.
///
/// Tags are ASN.1 universal or context-specific identifier octets
/// (X.690 §8.1.2); object identifiers are kept in dotted notation and
/// encoded arithmetically, so no encoded OID byte appears anywhere.
/// No raw hex literal may appear outside this directory
/// (`.swiftlint.yml` `unexplained_hex`).
public enum DerValues {
  /// The tag a DER-encoded certificate starts with, which is how a
  /// DER body is told from a PEM one.
  public static let sequenceTagByte: UInt8 = 0x30

  /// Universal tag: SEQUENCE, constructed.
  internal static let tagSequence: UInt8 = 0x30

  /// Universal tag: SET, constructed (X.690 §8.12).
  internal static let tagSet: UInt8 = 0x31

  /// Universal tag: INTEGER.
  internal static let tagInteger: UInt8 = 0x02

  /// Universal tag: BOOLEAN.
  internal static let tagBoolean: UInt8 = 0x01

  /// Universal tag: OCTET STRING.
  internal static let tagOctetString: UInt8 = 0x04

  /// Universal tag: OBJECT IDENTIFIER.
  internal static let tagObjectIdentifier: UInt8 = 0x06

  /// Universal tag: NULL, whose content is always empty.
  internal static let tagNull: UInt8 = 0x05

  /// Universal tag: UTCTime (RFC 5280 section 4.1.2.5.1).
  internal static let tagUtcTime: UInt8 = 0x17

  /// Universal tag: GeneralizedTime.
  internal static let tagGeneralizedTime: UInt8 = 0x18

  /// Universal tag: BIT STRING, whose first content octet counts the
  /// unused bits of the last byte.
  internal static let tagBitString: UInt8 = 0x03

  /// BIT STRING content prefix when every payload bit is used.
  internal static let bitStringNoUnusedBits: UInt8 = 0x00

  /// Octets occupied by a BIT STRING's unused-bits count.
  internal static let bitStringPrefixByteCount = 1

  /// Universal tag: ENUMERATED, used by OCSPResponseStatus.
  internal static let tagEnumerated: UInt8 = 0x0A

  /// Universal tag: UTF8String.
  internal static let tagUtf8String: UInt8 = 0x0C

  /// Universal tag: PrintableString, the older name encoding.
  internal static let tagPrintableString: UInt8 = 0x13

  /// Universal tag: IA5String, ASCII by definition.
  internal static let tagIa5String: UInt8 = 0x16

  /// BOOLEAN TRUE content octet: DER requires all bits set.
  internal static let booleanTrue: UInt8 = 0xFF

  /// BOOLEAN FALSE content octet.
  internal static let booleanFalse: UInt8 = 0x00

  /// ASCII `.`, the GeneralizedTime fractional-second separator (X.690 section 11.7.4).
  internal static let asciiPeriod: UInt8 = 0x2E

  /// ASCII `0`, the first decimal digit.
  internal static let asciiZero: UInt8 = 0x30

  /// ASCII `9`, the last decimal digit.
  internal static let asciiNine: UInt8 = 0x39

  /// ASCII `Z`, the UTC GeneralizedTime suffix.
  internal static let asciiZulu: UInt8 = 0x5A

  /// Context-specific constructed tag `[0]`.
  internal static let tagContext0Constructed: UInt8 = 0xA0

  /// Context-specific primitive tag `[0]`.
  internal static let tagContext0Primitive: UInt8 = 0x80

  /// Context-specific constructed tag `[1]`.
  internal static let tagContext1Constructed: UInt8 = 0xA1

  /// Context-specific primitive tag `[1]`.
  internal static let tagContext1Primitive: UInt8 = 0x81

  /// Context-specific constructed tag `[2]`.
  internal static let tagContext2Constructed: UInt8 = 0xA2

  /// Context-specific primitive tag `[2]`.
  internal static let tagContext2Primitive: UInt8 = 0x82

  /// Context-specific constructed tag `[3]`: a certificate's
  /// extensions (RFC 5280 §4.1).
  internal static let tagContext3Constructed: UInt8 = 0xA3

  /// Context-specific constructed tag `[4]`: a GeneralName's
  /// directoryName (RFC 5280 §4.2.1.6).
  internal static let tagContext4Constructed: UInt8 = 0xA4

  /// Context-specific primitive tag `[6]`: a GeneralName's
  /// uniformResourceIdentifier (RFC 5280 §4.2.1.6).
  internal static let tagContext6Primitive: UInt8 = 0x86

  /// Context-specific tag [7], primitive: a subjectAltName iPAddress.
  internal static let tagContext7Primitive: UInt8 = 0x87

  /// Explicit Certificate version value for v2.
  internal static let certificateVersionTwo: UInt8 = 1

  /// Explicit Certificate version value for v3.
  internal static let certificateVersionThree: UInt8 = 2

  /// keyCertSign in the first payload octet of an RFC 5280 KeyUsage.
  internal static let keyUsageCertificateSigningBit: UInt8 = 0x04

  /// cRLSign in the first payload octet of an RFC 5280 KeyUsage.
  internal static let keyUsageCrlSigningBit: UInt8 = 0x02

  /// Length byte: long-form marker bit (X.690 §8.1.3.5).
  internal static let longFormMask: UInt8 = 0x80

  /// The bits of a long-form length octet that count the octets to
  /// follow.
  internal static let longFormCountMask: UInt8 = 0x7F

  /// Length byte: number-of-length-bytes mask in the long form.
  internal static let lengthCountMask: UInt8 = 0x7F

  /// Longest length this reader accepts, in octets: four covers any
  /// document a signature is taken over.
  ///
  /// Deliberately wider than ``DerTlvRecord``'s two-octet cap: that
  /// parser reads card files bounded by the card's addressing, while
  /// this reader also parses certificates and revocation lists that
  /// legitimately exceed 64 KiB.
  internal static let maximumLengthOctets: Int = 4

  /// Largest length encodable in the short form.
  internal static let shortFormMaximum: Int = 127

  /// Sign bit of a content octet, deciding INTEGER zero-padding.
  internal static let signBitMask: UInt8 = 0x80

  /// Arcs an OID must have before the first two can share an octet.
  internal static let oidMinimumArcs: Int = 2

  /// OID arcs consumed by that shared first octet.
  internal static let oidSharedArcs: Int = 2

  /// OID first-arc multiplier: the first two arcs share one octet as
  /// `first * 40 + second` (X.690 §8.19.4).
  internal static let oidFirstArcMultiplier: UInt = 40

  /// Base-128 continuation bit of an OID arc octet.
  internal static let oidContinuationBit: UInt8 = 0x80

  /// Value bits per OID arc octet.
  internal static let oidArcBits: UInt = 7

  /// Mask selecting one OID arc septet.
  internal static let oidArcMask: UInt = 0x7F
}
