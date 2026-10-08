// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The four commands the probe sends, in order.
///
/// They are the opening of PACE-ECDH-GM over brainpoolP384r1: set the
/// security environment, ask for the encrypted nonce, send a mapping
/// point, send an ephemeral public key. The card performs its two
/// elliptic-curve computations in the last two rounds for any valid
/// terminal point, so the probe sends the curve's base point and stops
/// before the authentication token. Nothing is authenticated, no
/// password is involved, and no retry counter is touched.
internal struct PaceTimingCommand: Sendable {
  internal static let sequence: [Self] = [
    Self.securityEnvironment,
    Self.generalAuthenticate(name: "GA nonce", template: Data(), chained: true),
    Self.generalAuthenticate(
      name: "GA mapping",
      template: Self.tlv(PaceTimingValues.mappingDataTerminalTag, Self.mappingPoint),
      chained: true),
    Self.generalAuthenticate(
      name: "GA key agreement",
      template: Self.tlv(PaceTimingValues.ephemeralPublicKeyTerminalTag, Self.agreementPoint),
      chained: true),
  ]

  private static let securityEnvironment: Self = {
    let data =
      Self.tlv(
        PaceTimingValues.cryptographicMechanismReferenceTag, Data(PaceTimingValues.protocolOid))
      + Self.tlv(
        PaceTimingValues.passwordReferenceTag, Data([PaceTimingValues.passwordReferenceCan]))
      + Self.tlv(
        PaceTimingValues.domainParameterReferenceTag,
        Data([PaceTimingValues.domainParameterBrainpoolP384r1]))
    var command = Data([
      PaceTimingValues.classInterindustry,
      PaceTimingValues.insManageSecurityEnvironment,
      PaceTimingValues.mseSetAuthenticationTemplateP1,
      PaceTimingValues.mseSetAuthenticationTemplateP2,
      UInt8(data.count),
    ])
    command.append(data)
    return Self(name: "MSE:Set AT", apdu: command)
  }()

  private static let hexRadix = 16

  /// The fixed points in uncompressed SEC 1 form.
  private static let mappingPoint: Data =
    Data([PaceTimingValues.uncompressedPointTag])
    + Self.bytes(PaceTimingValues.mappingPointX)
    + Self.bytes(PaceTimingValues.mappingPointY)
  private static let agreementPoint: Data =
    Data([PaceTimingValues.uncompressedPointTag])
    + Self.bytes(PaceTimingValues.agreementPointX)
    + Self.bytes(PaceTimingValues.agreementPointY)

  internal let name: String
  internal let apdu: Data

  private static func generalAuthenticate(
    name: String, template: Data, chained: Bool
  ) -> Self {
    let data = Self.tlv(PaceTimingValues.dynamicAuthenticationDataTag, template)
    var command = Data([
      chained ? PaceTimingValues.classCommandChaining : PaceTimingValues.classInterindustry,
      PaceTimingValues.insGeneralAuthenticate,
      PaceTimingValues.generalAuthenticateP1,
      PaceTimingValues.generalAuthenticateP2,
      UInt8(data.count),
    ])
    command.append(data)
    command.append(PaceTimingValues.expectedLengthMaximum)
    return Self(name: name, apdu: command)
  }

  /// One short-form DER record. Every value here is shorter than the
  /// one-byte length limit, and the precondition keeps it so.
  private static func tlv(_ tag: UInt8, _ value: Data) -> Data {
    precondition(value.count < PaceTimingValues.shortFormLengthLimit)
    var record = Data([tag, UInt8(value.count)])
    record.append(value)
    return record
  }

  private static func bytes(_ hex: String) -> Data {
    var data = Data()
    var digits = hex[...]
    while let high = digits.first {
      digits = digits.dropFirst()
      guard let low = digits.first, let byte = UInt8(String([high, low]), radix: Self.hexRadix)
      else {
        preconditionFailure("odd or non-hex constant")
      }
      digits = digits.dropFirst()
      data.append(byte)
    }
    return data
  }
}
