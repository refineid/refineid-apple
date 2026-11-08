// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// A locked phone starts no credential action; it tells the holder and the
/// computer, continues on the unlock, and leaves a started action alone
/// (RAPP v26.11.8 §8.2 item 3).
@MainActor
@Suite
internal struct CustodianUnlockGateTests {
  /// A lock the test locks and unlocks.
  @MainActor
  private final class ScriptedLock: CustodianLockState {
    var isLocked: Bool

    init(isLocked: Bool) {
      self.isLocked = isLocked
    }
  }

  /// What one operation did, in order.
  private actor Log {
    private(set) var lines: [String] = []

    func add(_ line: String) {
      lines.append(line)
    }

    func count(of line: String) -> Int {
      lines.filter { $0 == line }.count
    }
  }

  private static let ticket = "operation"
  private static let progress = "waiting_for_unlock"
  private static let notice = "notice posted"
  private static let withdrawn = "notice withdrawn"
  private static let cardCommand = "card command"
  private static let yields = 20
  private static let batchSize = 3

  /// Lets every task the test started run as far as it can.
  private static func settle() async {
    for _ in 0..<Self.yields {
      await Task.yield()
    }
  }

  /// The credential step as the dispatcher runs it: the gate, then the card.
  private static func credentialStep(
    gate: CustodianUnlockGate<String>, log: Log
  ) -> Task<Bool, Never> {
    Task { @MainActor in
      let passed = await gate.pass(Self.ticket) {
        await log.add(Self.progress)
        await log.add(Self.notice)
      } withdraw: {
        await log.add(Self.withdrawn)
      }
      if passed { await log.add(Self.cardCommand) }
      return passed
    }
  }

  @Test("An unlocked phone runs the action at once and tells no one")
  internal func unlockedPhoneRunsAtOnce() async {
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: ScriptedLock(isLocked: false))
    #expect(await Self.credentialStep(gate: gate, log: log).value)
    #expect(await log.lines == [Self.cardCommand])
  }

  @Test("A locked phone sends no card command and tells the computer and the holder once")
  internal func lockedPhoneWaits() async {
    let lock = ScriptedLock(isLocked: true)
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: lock)
    let step = Self.credentialStep(gate: gate, log: log)
    await Self.settle()
    gate.reassess()
    await Self.settle()
    #expect(await log.lines == [Self.progress, Self.notice], "still locked: nothing more")

    lock.isLocked = false
    gate.reassess()
    #expect(await step.value)
    #expect(await log.lines == [Self.progress, Self.notice, Self.withdrawn, Self.cardCommand])
  }

  @Test("The operation's deadline ends a wait still locked, with no card command")
  internal func deadlineEndsTheWait() async {
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: ScriptedLock(isLocked: true))
    let step = Self.credentialStep(gate: gate, log: log)
    await Self.settle()
    gate.end(Self.ticket)
    #expect(await step.value == false)
    #expect(await log.lines == [Self.progress, Self.notice, Self.withdrawn])
  }

  @Test("An operation that ended before its turn at the gate tells no one")
  internal func endedBeforeThePass() async {
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: ScriptedLock(isLocked: true))
    gate.end(Self.ticket)
    #expect(await Self.credentialStep(gate: gate, log: log).value == false)
    #expect(await log.lines.isEmpty)
  }

  @Test("An unlock while the holder is being told is not missed")
  internal func unlockDuringTheTelling() async {
    let lock = ScriptedLock(isLocked: true)
    let gate = CustodianUnlockGate<String>(lockState: lock)
    let passed = await gate.pass(Self.ticket) {
      await MainActor.run { lock.isLocked = false }
    } withdraw: {
      // Nothing was shown.
    }
    #expect(passed)
  }

  @Test("A second lock of one operation tells the computer again")
  internal func secondLockTellsAgain() async {
    let lock = ScriptedLock(isLocked: true)
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: lock)
    for _ in 0..<2 {
      lock.isLocked = true
      let step = Self.credentialStep(gate: gate, log: log)
      await Self.settle()
      lock.isLocked = false
      gate.reassess()
      #expect(await step.value)
    }
    #expect(await log.count(of: Self.progress) == 2)
  }

  @Test("A lock after the gate does not stop an approved batch")
  internal func approvedBatchContinuesAcrossALock() async {
    let lock = ScriptedLock(isLocked: false)
    let log = Log()
    let gate = CustodianUnlockGate<String>(lockState: lock)
    #expect(await Self.credentialStep(gate: gate, log: log).value)
    lock.isLocked = true
    for _ in 1..<Self.batchSize {
      await log.add(Self.cardCommand)
    }
    #expect(await log.count(of: Self.cardCommand) == Self.batchSize)
    #expect(await log.count(of: Self.progress) == 0)
  }

  @Test("The lock-screen notice names the computer")
  internal func noticeNamesTheComputer() {
    let computer = "Workstation"
    #expect(
      RappAuthorizationPrompt.unlockAuthenticationMessage(computer: computer).contains(computer))
    #expect(RappAuthorizationPrompt.unlockSignatureMessage(computer: computer).contains(computer))
  }

  @Test(
    "The lock-screen notice says the full PIN name in every language",
    arguments: [
      ("en", "Basic PIN 1", "Signature PIN 2"),
      ("fi", "perustunnusluvulla 1", "allekirjoitustunnusluvulla 2"),
      ("sv", "grund PIN 1", "signaturkod 2"),
    ])
  internal func noticeWords(language: String, basic: String, signature: String) throws {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let login = "%@ asks you to authenticate with Basic PIN 1. Unlock your phone."
    let sign = "%@ asks you to sign with Signature PIN 2. Unlock your phone."
    #expect(bundle.localizedString(forKey: login, value: nil, table: nil).contains(basic))
    #expect(bundle.localizedString(forKey: sign, value: nil, table: nil).contains(signature))
  }
}
