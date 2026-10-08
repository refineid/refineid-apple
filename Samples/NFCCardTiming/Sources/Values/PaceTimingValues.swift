// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The wire values the timing probe sends, each with the document that
/// defines it.
internal enum PaceTimingValues {
  // MARK: ISO/IEC 7816-4

  /// CLA for an interindustry command that is the last in its chain.
  internal static let classInterindustry: UInt8 = 0x00

  /// CLA with the command-chaining bit: more of this command follows.
  internal static let classCommandChaining: UInt8 = 0x10

  internal static let insManageSecurityEnvironment: UInt8 = 0x22
  internal static let insGeneralAuthenticate: UInt8 = 0x86

  /// MSE:Set, authentication template (P1 = set for computation, P2 = AT).
  internal static let mseSetAuthenticationTemplateP1: UInt8 = 0xC1
  internal static let mseSetAuthenticationTemplateP2: UInt8 = 0xA4

  internal static let generalAuthenticateP1: UInt8 = 0x00
  internal static let generalAuthenticateP2: UInt8 = 0x00

  /// Short-form Le asking for up to 256 bytes.
  internal static let expectedLengthMaximum: UInt8 = 0x00

  /// Lengths below this encode in one byte; the probe never needs more.
  internal static let shortFormLengthLimit: Int = 0x80

  /// Bytes of status word at the end of every response.
  internal static let statusWordLength: Int = 2

  // MARK: BSI TR-03110 part 3, PACE

  /// id-PACE-ECDH-GM-AES-CBC-CMAC-256, 0.4.0.127.0.7.2.2.4.2.4, as the
  /// DER body: arc by arc, the first two arcs in one byte.
  internal static let protocolOid: [UInt8] = [
    oidArcItuTIdentifiedOrganization,
    oidArcEtsi,
    oidArcReserved,
    oidArcInternational,
    oidArcBsiDe,
    oidArcProtocols,
    oidArcSmartcard,
    oidArcIdPace,
    oidArcEcdhGenericMapping,
    oidArcAesCbcCmac256,
  ]

  private static let oidArcItuTIdentifiedOrganization: UInt8 = 0x04
  private static let oidArcEtsi: UInt8 = 0x00
  private static let oidArcReserved: UInt8 = 0x7F
  private static let oidArcInternational: UInt8 = 0x00
  private static let oidArcBsiDe: UInt8 = 0x07
  private static let oidArcProtocols: UInt8 = 0x02
  private static let oidArcSmartcard: UInt8 = 0x02
  private static let oidArcIdPace: UInt8 = 0x04
  private static let oidArcEcdhGenericMapping: UInt8 = 0x02
  private static let oidArcAesCbcCmac256: UInt8 = 0x04

  internal static let cryptographicMechanismReferenceTag: UInt8 = 0x80
  internal static let passwordReferenceTag: UInt8 = 0x83
  internal static let passwordReferenceCan: UInt8 = 0x02
  internal static let domainParameterReferenceTag: UInt8 = 0x84

  /// Standardized domain parameter 16: brainpoolP384r1.
  internal static let domainParameterBrainpoolP384r1: UInt8 = 0x10

  internal static let dynamicAuthenticationDataTag: UInt8 = 0x7C
  internal static let mappingDataTerminalTag: UInt8 = 0x81
  internal static let ephemeralPublicKeyTerminalTag: UInt8 = 0x83

  // MARK: SEC 1 and RFC 5639

  internal static let uncompressedPointTag: UInt8 = 0x04

  /// The brainpoolP384r1 base point, RFC 5639 section 3.6, used as the
  /// fixed terminal point: a valid point the card computes against
  /// without the probe holding any secret.
  internal static let generatorX =
    "1D1C64F068CF45FFA2A63A81B7C13F6B8847A3E77EF14FE3DB7FCAFE0CBD10E8E826E03436D646AAEF87B2E247D4AF1E"
  internal static let generatorY =
    "8ABE1D7520F9C2A45CB1EB8E95CFD55262B70B29FEEC5864E19C054FF99129280E4646217791811142820341263C5315"
}
