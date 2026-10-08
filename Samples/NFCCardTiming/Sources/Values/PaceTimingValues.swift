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

  /// Fixed terminal points: the second and third multiples of the
  /// brainpoolP384r1 base point of RFC 5639 section 3.6, computed from it
  /// and checked on the curve. Valid points the card computes against
  /// without the probe holding any secret. The base point itself is not
  /// accepted by the card as a terminal key, so the multiples are used.
  internal static let mappingPointX =
    "2282BC382A2F4DFCB95C3495D7B4FD590AD520B3EB6BE4D6EC2F80C4E0F70DF87C4BA74A09B553EBB427B58DF9D59FCA"
  internal static let mappingPointY =
    "0EDDA83773AC68735768D14A24F37A57CE9BEDBC170921CE4D89DD051728FC3EB4B4EA69AB64FC288F1B29502B6E1D30"
  internal static let agreementPointX =
    "7B63205BF00DDAE73B17452B6A27EBF53DF581348C6949F83EE1B6FCC7463BBE3C11EF6596A3B8897D7CC85B3035F11F"
  internal static let agreementPointY =
    "761D3A4A5F8093775521A326BC02BAAF7B2EB481EAD16A5C7B2BD39462363E0373C0EDAEA3B8F59381D7129D48772EB3"
}
