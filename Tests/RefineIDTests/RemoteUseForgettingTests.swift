// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappRequester
import Testing

/// The holder's click turning remote use off, against a vault that keeps its
/// pairings in memory: the click is stored before anything is forgotten, its
/// pairings are marked forgotten at the click's time, a later pairing stays,
/// and nothing is cleared that a failure or a later click should keep
/// (RAPP v26.11.8 §4.6 item 6, STPA CC-100, CC-118).
@Suite(.serialized)
internal struct RemoteUseForgettingTests {
  /// A vault of records in memory, with the refusals a test asks for.
  internal final class FakeVault: PairingVault, @unchecked Sendable {
    internal var records: [Data: (created: UInt64, forgotten: UInt64?)] = [:]
    /// Records the vault holds but cannot read.
    internal var unreadable: Set<Data> = []
    internal var refusesListing = false
    internal var refusesForget: Set<Data> = []
    internal private(set) var destroyed: [Data] = []

    internal func activePairIDs() throws -> [Data] {
      if refusesListing { throw PairingVaultError.unavailable }
      return records.filter { record in record.value.forgotten == nil }
        .map(\.key)
        .sorted { first, second in first.lexicographicallyPrecedes(second) }
    }

    internal func createdAtMs(of pairID: Data) throws -> UInt64? {
      guard let record = records[pairID] else { throw PairingVaultError.notFound }
      if unreadable.contains(pairID) { throw PairingVaultError.malformed }
      return record.created
    }

    internal func forgottenAtMs(of pairID: Data) throws -> UInt64? {
      guard let record = records[pairID] else { throw PairingVaultError.notFound }
      if unreadable.contains(pairID) { throw PairingVaultError.malformed }
      return record.forgotten
    }

    internal func forget(_ pairID: Data, at forgottenAtMs: UInt64) throws {
      if refusesForget.contains(pairID) { throw PairingVaultError.unavailable }
      guard let record = records[pairID] else { throw PairingVaultError.notFound }
      records[pairID] = (created: record.created, forgotten: forgottenAtMs)
    }

    internal func destroy(_ pairID: Data) {
      records[pairID] = nil
      destroyed.append(pairID)
    }

  }

  internal static let click: UInt64 = 1_000

  /// Pairings, as the vault names them.
  internal static let first = Data("first pairing".utf8)
  internal static let second = Data("second pairing".utf8)

  /// A store of its own, cleared before the test.
  internal static func store(_ name: String) -> RemoteUseForgetting.Store {
    UserDefaults.standard.removePersistentDomain(forName: name)
    return RemoteUseForgetting.Store(suiteName: name)
  }

  /// A vault holding `pairIDs`, made before the click.
  internal static func vault(_ pairIDs: Data...) -> FakeVault {
    let vault = FakeVault()
    for pairID in pairIDs {
      vault.records[pairID] = (created: click - 1, forgotten: nil)
    }
    return vault
  }

  @Test
  internal func aClickStoresItsPairingsBeforeForgetting() {
    let store = Self.store("fi.refineid.rapptests.forgetting.stored")
    let vault = Self.vault(Self.first, Self.second)

    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)

    let pending = RemoteUseForgetting.pending(in: store)
    #expect(pending?.clickedAtMs ?? 0 == Self.click)
    #expect(pending?.pairIDs == [Self.first, Self.second])
    #expect(pending?.needsListing == false)
    #expect(vault.records[Self.first]?.forgotten == nil)
  }

  @Test
  internal func finishingForgetsAtTheClicksTimeAndClears() {
    let store = Self.store("fi.refineid.rapptests.forgetting.finish")
    let vault = Self.vault(Self.first, Self.second)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)

    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.failures == 0)
    #expect(outcome.forgotten == [Self.first, Self.second])
    #expect(vault.records[Self.first]?.forgotten == Self.click)
    #expect(vault.records[Self.second]?.forgotten == Self.click)
    #expect(RemoteUseForgetting.pending(in: store) == nil)
  }

  @Test
  internal func aPairingMadeAfterTheClickStays() {
    let store = Self.store("fi.refineid.rapptests.forgetting.later")
    let vault = Self.vault(Self.first)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)
    vault.records[Self.second] = (created: Self.click + 1, forgotten: nil)

    _ = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(vault.records[Self.first]?.forgotten == Self.click)
    #expect(vault.records[Self.second]?.forgotten == nil)
  }

  @Test
  internal func anUnlistedVaultIsListedOnTheNextAttempt() {
    let store = Self.store("fi.refineid.rapptests.forgetting.listing")
    let vault = Self.vault(Self.first)
    vault.refusesListing = true

    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)

    #expect(RemoteUseForgetting.pending(in: store)?.needsListing == true)

    vault.refusesListing = false
    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.forgotten == [Self.first])
    #expect(vault.records[Self.first]?.forgotten == Self.click)
    #expect(RemoteUseForgetting.pending(in: store) == nil)
  }

  @Test
  internal func aRefusedForgetKeepsTheClickForTheNextAttempt() {
    let store = Self.store("fi.refineid.rapptests.forgetting.refused")
    let vault = Self.vault(Self.first)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)
    vault.refusesForget.insert(Self.first)

    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.failures == 1)
    #expect(RemoteUseForgetting.pending(in: store) != nil)

    vault.refusesForget.removeAll()
    let retried = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(retried.forgotten == [Self.first])
    #expect(RemoteUseForgetting.pending(in: store) == nil)
  }

  @Test
  internal func anUnreadableRecordIsDestroyed() {
    let store = Self.store("fi.refineid.rapptests.forgetting.malformed")
    let vault = Self.vault(Self.first, Self.second)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)
    vault.unreadable.insert(Self.second)

    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.forgotten == [Self.first, Self.second])
    #expect(vault.destroyed == [Self.second])
    #expect(RemoteUseForgetting.pending(in: store) == nil)
  }

  @Test
  internal func aPairingTheVaultLostIsPassedOver() {
    let store = Self.store("fi.refineid.rapptests.forgetting.lost")
    let vault = Self.vault(Self.first, Self.second)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)
    vault.records[Self.second] = nil

    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.forgotten == [Self.first])
    #expect(outcome.failures == 0)
    #expect(RemoteUseForgetting.pending(in: store) == nil)
  }

  @Test
  internal func aSecondClickExtendsTheFirst() {
    let store = Self.store("fi.refineid.rapptests.forgetting.second")
    RemoteUseForgetting.request(at: Self.click, forgetting: [Self.first], listed: true, in: store)
    RemoteUseForgetting.request(
      at: Self.click + 5, forgetting: [Self.second], listed: true, in: store)

    let pending = RemoteUseForgetting.pending(in: store)
    #expect(pending?.clickedAtMs ?? 0 == Self.click + 5)
    #expect(pending?.pairIDs == [Self.first, Self.second])
  }

  @Test
  internal func anAttemptFinishesTheClickItRead() {
    let store = Self.store("fi.refineid.rapptests.forgetting.compare")
    let vault = Self.vault(Self.first)
    RemoteUseForgetting.request(at: Self.click, listing: vault, in: store)

    let outcome = RemoteUseForgetting.finish(in: vault, store: store)

    #expect(outcome.failures == 0)
    #expect(RemoteUseForgetting.pending(in: store) == nil)
    #expect(vault.records[Self.first]?.forgotten == Self.click)
  }
}
