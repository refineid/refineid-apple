// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// EF.CardAccess files in the shapes the FINEID cards publish (BSI
/// TR-03110-3 section A.1, table 2), assembled from named parts.
///
/// The citizen cards list generic and chip-authentication mapping over
/// brainpoolP384r1 (FINEID S4-1 v4.2 section 3.2); the organization card
/// lists generic and integrated mapping, each over NIST P-256 and P-384
/// (FINEID S4-2 v4.0 section 6).
internal enum CardAccessFixture {
  /// `id-PACE-ECDH-GM-AES-CBC-CMAC-256`, `0.4.0.127.0.7.2.2.4.2.4`.
  internal static let genericMappingOidHex = "04007F00070202040204"

  /// `id-PACE-ECDH-IM-AES-CBC-CMAC-256`, `0.4.0.127.0.7.2.2.4.4.4`.
  internal static let integratedMappingOidHex = "04007F00070202040404"

  /// `id-PACE-ECDH-CAM-AES-CBC-CMAC-256`, `0.4.0.127.0.7.2.2.4.6.4`.
  internal static let chipAuthenticationMappingOidHex = "04007F00070202040604"

  /// The `PACEInfo` version the cards list.
  internal static let version: UInt8 = 2

  /// Standardized domain parameters (BSI TR-03110-3 table 4).
  internal static let nistP256: UInt8 = 12
  internal static let nistP384: UInt8 = 15
  internal static let brainpoolP384: UInt8 = 16

  /// DER tags (ITU-T X.690).
  private static let setTag: UInt8 = 0x31
  internal static let sequenceTag: UInt8 = 0x30
  internal static let objectIdentifierTag: UInt8 = 0x06
  private static let integerTag: UInt8 = 0x02

  /// What a citizen card publishes.
  internal static var citizenCard: Data {
    file([
      paceInfo(genericMappingOidHex, parameter: brainpoolP384),
      paceInfo(chipAuthenticationMappingOidHex, parameter: brainpoolP384),
    ])
  }

  /// What the organization card publishes.
  internal static var organizationCard: Data {
    file([
      paceInfo(genericMappingOidHex, parameter: nistP256),
      paceInfo(genericMappingOidHex, parameter: nistP384),
      paceInfo(integratedMappingOidHex, parameter: nistP256),
      paceInfo(integratedMappingOidHex, parameter: nistP384),
    ])
  }

  /// A card offering generic mapping over P-256 alone.
  internal static var p256OnlyCard: Data {
    file([paceInfo(genericMappingOidHex, parameter: nistP256)])
  }

  /// A card offering integrated mapping alone.
  internal static var integratedOnlyCard: Data {
    file([paceInfo(integratedMappingOidHex, parameter: nistP384)])
  }

  /// One `PACEInfo`: protocol, version, and the optional parameter id.
  internal static func paceInfo(_ oidHex: String, parameter: UInt8?) -> Data {
    paceInfo(oidHex, version: version, parameter: parameter)
  }

  /// One `PACEInfo` with a stated version.
  internal static func paceInfo(_ oidHex: String, version: UInt8, parameter: UInt8?) -> Data {
    var fields = encoded(objectIdentifierTag, WireHex.data(oidHex))
    fields += encoded(integerTag, Data([version]))
    if let parameter {
      fields += encoded(integerTag, Data([parameter]))
    }
    return encoded(sequenceTag, fields)
  }

  /// The SET wrapping every entry.
  internal static func file(_ entries: [Data]) -> Data {
    encoded(setTag, entries.reduce(Data(), +))
  }

  private static func encoded(_ tag: UInt8, _ value: Data) -> Data {
    DerTlvRecord.encoded(tag: tag, value: value) ?? Data()
  }
}
