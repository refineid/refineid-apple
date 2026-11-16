// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RfcTimestamp {
  /// A parsed message imprint and the following binding fields.
  internal struct Binding {
    /// The complete AlgorithmIdentifier.
    internal let algorithm: Data

    /// The imprint OCTET STRING content.
    internal let digest: Data

    /// The generation time.
    internal let generatedAt: Date

    /// The complete nonce INTEGER, when present.
    internal let nonce: Data?
  }

  /// Required fields that precede TSTInfo's optional run.
  private struct RequiredFields {
    let generatedAt: Date
    let imprint: DerReader.Element
  }

  /// Progress through TSTInfo's ordered optional fields.
  private enum OptionalStage {
    case accuracy
    case extensions
    case nonce
    case ordering
    case start
    case tsa
  }

  /// The granted TimeStampToken element from a complete TimeStampResp.
  internal static func encodedToken(inResponse response: Data) throws -> Data {
    var outer = DerReader(response)
    guard
      let envelope = outer.next(),
      envelope.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      throw TokenFailure.malformed
    }
    var reader = DerReader(response, within: envelope)
    guard
      let statusInfo = reader.next(),
      statusInfo.tag == DerValues.tagSequence
    else {
      throw TokenFailure.malformed
    }
    var statusReader = DerReader(response, within: statusInfo)
    guard
      let status = statusReader.next(),
      status.tag == DerValues.tagInteger,
      let statusValue = statusReader.integerValue(of: status)
    else {
      throw TokenFailure.malformed
    }
    guard SignOids.grantedStatuses.contains(statusValue) else {
      throw TokenFailure.rejected(status: statusValue)
    }
    guard
      let tokenElement = reader.next(),
      tokenElement.tag == DerValues.tagSequence,
      reader.isAtEnd
    else {
      throw TokenFailure.malformed
    }
    return reader.data(of: tokenElement)
  }

  /// The binding fields out of a TSTInfo.
  internal static func binding(in tstInfo: Data) throws -> Binding {
    var outer = DerReader(tstInfo)
    guard
      let sequence = outer.next(),
      sequence.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      throw TokenFailure.malformed
    }
    var reader = DerReader(tstInfo, within: sequence)
    let required = try Self.requiredFields(reader: &reader)
    var imprint = DerReader(tstInfo, within: required.imprint)
    guard
      let algorithm = imprint.next(),
      algorithm.tag == DerValues.tagSequence,
      let hashed = imprint.next(),
      hashed.tag == DerValues.tagOctetString,
      imprint.isAtEnd
    else {
      throw TokenFailure.malformed
    }
    return Binding(
      algorithm: imprint.data(of: algorithm),
      digest: imprint.contentData(of: hashed),
      generatedAt: required.generatedAt,
      nonce: try Self.nonce(reader: &reader)
    )
  }

  /// The fixed TSTInfo prefix through genTime.
  private static func requiredFields(
    reader: inout DerReader
  ) throws -> RequiredFields {
    guard
      let version = reader.next(),
      version.tag == DerValues.tagInteger,
      reader.integerValue(of: version) == SignOids.tstInfoVersion,
      let policy = reader.next(),
      policy.tag == DerValues.tagObjectIdentifier,
      let imprint = reader.next(),
      imprint.tag == DerValues.tagSequence,
      let serial = reader.next(),
      serial.tag == DerValues.tagInteger,
      let time = reader.next(),
      let generatedAt = DerTime.rfc3161GeneralizedTime(in: reader, element: time)
    else {
      throw TokenFailure.malformed
    }
    return RequiredFields(generatedAt: generatedAt, imprint: imprint)
  }

  /// The nonce in TSTInfo's ordered optional-field run.
  private static func nonce(reader: inout DerReader) throws -> Data? {
    var found: Data?
    var stage = OptionalStage.start
    while let candidate = reader.next() {
      switch candidate.tag {
      case DerValues.tagSequence where stage == .start:
        stage = .accuracy

      case DerValues.tagBoolean where stage == .start || stage == .accuracy:
        stage = .ordering

      case DerValues.tagInteger
      where stage == .start || stage == .accuracy || stage == .ordering:
        found = reader.data(of: candidate)
        stage = .nonce

      case DerValues.tagContext0Constructed
      where stage != .tsa && stage != .extensions:
        stage = .tsa

      case DerValues.tagContext1Constructed where stage != .extensions:
        stage = .extensions

      default:
        throw TokenFailure.malformed
      }
    }
    guard reader.isAtEnd else { throw TokenFailure.malformed }
    return found
  }

  /// Whether an AlgorithmIdentifier is SHA-384 with absent or NULL
  /// parameters, both forms recipients must understand (RFC 5754).
  internal static func isSha384(_ encoded: Data) -> Bool {
    var outer = DerReader(encoded)
    guard
      let sequence = outer.next(),
      sequence.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      return false
    }
    var reader = DerReader(encoded, within: sequence)
    guard
      let oid = reader.next(),
      reader.data(of: oid) == DerEncoder.objectIdentifier(SignOids.sha384)
    else {
      return false
    }
    guard let parameters = reader.next() else { return reader.isAtEnd }
    return parameters.tag == DerValues.tagNull
      && reader.contentData(of: parameters).isEmpty
      && reader.isAtEnd
  }

  /// The TSTInfo eContent octets inside a token's SignedData.
  internal static func tstInfoContent(in token: Data) throws -> Data {
    guard
      let signedData = CmsSignedData(in: token),
      let content = signedData.attachedOctetString(
        contentType: SignOids.tstInfo,
        in: token
      )
    else {
      throw TokenFailure.malformed
    }
    return content
  }
}
