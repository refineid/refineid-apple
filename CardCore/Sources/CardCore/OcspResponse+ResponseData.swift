// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OcspResponse {
  /// The mandatory ResponseData fields preceding the single-response list.
  private struct ResponseDataHeader {
    /// The responder's signed production time.
    let producedAt: Date

    /// The responder identity named in the response.
    let responderId: ResponderId

    /// The SingleResponses sequence.
    let responses: DerReader.Element
  }

  /// Parses the signed ResponseData and finds the one requested certificate.
  internal static func parseResponseData(
    _ encoded: Data,
    element: DerReader.Element,
    expected: ExpectedCertId,
    nonce: Data?
  ) throws -> ResponseData {
    var reader = DerReader(encoded, within: element)
    let header = try Self.responseDataHeader(in: encoded, reader: &reader)
    let matched = try Self.matchingSingleResponse(
      in: encoded,
      responses: header.responses,
      expected: expected
    )
    try Self.checkTrailingResponseData(
      in: encoded,
      reader: &reader,
      expectedNonce: nonce
    )
    return ResponseData(
      nextUpdate: matched.nextUpdate,
      producedAt: header.producedAt,
      raw: reader.data(of: element),
      responderId: header.responderId,
      status: matched.status,
      thisUpdate: matched.thisUpdate
    )
  }

  /// Parses the mandatory ResponseData prefix through the responses sequence.
  private static func responseDataHeader(
    in encoded: Data,
    reader: inout DerReader
  ) throws -> ResponseDataHeader {
    var next = try Self.requiredElement(from: &reader)
    if next.tag == DerValues.tagContext0Constructed {
      try Self.checkVersion(in: encoded, wrapper: next)
      next = try Self.requiredElement(from: &reader)
    }
    let responderId = try Self.responderId(in: encoded, element: next)
    let producedAt = try Self.generalizedTime(
      in: encoded,
      element: try Self.requiredElement(
        from: &reader,
        tag: DerValues.tagGeneralizedTime
      )
    )
    let responses = try Self.requiredElement(from: &reader, tag: DerValues.tagSequence)
    return ResponseDataHeader(
      producedAt: producedAt,
      responderId: responderId,
      responses: responses
    )
  }

  /// Finds exactly one status answer for the requested certificate.
  private static func matchingSingleResponse(
    in encoded: Data,
    responses: DerReader.Element,
    expected: ExpectedCertId
  ) throws -> ParsedSingleResponse {
    var reader = DerReader(encoded, within: responses)
    var matched: ParsedSingleResponse?
    while let single = reader.next() {
      let candidate = try Self.singleResponse(
        in: encoded,
        element: single,
        expected: expected
      )
      guard !candidate.matches || matched == nil else {
        throw ValidationFailure.malformed
      }
      if candidate.matches {
        matched = candidate
      }
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    guard let matched else { throw ValidationFailure.certificateMismatch }
    return matched
  }

  /// Checks the optional response extension run is structurally complete.
  private static func checkTrailingResponseData(
    in encoded: Data,
    reader: inout DerReader,
    expectedNonce: Data?
  ) throws {
    if let extensions = reader.next() {
      guard extensions.tag == DerValues.tagContext1Constructed else {
        throw ValidationFailure.malformed
      }
      try Self.checkResponseExtensions(
        in: encoded,
        wrapper: extensions,
        expectedNonce: expectedNonce
      )
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
  }

  /// Parses one response while preserving the target-match distinction.
  internal static func singleResponse(
    in encoded: Data,
    element: DerReader.Element,
    expected: ExpectedCertId
  ) throws -> ParsedSingleResponse {
    guard element.tag == DerValues.tagSequence else {
      throw ValidationFailure.malformed
    }
    var reader = DerReader(encoded, within: element)
    let certId = try Self.requiredElement(from: &reader, tag: DerValues.tagSequence)
    let status = try Self.certificateStatus(
      try Self.requiredElement(from: &reader),
      in: encoded
    )
    let thisUpdate = try Self.generalizedTime(
      in: encoded,
      element: try Self.requiredElement(
        from: &reader,
        tag: DerValues.tagGeneralizedTime
      )
    )
    let nextUpdate = try Self.optionalSingleResponseFields(
      in: encoded,
      reader: &reader
    )
    return ParsedSingleResponse(
      matches: try Self.matches(expected, certId: certId, in: encoded),
      nextUpdate: nextUpdate,
      status: status,
      thisUpdate: thisUpdate
    )
  }

  /// Parses `nextUpdate` and single-response extensions when present.
  private static func optionalSingleResponseFields(
    in encoded: Data,
    reader: inout DerReader
  ) throws -> Date? {
    guard let optional = reader.next() else { return nil }
    switch optional.tag {
    case DerValues.tagContext0Constructed:
      let nextUpdate = try Self.explicitGeneralizedTime(
        in: encoded,
        wrapper: optional
      )
      if let extensions = reader.next() {
        guard extensions.tag == DerValues.tagContext1Constructed else {
          throw ValidationFailure.malformed
        }
        try Self.rejectUnknownCriticalExtensions(
          try Self.extensions(in: encoded, wrapper: extensions)
        )
      }
      guard reader.isAtEnd else { throw ValidationFailure.malformed }
      return nextUpdate

    case DerValues.tagContext1Constructed:
      try Self.rejectUnknownCriticalExtensions(
        try Self.extensions(in: encoded, wrapper: optional)
      )
      guard reader.isAtEnd else { throw ValidationFailure.malformed }
      return nil

    default:
      throw ValidationFailure.malformed
    }
  }

  /// Ensures a certificate status has the expected choice encoding.
  internal static func certificateStatus(
    _ element: DerReader.Element,
    in encoded: Data
  ) throws -> CertificateStatus {
    switch element.tag {
    case DerValues.tagContext0Primitive:
      guard element.content.isEmpty else { throw ValidationFailure.malformed }
      return .good

    case DerValues.tagContext1Constructed:
      var reader = DerReader(encoded, within: element)
      let revocationTime = try Self.requiredElement(
        from: &reader,
        tag: DerValues.tagGeneralizedTime
      )
      let revokedAt = try Self.generalizedTime(in: encoded, element: revocationTime)
      let reason = try Self.optionalRevocationReason(in: encoded, reader: &reader)
      guard reader.isAtEnd else { throw ValidationFailure.malformed }
      return .revoked(revokedAt: revokedAt, reason: reason)

    case DerValues.tagContext2Primitive:
      guard element.content.isEmpty else { throw ValidationFailure.malformed }
      return .unknown

    default:
      throw ValidationFailure.malformed
    }
  }

  /// Parses the optional RFC 5280 revocation reason wrapper.
  private static func optionalRevocationReason(
    in encoded: Data,
    reader: inout DerReader
  ) throws -> RevocationReason? {
    guard let reason = reader.next() else { return nil }
    guard reason.tag == DerValues.tagContext0Constructed else {
      throw ValidationFailure.malformed
    }
    var reasonReader = DerReader(encoded, within: reason)
    let enumerated = try Self.requiredElement(
      from: &reasonReader,
      tag: DerValues.tagEnumerated
    )
    guard enumerated.content.count == 1, reasonReader.isAtEnd else {
      throw ValidationFailure.malformed
    }
    return reasonReader.integerValue(of: enumerated)
      .map(RevocationReason.init(code:)) ?? .unrecognized
  }

  /// Checks CertID against every hash and serial component we requested.
  internal static func matches(
    _ expected: ExpectedCertId,
    certId: DerReader.Element,
    in encoded: Data
  ) throws -> Bool {
    var reader = DerReader(encoded, within: certId)
    let algorithm = try Self.requiredElement(from: &reader, tag: DerValues.tagSequence)
    guard
      let hashAlgorithm = try Self.certIdHashAlgorithm(in: encoded, element: algorithm),
      let hashes = expected.hashes(underAlgorithm: hashAlgorithm)
    else {
      return false
    }
    let nameHash = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagOctetString
    )
    let keyHash = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagOctetString
    )
    let serial = try Self.requiredElement(from: &reader, tag: DerValues.tagInteger)
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    guard
      let answered = Self.magnitude(reader.contentData(of: serial)),
      let requested = Self.magnitude(expected.serialNumber)
    else {
      return false
    }
    return reader.contentData(of: nameHash) == hashes.name
      && reader.contentData(of: keyHash) == hashes.key
      && answered == requested
  }

  /// A serial INTEGER's value without its sign-padding octets, so two
  /// encodings of one serial compare equal.
  private static func magnitude(_ content: Data) -> Data? {
    try? CertificateRevocationList.unsignedIntegerContent(content)
  }

  /// Checks the default or explicit OCSP version is v1.
  internal static func checkVersion(
    in encoded: Data,
    wrapper: DerReader.Element
  ) throws {
    var reader = DerReader(encoded, within: wrapper)
    let version = try Self.requiredElement(from: &reader, tag: DerValues.tagInteger)
    guard
      reader.isAtEnd,
      reader.contentData(of: version) == Data([0])
    else {
      throw ValidationFailure.malformed
    }
  }

  /// Parses the exact ResponderID form that identifies the signer certificate.
  internal static func responderId(
    in encoded: Data,
    element: DerReader.Element
  ) throws -> ResponderId {
    switch element.tag {
    case DerValues.tagContext1Constructed:
      var reader = DerReader(encoded, within: element)
      let name = try Self.requiredElement(from: &reader, tag: DerValues.tagSequence)
      guard reader.isAtEnd else { throw ValidationFailure.malformed }
      return .name(reader.data(of: name))

    case DerValues.tagContext2Primitive:
      let hash = DerReader(encoded).contentData(of: element)
      guard hash.count == Self.sha1DigestByteCount else {
        throw ValidationFailure.malformed
      }
      return .keyHash(hash)

    default:
      throw ValidationFailure.malformed
    }
  }

  /// The encoded OBJECT IDENTIFIER of a CertID hashAlgorithm whose
  /// parameters are absent or NULL, nil for any other shape.
  internal static func certIdHashAlgorithm(
    in encoded: Data,
    element: DerReader.Element
  ) throws -> Data? {
    var reader = DerReader(encoded, within: element)
    let oid = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagObjectIdentifier
    )
    if let parameters = reader.next() {
      guard
        parameters.tag == DerValues.tagNull,
        parameters.content.isEmpty,
        reader.isAtEnd
      else {
        return nil
      }
    }
    return reader.isAtEnd ? reader.data(of: oid) : nil
  }
}
