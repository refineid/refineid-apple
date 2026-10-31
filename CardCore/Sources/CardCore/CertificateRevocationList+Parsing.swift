// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CertificateRevocationList {
  /// Version INTEGER value for the v2 CRL syntax.
  private static let versionTwo: UInt8 = 1

  /// Parses one complete CertificateList and searches for the target serial.
  internal static func parse(
    _ encoded: Data,
    targetSerial: Data
  ) throws -> ParsedList {
    let outer = try Self.onlyElement(in: encoded, tag: DerValues.tagSequence)
    var reader = DerReader(encoded, within: outer)
    let tbs = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagSequence
    )
    let outerAlgorithm = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagSequence
    )
    let signatureBits = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagBitString
    )
    guard reader.isAtEnd else { throw ValidationFailure.malformed }

    let signatureContent = reader.contentData(of: signatureBits)
    guard
      signatureContent.first == 0,
      signatureContent.count > 1
    else {
      throw ValidationFailure.signatureInvalid
    }
    let fields = try Self.parseTbs(
      encoded,
      element: tbs,
      targetSerial: targetSerial
    )
    let outerAlgorithmData = reader.data(of: outerAlgorithm)
    guard fields.signatureAlgorithm == outerAlgorithmData else {
      throw ValidationFailure.malformed
    }
    return ParsedList(
      signedData: reader.data(of: tbs),
      signatureAlgorithm: outerAlgorithmData,
      signature: signatureContent.dropFirst(),
      issuerName: fields.issuerName,
      thisUpdate: fields.thisUpdate,
      nextUpdate: fields.nextUpdate,
      targetRevocation: fields.targetRevocation
    )
  }

  /// Parses the signed TBSCertList fields and all revocation entries.
  private static func parseTbs(
    _ encoded: Data,
    element: DerReader.Element,
    targetSerial: Data
  ) throws -> TbsFields {
    var reader = DerReader(encoded, within: element)
    let header = try Self.parseTbsHeader(encoded, reader: &reader)

    guard let following = try Self.nextElement(from: &reader, in: encoded) else {
      return TbsFields(
        signatureAlgorithm: header.signatureAlgorithm,
        issuerName: header.issuerName,
        thisUpdate: header.thisUpdate,
        nextUpdate: nil,
        targetRevocation: nil
      )
    }
    guard Self.isTimeTag(following.tag) else {
      throw ValidationFailure.nextUpdateMissing
    }
    let nextUpdate = try Self.time(in: encoded, element: following)

    var targetRevocation: RevokedEntry?
    var trailing = try Self.nextElement(from: &reader, in: encoded)
    if let revoked = trailing, revoked.tag == DerValues.tagSequence {
      targetRevocation = try Self.parseRevokedCertificates(
        encoded,
        element: revoked,
        targetSerial: targetSerial,
        isVersionTwo: header.isVersionTwo
      )
      trailing = try Self.nextElement(from: &reader, in: encoded)
    }
    if let extensions = trailing {
      guard
        extensions.tag == DerValues.tagContext0Constructed,
        header.isVersionTwo
      else {
        throw ValidationFailure.malformed
      }
      try Self.parseCrlExtensions(encoded, wrapper: extensions)
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return TbsFields(
      signatureAlgorithm: header.signatureAlgorithm,
      issuerName: header.issuerName,
      thisUpdate: header.thisUpdate,
      nextUpdate: nextUpdate,
      targetRevocation: targetRevocation
    )
  }

  /// Parses the fixed TBSCertList prefix through thisUpdate.
  private static func parseTbsHeader(
    _ encoded: Data,
    reader: inout DerReader
  ) throws -> TbsHeader {
    var signature = try Self.requiredElement(from: &reader, in: encoded)
    var isVersionTwo = false
    if signature.tag == DerValues.tagInteger {
      guard reader.contentData(of: signature) == Data([Self.versionTwo]) else {
        throw ValidationFailure.malformed
      }
      isVersionTwo = true
      signature = try Self.requiredElement(
        from: &reader,
        in: encoded,
        tag: DerValues.tagSequence
      )
    }
    guard signature.tag == DerValues.tagSequence else {
      throw ValidationFailure.malformed
    }
    let issuer = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagSequence
    )
    let update = try Self.requiredElement(from: &reader, in: encoded)
    return TbsHeader(
      signatureAlgorithm: reader.data(of: signature),
      issuerName: reader.data(of: issuer),
      thisUpdate: try Self.time(in: encoded, element: update),
      isVersionTwo: isVersionTwo
    )
  }

  /// Parses all revoked entries and compares their integer values by magnitude.
  private static func parseRevokedCertificates(
    _ encoded: Data,
    element: DerReader.Element,
    targetSerial: Data,
    isVersionTwo: Bool
  ) throws -> RevokedEntry? {
    var reader = DerReader(encoded, within: element)
    var targetRevocation: RevokedEntry?
    while let entry = try Self.nextElement(from: &reader, in: encoded) {
      guard entry.tag == DerValues.tagSequence else {
        throw ValidationFailure.malformed
      }
      var entryReader = DerReader(encoded, within: entry)
      let serial = try Self.requiredElement(
        from: &entryReader,
        in: encoded,
        tag: DerValues.tagInteger
      )
      let serialMagnitude = try Self.unsignedIntegerContent(
        entryReader.contentData(of: serial)
      )
      let revocationDate = try Self.requiredElement(from: &entryReader, in: encoded)
      let revokedAt = try Self.time(in: encoded, element: revocationDate)
      var reason: RevocationReason?
      if let extensions = try Self.nextElement(from: &entryReader, in: encoded) {
        guard extensions.tag == DerValues.tagSequence, isVersionTwo else {
          throw ValidationFailure.malformed
        }
        reason = try Self.parseEntryExtensions(encoded, sequence: extensions)
      }
      guard entryReader.isAtEnd else { throw ValidationFailure.malformed }
      // removeFromCRL belongs only to delta CRLs (RFC 5280 section
      // 5.3.1); in a complete list such an entry revokes nothing.
      if serialMagnitude == targetSerial, targetRevocation == nil, reason != .removeFromCrl {
        targetRevocation = RevokedEntry(revokedAt: revokedAt, reason: reason)
      }
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return targetRevocation
  }

  /// Validates positive DER INTEGER content and removes sign padding.
  internal static func unsignedIntegerContent(_ content: Data) throws -> Data {
    guard let first = content.first else { throw ValidationFailure.malformed }
    if first == 0 {
      guard content.count > 1 else { return content }
      let next = content[content.index(after: content.startIndex)]
      guard next & DerValues.signBitMask != 0 else {
        throw ValidationFailure.malformed
      }
      return content.dropFirst()
    }
    guard first & DerValues.signBitMask == 0 else {
      throw ValidationFailure.malformed
    }
    return content
  }

  /// Requires exactly one canonical top-level element of the expected type.
  internal static func onlyElement(
    in encoded: Data,
    tag: UInt8
  ) throws -> DerReader.Element {
    var reader = DerReader(encoded)
    let element = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: tag
    )
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return element
  }

  /// Reads one optional element and verifies its minimal DER length encoding.
  internal static func nextElement(
    from reader: inout DerReader,
    in encoded: Data
  ) throws -> DerReader.Element? {
    guard let element = reader.next() else {
      guard reader.isAtEnd else { throw ValidationFailure.malformed }
      return nil
    }
    guard
      element.raw.upperBound <= encoded.count,
      reader.data(of: element)
        == DerEncoder.tlv(element.tag, reader.contentData(of: element))
    else {
      throw ValidationFailure.malformed
    }
    return element
  }

  /// Reads one required element, optionally constraining its tag.
  internal static func requiredElement(
    from reader: inout DerReader,
    in encoded: Data
  ) throws -> DerReader.Element {
    guard let element = try Self.nextElement(from: &reader, in: encoded) else {
      throw ValidationFailure.malformed
    }
    return element
  }

  /// Reads one required element with the expected identifier octet.
  internal static func requiredElement(
    from reader: inout DerReader,
    in encoded: Data,
    tag: UInt8
  ) throws -> DerReader.Element {
    let element = try Self.requiredElement(from: &reader, in: encoded)
    guard element.tag == tag else { throw ValidationFailure.malformed }
    return element
  }
}
