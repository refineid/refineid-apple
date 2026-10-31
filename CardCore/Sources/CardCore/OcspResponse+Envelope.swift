// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OcspResponse {
  /// Opens OCSPResponse, requires success and unwraps BasicOCSPResponse.
  internal static func basicResponse(
    from response: Data,
    expected: ExpectedCertId,
    nonce: Data?
  ) throws -> BasicResponse {
    let outer = try Self.onlyElement(in: response, tag: DerValues.tagSequence)
    var reader = DerReader(response, within: outer)
    let status = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagEnumerated
    )
    guard status.content.count == 1, let statusValue = reader.integerValue(of: status) else {
      throw ValidationFailure.malformed
    }
    guard statusValue == 0 else {
      throw ValidationFailure.rejected(status: statusValue)
    }
    let wrappedResponse = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagContext0Constructed
    )
    guard reader.isAtEnd else { throw ValidationFailure.malformed }

    var wrapperReader = DerReader(response, within: wrappedResponse)
    let responseBytes = try Self.requiredElement(
      from: &wrapperReader,
      tag: DerValues.tagSequence
    )
    guard wrapperReader.isAtEnd else { throw ValidationFailure.malformed }
    var bytesReader = DerReader(response, within: responseBytes)
    let type = try Self.requiredElement(
      from: &bytesReader,
      tag: DerValues.tagObjectIdentifier
    )
    guard bytesReader.data(of: type) == DerEncoder.objectIdentifier(SignOids.ocspBasic) else {
      throw ValidationFailure.unsupportedResponseType
    }
    let body = try Self.requiredElement(
      from: &bytesReader,
      tag: DerValues.tagOctetString
    )
    guard bytesReader.isAtEnd else { throw ValidationFailure.malformed }
    return try Self.parseBasic(
      bytesReader.contentData(of: body),
      expected: expected,
      nonce: nonce
    )
  }

  /// Parses BasicOCSPResponse and retains the exact ResponseData bytes.
  internal static func parseBasic(
    _ encoded: Data,
    expected: ExpectedCertId,
    nonce: Data?
  ) throws -> BasicResponse {
    let outer = try Self.onlyElement(in: encoded, tag: DerValues.tagSequence)
    var reader = DerReader(encoded, within: outer)
    let data = try Self.requiredElement(from: &reader, tag: DerValues.tagSequence)
    let responseData = try Self.parseResponseData(
      encoded,
      element: data,
      expected: expected,
      nonce: nonce
    )
    let signatureAlgorithm = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagSequence
    )
    let signatureElement = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagBitString
    )
    let bitString = reader.contentData(of: signatureElement)
    guard
      let unusedBits = bitString.first,
      unusedBits == 0,
      bitString.count > 1
    else {
      throw ValidationFailure.signatureInvalid
    }

    var certificates: [Data] = []
    if let certificateWrapper = reader.next() {
      guard certificateWrapper.tag == DerValues.tagContext0Constructed else {
        throw ValidationFailure.malformed
      }
      certificates = try Self.certificates(in: encoded, wrapper: certificateWrapper)
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return BasicResponse(
      encoded: encoded,
      responseData: responseData,
      signatureAlgorithm: signatureAlgorithm,
      signature: Data(bitString.dropFirst()),
      certificates: certificates
    )
  }

  /// Parses optional BasicOCSPResponse certificates.
  internal static func certificates(
    in encoded: Data,
    wrapper: DerReader.Element
  ) throws -> [Data] {
    var wrapperReader = DerReader(encoded, within: wrapper)
    let sequence = try Self.requiredElement(
      from: &wrapperReader,
      tag: DerValues.tagSequence
    )
    guard wrapperReader.isAtEnd else { throw ValidationFailure.malformed }
    var reader = DerReader(encoded, within: sequence)
    var values: [Data] = []
    while let certificate = reader.next() {
      guard certificate.tag == DerValues.tagSequence else {
        throw ValidationFailure.malformed
      }
      values.append(reader.data(of: certificate))
    }
    guard reader.isAtEnd, !values.isEmpty else { throw ValidationFailure.malformed }
    return values
  }

  /// Requires exactly one top-level element of the expected type.
  internal static func onlyElement(
    in encoded: Data,
    tag: UInt8
  ) throws -> DerReader.Element {
    var reader = DerReader(encoded)
    let element = try Self.requiredElement(from: &reader, tag: tag)
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return element
  }

  /// Reads one required element, optionally constraining its tag.
  internal static func requiredElement(
    from reader: inout DerReader
  ) throws -> DerReader.Element {
    try Self.requiredElement(from: &reader, expectedTag: nil)
  }

  /// Reads one required element of the specified tag.
  internal static func requiredElement(
    from reader: inout DerReader,
    tag: UInt8
  ) throws -> DerReader.Element {
    try Self.requiredElement(from: &reader, expectedTag: tag)
  }

  /// Implements the shared required-element structural check.
  private static func requiredElement(
    from reader: inout DerReader,
    expectedTag: UInt8?
  ) throws -> DerReader.Element {
    guard
      let element = reader.next(),
      expectedTag == nil || element.tag == expectedTag
    else {
      throw ValidationFailure.malformed
    }
    return element
  }
}
