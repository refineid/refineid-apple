// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension HeldCardSessionTests {
  /// Slot loss wakes the signer before a blocked transport completes.
  @Test(arguments: [true, false])
  internal func testSlotLossDuringPACEWakesSignerAndDefersCleanup(startEarly: Bool) throws {
    let can = try #require(CardAccessNumber(digits: Self.validCanString))
    let channel = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let transmitStarted = DispatchSemaphore(value: 0)
    let resumeTransmit = DispatchSemaphore(value: 0)
    let signerWaiting = DispatchSemaphore(value: 0)
    let signerFinished = DispatchSemaphore(value: 0)
    let released = DispatchSemaphore(value: 0)
    let cleaned = DispatchSemaphore(value: 0)
    let held = HeldCardSession(diagnostic: { event in
      if event.contains("waiting preparation") { signerWaiting.signal() }
    })
    channel.onFirstTransmit = {
      transmitStarted.signal()
      resumeTransmit.wait()
    }
    channel.onEnd = { cleaned.signal() }
    held.retain(channel)
    if startEarly { held.startPACE(with: can) }
    defer { resumeTransmit.signal() }
    DispatchQueue.global().async {
      #expect(throws: CardOperationError.sessionUnavailable) {
        try held.preparedChannel(accessNumber: can)
      }
      signerFinished.signal()
    }
    try #require(signerWaiting.wait(timeout: .now() + 5) == .success)
    try #require(transmitStarted.wait(timeout: .now() + 5) == .success)
    DispatchQueue.global().async {
      held.release(reason: .slotMissing)
      released.signal()
    }
    #expect(released.wait(timeout: .now() + 1) == .success)
    #expect(signerFinished.wait(timeout: .now() + 1) == .success)
    #expect(!held.isAvailable)
    #expect(channel.sessionEndCount == 0)
    held.release(reason: .slotMissing)
    resumeTransmit.signal()
    #expect(cleaned.wait(timeout: .now() + 5) == .success)
    #expect(channel.sessionEndCount == 1)
    #expect(!held.isAvailable)
  }

  /// An old worker cannot publish preparation into a replacement hold.
  @Test
  internal func testLatePACECompletionCannotReviveReplacementHold() throws {
    let can = try #require(CardAccessNumber(digits: Self.validCanString))
    let old = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let replacement = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let started = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let discarded = DispatchSemaphore(value: 0)
    let cleaned = DispatchSemaphore(value: 0)
    let held = HeldCardSession(diagnostic: { event in
      if event.contains("PACE discarded") { discarded.signal() }
    })
    old.onFirstTransmit = {
      started.signal()
      resume.wait()
    }
    old.onEnd = { cleaned.signal() }
    held.retain(old)
    held.startPACE(with: can)
    defer { resume.signal() }
    try #require(started.wait(timeout: .now() + 5) == .success)
    DispatchQueue.global().async {
      held.release(reason: .slotMissing)
      held.retain(replacement)
      resume.signal()
    }
    try #require(discarded.wait(timeout: .now() + 5) == .success)
    #expect(cleaned.wait(timeout: .now() + 5) == .success)
    held.condition.lock()
    if case .idle = held.preparation {
      // The replacement remains unprepared until it is claimed.
    } else {
      Issue.record("Old worker changed replacement preparation")
    }
    held.condition.unlock()
    #expect(held.isAvailable)
    #expect(!replacement.isSessionEnded)
    let freshPACE = DispatchSemaphore(value: 0)
    replacement.onFirstTransmit = { freshPACE.signal() }
    do {
      let lease = try held.preparedChannel(accessNumber: can)
      #expect(freshPACE.wait(timeout: .now()) == .success)
      _ = lease
    }
    held.release()
    #expect(replacement.sessionEndCount == 1)
  }

  /// A timer from an earlier powered field cannot release its replacement.
  @Test
  internal func testStaleActivityTimerCannotReleaseReplacement() throws {
    let old = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let replacement = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let held = HeldCardSession()
    held.retain(old)
    let oldGeneration = held.generation
    held.release(reason: .slotMissing)
    held.retain(replacement)
    held.handleActivityTimeout(
      seconds: HeldCardSession.defaultActivityTimeoutSeconds, generation: oldGeneration)
    #expect(held.isAvailable)
    #expect(!replacement.isSessionEnded)
    held.release()
    #expect(old.sessionEndCount == 1)
    #expect(replacement.sessionEndCount == 1)
  }

  /// An active lease stops issuing commands after its powered field is lost.
  @Test
  internal func testSlotLossInvalidatesActiveSecureChannel() throws {
    let can = try #require(CardAccessNumber(digits: Self.validCanString))
    let channel = TestHeldCardChannel(card: try Self.makeSyntheticCard())
    let cleaned = DispatchSemaphore(value: 0)
    channel.onEnd = { cleaned.signal() }
    let held = HeldCardSession()
    held.retain(channel)
    do {
      let lease = try held.preparedChannel(accessNumber: can)
      held.release(reason: .slotMissing)
      #expect(!held.isAvailable)
      #expect(channel.sessionEndCount == 0)
      #expect(throws: CardOperationError.sessionUnavailable) {
        try CardOperations(channel: lease.channel).selectFineidApplication()
      }
      _ = lease
    }
    #expect(cleaned.wait(timeout: .now() + 5) == .success)
    #expect(channel.sessionEndCount == 1)
  }

}
