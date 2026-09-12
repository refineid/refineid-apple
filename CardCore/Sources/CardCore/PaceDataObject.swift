// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The data objects a PACE round exchanges: the `7C` dynamic authentication
/// data template, its context objects, and the `7F49` public key template
/// the mutual-authentication tokens are computed over.
///
/// Encoding and parsing are separated from the protocol flow so that the
/// flow reads as the protocol and each wire shape has one place it is built
/// and one place it is checked.
///
/// Provenance: the `Tlv` usage inside the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`.
internal enum PaceDataObject {
  /// The `7C` template carrying one context data object.
  internal static func dynamicAuthenticationData(
    contextTag: UInt8,
    value: Data
  ) -> Data? {
    guard let context = DerTlvRecord.encoded(tag: contextTag, value: value) else {
      return nil
    }
    return DerTlvRecord.encoded(
      tag: PaceValues.dynamicAuthenticationDataTag,
      value: context
    )
  }

  /// The empty `7C` template that opens the exchange.
  internal static func emptyDynamicAuthenticationData() -> Data? {
    DerTlvRecord.encoded(
      tag: PaceValues.dynamicAuthenticationDataTag,
      value: Data()
    )
  }

  /// The value of one context data object inside a response's `7C`
  /// template.
  internal static func value(in payload: Data, contextTag: UInt8) throws -> Data {
    guard
      let outer = try? DerTlvRecord.sequence(in: payload),
      let template = outer.first,
      template.tag == PaceValues.dynamicAuthenticationDataTag,
      let inner = try? DerTlvRecord.sequence(in: template.value),
      let record = inner.first(where: { $0.tag == contextTag })
    else {
      throw PaceEstablishment.Failure.malformedResponse
    }
    return record.value
  }

  /// The card's point from one context data object.
  ///
  /// `BrainpoolPoint`'s decoder is the gate: a non-canonical coordinate or
  /// an off-curve pair never becomes a point, so the protocol flow never
  /// has to re-check what the card sent.
  internal static func point(in payload: Data, contextTag: UInt8) throws -> BrainpoolPoint {
    let encoded = try Self.value(in: payload, contextTag: contextTag)
    guard let decoded = BrainpoolPoint.decodeUncompressed(encoded) else {
      throw PaceEstablishment.Failure.malformedResponse
    }
    return decoded
  }

  /// The SEC1 uncompressed encoding of a point the protocol requires to be
  /// finite.
  internal static func encodedPoint(_ point: BrainpoolPoint) throws -> Data {
    guard let encoded = point.encodeUncompressed() else {
      throw PaceEstablishment.Failure.unusablePoint
    }
    return encoded
  }

  /// The mutual-authentication token input for a point:
  /// `7F49 { 06 <protocol OID>, 86 <point> }`.
  ///
  /// The two-byte tag `7F49` is emitted by encoding the template under its
  /// second byte and prefixing the first, which yields exactly
  /// `7F 49 <len> <value>` and needs no second encoder.
  internal static func authenticationTokenInput(for point: BrainpoolPoint) throws -> Data {
    guard
      let identifier = DerTlvRecord.encoded(
        tag: PaceValues.objectIdentifierTag,
        value: Data(PaceValues.protocolOidBody)
      ),
      let publicKey = DerTlvRecord.encoded(
        tag: PaceValues.publicKeyTemplatePointTag,
        value: try Self.encodedPoint(point)
      ),
      let template = DerTlvRecord.encoded(
        tag: PaceValues.publicKeyTemplateTagSecondByte,
        value: identifier + publicKey
      )
    else {
      throw PaceEstablishment.Failure.malformedResponse
    }
    return Data([PaceValues.publicKeyTemplateTagFirstByte]) + template
  }
}
