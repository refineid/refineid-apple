// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The suite the handshake takes from EF.CardAccess: generic mapping over
/// the most preferred listed domain, NIST P-384, then brainpoolP384r1,
/// then NIST P-256 (refineid-core `doc/reference/pace.md`).
@Suite
internal struct CardAccessTests {
  /// An unregistered `PACEInfo` version.
  private static let deprecatedVersion: UInt8 = 1

  /// A table 4 identifier this build does not run: brainpoolP256r1.
  private static let brainpoolP256: UInt8 = 13

  @Test
  internal func theCitizenCardRunsGenericMappingOverBrainpool() throws {
    let access = try CardAccess.parse(CardAccessFixture.citizenCard)
    #expect(access.suites.count == 1)
    let suite = try #require(access.genericMappingSuite)
    #expect(suite.mapping == .generic)
    #expect(suite.domain == .brainpoolP384r1)
  }

  @Test
  internal func theOrganizationCardRunsGenericMappingOverP384() throws {
    let access = try CardAccess.parse(CardAccessFixture.organizationCard)
    #expect(access.suites.count == 4)
    let suite = try #require(access.genericMappingSuite)
    #expect(suite.mapping == .generic)
    #expect(suite.domain == .nistP384)
  }

  @Test
  internal func unrunnableEntriesAreSkipped() throws {
    let access = try CardAccess.parse(
      CardAccessFixture.file([
        CardAccessFixture.paceInfo(
          CardAccessFixture.genericMappingOidHex, version: Self.deprecatedVersion,
          parameter: CardAccessFixture.nistP384),
        CardAccessFixture.paceInfo(
          CardAccessFixture.genericMappingOidHex, parameter: Self.brainpoolP256),
        CardAccessFixture.paceInfo(CardAccessFixture.genericMappingOidHex, parameter: nil),
      ]))
    #expect(access.suites.isEmpty)
    #expect(access.genericMappingSuite == nil)
  }

  @Test
  internal func aRunnableEntryWithoutAVersionFailsTheParse() {
    let malformed = CardAccessFixture.file([
      DerTlvRecord.encoded(
        tag: CardAccessFixture.sequenceTag,
        value: DerTlvRecord.encoded(
          tag: CardAccessFixture.objectIdentifierTag,
          value: WireHex.data(CardAccessFixture.genericMappingOidHex)) ?? Data()) ?? Data()
    ])
    #expect(throws: CardAccess.Failure.malformedPaceInfo) {
      try CardAccess.parse(malformed)
    }
  }

  @Test
  internal func bytesThatAreNotOneSetFailTheParse() {
    #expect(throws: CardAccess.Failure.notSecurityInfos) {
      try CardAccess.parse(Data())
    }
    #expect(throws: CardAccess.Failure.notSecurityInfos) {
      try CardAccess.parse(CardAccessFixture.citizenCard + CardAccessFixture.citizenCard)
    }
  }
}
