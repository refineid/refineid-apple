// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension Pin1ProbeTests {
  @Test
  internal func readerThrowingCounterProbeClearsHeldPin1ForThatCardOnly() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-READER-A")
    let otherCard = try Self.serial("SYNTHETIC-READER-B")
    try Self.accept(Self.digits, for: card, in: memory)
    try Self.accept(Self.otherDigits, for: otherCard, in: memory)

    let channel = ProbeChannel([
      (.selectApplication(.fineidApplication), .reply(Self.statusBytes(.success))),
      (.selectElementaryFile(.tokenInfo), .reply(Self.statusBytes(.success))),
      (try Self.readTokenInfoCommand(), .reply(Self.tokenInfoResponse(for: card))),
      (.readRetryCounter(role: .pin1, references: .citizen), .fail(.linkLost)),
    ])

    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeReader(CardOperations(channel: channel), serial: card)
    }
    #expect(channel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))
    #expect(Self.holdsAccepted(memory, for: otherCard))
  }

  @Test
  internal func readerThrowingApplicationSelectAndSerialReadClearHeldPin1AndKeepCandidate() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-READER-A")
    try Self.accept(Self.digits, for: card, in: memory)

    let selectChannel = ProbeChannel([
      (.selectApplication(.fineidApplication), .fail(.linkLost))
    ])

    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeReader(CardOperations(channel: selectChannel), serial: card)
    }
    #expect(selectChannel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))

    try Self.accept(Self.digits, for: card, in: memory)
    let serialChannel = ProbeChannel([
      (.selectApplication(.fineidApplication), .reply(Self.statusBytes(.success))),
      (.selectElementaryFile(.tokenInfo), .fail(.linkLost)),
    ])

    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeReader(CardOperations(channel: serialChannel), serial: card)
    }
    #expect(serialChannel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))

    #expect(memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID()))
    let candidateChannel = ProbeChannel([
      (.selectApplication(.fineidApplication), .fail(.linkLost))
    ])
    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeReader(CardOperations(channel: candidateChannel), serial: card)
    }
    #expect(Self.holdsCandidate(memory, for: card))
  }

  @Test
  internal func readerWrongCardAndFloorRefusalClearHeldPin1() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-READER-A")
    let imposter = try Self.serial("SYNTHETIC-READER-B")
    try Self.accept(Self.digits, for: card, in: memory)

    let wrongCardChannel = ProbeChannel([
      (.selectApplication(.fineidApplication), .reply(Self.statusBytes(.success))),
      (.selectElementaryFile(.tokenInfo), .reply(Self.statusBytes(.success))),
      (try Self.readTokenInfoCommand(), .reply(Self.tokenInfoResponse(for: imposter))),
    ])

    #expect(throws: Pin1Memory.ProbeRefusal.wrongCard) {
      _ = try memory.probeReader(CardOperations(channel: wrongCardChannel), serial: card)
    }
    #expect(wrongCardChannel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))

    try Self.accept(Self.digits, for: card, in: memory)
    let two = try #require(RetryCount(attemptsRemaining: Self.floorRefusalAttempts))
    let floorChannel = ProbeChannel([
      (.selectApplication(.fineidApplication), .reply(Self.statusBytes(.success))),
      (.selectElementaryFile(.tokenInfo), .reply(Self.statusBytes(.success))),
      (try Self.readTokenInfoCommand(), .reply(Self.tokenInfoResponse(for: card))),
      (
        .readRetryCounter(role: .pin1, references: .citizen),
        .reply(Self.statusBytes(.pinIncorrect(remaining: two)))
      ),
    ])

    #expect(throws: Pin1Memory.ProbeRefusal.retryFloor(.refuseLowAttempts, .remaining(two))) {
      _ = try memory.probeReader(CardOperations(channel: floorChannel), serial: card)
    }
    #expect(floorChannel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))
  }

  @Test
  internal func readerPristineProbeKeepsHeldPin1() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-READER-A")
    try Self.accept(Self.digits, for: card, in: memory)
    let pristine = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance))

    let channel = ProbeChannel([
      (.selectApplication(.fineidApplication), .reply(Self.statusBytes(.success))),
      (.selectElementaryFile(.tokenInfo), .reply(Self.statusBytes(.success))),
      (try Self.readTokenInfoCommand(), .reply(Self.tokenInfoResponse(for: card))),
      (
        .readRetryCounter(role: .pin1, references: .citizen),
        .reply(Self.statusBytes(.pinIncorrect(remaining: pristine)))
      ),
    ])

    let outcome = try memory.probeReader(CardOperations(channel: channel), serial: card)
    #expect(outcome == .remaining(pristine))
    #expect(channel.isExhausted)
    #expect(Self.holdsAccepted(memory, for: card))
  }
}
