// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EF.CardAccess parsing, against bytes in the shape ICAO 9303-11
/// section 9.2.11 defines.
///
/// The fixtures are assembled here rather than copied from a card: a
/// card's file would carry its serial-adjacent detail into the
/// repository, and the structure is what these tests are about.
internal struct CardAccessFileTests {
  /// `0.4.0.127.0.7.2.2.4.2.4` -- PACE-ECDH-GM-AES-CBC-CMAC-256, the
  /// suite RefineID runs.
  private static let ecdhGenericAes256: [UInt8] = [
    0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02, 0x04, 0x02, 0x04,
  ]

  /// `0.4.0.127.0.7.2.2.4.4.4` -- the same cipher under integrated
  /// mapping, which is the cheaper variant this file is read to find.
  private static let ecdhIntegratedAes256: [UInt8] = [
    0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02, 0x04, 0x04, 0x04,
  ]

  /// Wraps `content` in a DER record with a short-form length.
  private static func record(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
    [tag, UInt8(content.count)] + content
  }

  /// One PACEInfo SEQUENCE: protocol, version, optional parameter id.
  private static func paceInfo(
    oid: [UInt8],
    version: UInt8,
    parameterID: UInt8?
  ) -> [UInt8] {
    var body = record(tag: 0x06, oid) + record(tag: 0x02, [version])
    if let parameterID {
      body += record(tag: 0x02, [parameterID])
    }
    return record(tag: 0x30, body)
  }

  /// A whole file: the SET wrapping every entry.
  private static func file(_ entries: [[UInt8]]) -> Data {
    Data(record(tag: 0x31, Array(entries.joined())))
  }

  @Test("the running suite is recognized and fully named")
  internal func namesTheRunningSuite() throws {
    let der = Self.file([
      Self.paceInfo(oid: Self.ecdhGenericAes256, version: 2, parameterID: 16)
    ])
    let infos = CardAccessFile.parse(der)
    #expect(infos.count == 1)
    let info = try #require(infos.first)
    #expect(info.isPace)
    #expect(info.protocolName == "PACE-ECDH-GM-AES-CBC-CMAC-256")
    #expect(info.objectIdentifier == "0.4.0.127.0.7.2.2.4.2.4")
    #expect(info.version == 2)
    #expect(info.parameterID == 16)
    #expect(info.parameterName == "brainpoolP384r1")
  }

  @Test("integrated mapping is distinguished from generic")
  internal func distinguishesIntegratedMapping() {
    let der = Self.file([
      Self.paceInfo(oid: Self.ecdhGenericAes256, version: 2, parameterID: 16),
      Self.paceInfo(oid: Self.ecdhIntegratedAes256, version: 2, parameterID: 13),
    ])
    let infos = CardAccessFile.parse(der)
    #expect(infos.count == 2)
    #expect(infos[1].protocolName == "PACE-ECDH-IM-AES-CBC-CMAC-256")
    #expect(infos[1].parameterName == "brainpoolP256r1")
    #expect(!infos[0].usesIntegratedMapping)
    #expect(infos[1].usesIntegratedMapping)
  }

  @Test("a parameter id this build does not know keeps its number")
  internal func keepsUnknownParameterNumber() throws {
    let der = Self.file([
      Self.paceInfo(oid: Self.ecdhGenericAes256, version: 2, parameterID: 99)
    ])
    let info = try #require(CardAccessFile.parse(der).first)
    #expect(info.parameterID == 99)
    #expect(info.parameterName == nil)
  }

  @Test("an absent parameter id is absent, not invented")
  internal func leavesAbsentParameterAbsent() throws {
    let der = Self.file([
      Self.paceInfo(oid: Self.ecdhGenericAes256, version: 2, parameterID: nil)
    ])
    let info = try #require(CardAccessFile.parse(der).first)
    #expect(info.version == 2)
    #expect(info.parameterID == nil)
  }

  @Test("a protocol outside the PACE family is reported by identifier")
  internal func reportsUnknownProtocolByIdentifier() throws {
    // 0.4.0.127.0.7.2.2.3.2.2 -- id-CA-ECDH-AES-CBC-CMAC-128.
    let chipAuthentication: [UInt8] = [
      0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02, 0x03, 0x02, 0x02,
    ]
    let der = Self.file([
      Self.paceInfo(oid: chipAuthentication, version: 1, parameterID: nil)
    ])
    let info = try #require(CardAccessFile.parse(der).first)
    #expect(!info.isPace)
    #expect(info.protocolName == nil)
    #expect(info.objectIdentifier == "0.4.0.127.0.7.2.2.3.2.2")
  }

  @Test("bytes that are not a SET parse to nothing")
  internal func refusesNonSet() {
    #expect(CardAccessFile.parse(Data([0x30, 0x02, 0x02, 0x01])).isEmpty)
    #expect(CardAccessFile.parse(Data()).isEmpty)
  }

  @Test("an unparsable entry is skipped, not fatal")
  internal func skipsUnparsableEntry() {
    let der = Self.file([
      Self.record(tag: 0x30, [0x02, 0x01, 0x05]),
      Self.paceInfo(oid: Self.ecdhGenericAes256, version: 2, parameterID: 16),
    ])
    let infos = CardAccessFile.parse(der)
    #expect(infos.count == 1)
    #expect(infos[0].protocolName == "PACE-ECDH-GM-AES-CBC-CMAC-256")
  }
}
