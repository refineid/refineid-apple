// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// A vault write succeeds only when the keychain reports the write.
@Suite("Vault writes answer the keychain's status")
internal struct RappDeviceVaultWriteStatusTests {
  private typealias Write = RappVaultTestKeychain.Write

  /// Refusals that say the keychain is closed to the process, and an
  /// ordinary one.
  private static let refusals = [
    errSecAuthFailed, errSecMissingEntitlement, errSecInteractionNotAllowed, errSecIO,
  ]

  private static let pairID = Data(repeating: 1, count: RappDeviceVault.IdentifierSize.pair)
  private static let firstRecord = Data("first record".utf8)
  private static let secondRecord = Data("second record".utf8)

  private static func vault() -> RappDeviceVault {
    RappDeviceVault(
      accessGroup: nil, servicePrefix: "fi.refineid.test.writes.\(UUID().uuidString)")
  }

  private static func expectRefused(
    with status: OSStatus, _ write: () throws -> Void
  ) {
    #expect(throws: RappDeviceVault.Failure.unavailable(status)) { try write() }
  }

  @Test("A refused add stores nothing, in the keychain or in memory")
  internal func refusedAddStoresNothing() throws {
    for status in Self.refusals {
      let vault = Self.vault()
      vault.testKeychain.refusal = { $0 == .add ? status : nil }
      Self.expectRefused(with: status) {
        try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
      }
      #expect(try vault.activePairIDs().isEmpty)
      #expect(try vault.loadPair(pairID: Self.pairID) == nil)
    }
  }

  @Test("A successful add stores the record with one write")
  internal func successStores() throws {
    let vault = Self.vault()
    try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
    #expect(vault.testKeychain.attempts == [.add])
    #expect(try vault.loadPair(pairID: Self.pairID) == Self.firstRecord)
    #expect(try vault.activePairIDs() == [Self.pairID])
  }

  @Test("A duplicate goes to the update, and the update's status decides")
  internal func duplicateUpdateIsChecked() throws {
    let vault = Self.vault()
    try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)

    try vault.insertPair(pairID: Self.pairID, record: Self.secondRecord)
    #expect(vault.testKeychain.attempts == [.add, .add, .update])
    #expect(try vault.loadPair(pairID: Self.pairID) == Self.secondRecord)

    for status in Self.refusals {
      vault.testKeychain.refusal = { $0 == .update ? status : nil }
      Self.expectRefused(with: status) {
        try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
      }
      #expect(try vault.loadPair(pairID: Self.pairID) == Self.secondRecord)
    }
  }

  @Test("A refused replacement keeps the record it would have replaced")
  internal func refusedReplaceKeepsTheRecord() throws {
    let vault = Self.vault()
    try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
    for status in Self.refusals {
      vault.testKeychain.refusal = { $0 == .update ? status : nil }
      Self.expectRefused(with: status) {
        try vault.replacePair(pairID: Self.pairID, record: Self.secondRecord)
      }
      #expect(try vault.loadPair(pairID: Self.pairID) == Self.firstRecord)
    }
  }

  @Test("A refused revocation keeps the record and says so")
  internal func refusedDeleteIsReported() throws {
    let vault = Self.vault()
    try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
    for status in Self.refusals {
      vault.testKeychain.refusal = { $0 == .delete ? status : nil }
      Self.expectRefused(with: status) {
        try vault.revokePair(pairID: Self.pairID, revokedAtMilliseconds: 0)
      }
      #expect(try vault.loadPair(pairID: Self.pairID) == Self.firstRecord)
    }
    vault.testKeychain.refusal = { _ in nil }
    try vault.revokePair(pairID: Self.pairID, revokedAtMilliseconds: 0)
    #expect(try vault.loadPair(pairID: Self.pairID) == nil)
    try vault.revokePair(pairID: Self.pairID, revokedAtMilliseconds: 0)
  }

  @Test("A refused selection selects nothing, whichever write refused")
  internal func refusedSelectionSelectsNothing() throws {
    let refusedWrites: [Write] = [.update, .add]
    for refused in refusedWrites {
      let vault = Self.vault()
      try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
      vault.testKeychain.refusal = { $0 == refused ? errSecMissingEntitlement : nil }
      Self.expectRefused(with: errSecMissingEntitlement) {
        try vault.selectPair(pairID: Self.pairID)
      }
      #expect(try vault.selectedPairID() == nil)
    }
    let vault = Self.vault()
    try vault.insertPair(pairID: Self.pairID, record: Self.firstRecord)
    try vault.selectPair(pairID: Self.pairID)
    #expect(try vault.selectedPairID() == Self.pairID)
  }

  @Test("A read refused for a missing entitlement is an error, not an absence")
  internal func missingEntitlementIsNotUnreadableForNow() {
    #expect(!RappDeviceVault.isUnreadableForNow(errSecMissingEntitlement))
    #expect(RappDeviceVault.isUnreadableForNow(errSecInteractionNotAllowed))
    #expect(!RappDeviceVault.isUnreadableForNow(errSecIO))
  }
}
