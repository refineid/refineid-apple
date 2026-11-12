// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Pre-VERIFY PIN 1 probing on the field and reader paths: a counter read
/// that throws destroys the held PIN 1 for that card just as an unreadable
/// or spent counter does, while preserving another card's value and any
/// unverified candidate staged before the field opened.
@Suite
internal struct Pin1ProbeTests {
  internal struct InvalidFixturePin: Error {}

  internal enum Step {
    case fail(TransportFailure)
    case reply(Data)
  }

  internal enum TransportFailure: Error, Equatable {
    case linkLost
  }

  internal final class ProbeChannel: CardChannel {
    private var steps: [(expected: Data, step: Step)]

    internal var readChunkLength: ReadChunkLength {
      .plain
    }

    internal var isExhausted: Bool {
      steps.isEmpty
    }

    internal init(_ steps: [(CommandApdu, Step)]) {
      self.steps = steps.map { command, step in
        (expected: command.encoded, step: step)
      }
    }

    internal func transmit(_ payload: Data) throws -> Data {
      guard let next = steps.first, next.expected == payload else {
        Issue.record("unexpected transmit of \(payload.count) bytes")
        throw TransportFailure.linkLost
      }
      steps.removeFirst()
      switch next.step {
      case .fail(let failure):
        throw failure

      case .reply(let response):
        return response
      }
    }
  }

  internal static let digits = "1234"
  internal static let otherDigits = "654321"
  internal static let statusHighByteShift = 8
  internal static let floorRefusalAttempts: UInt8 = 2

  internal static func serial(_ value: String) throws -> ChipSerial {
    try #require(ChipSerial(value: value))
  }

  internal static func pin(_ value: String) throws -> Pin1 {
    guard let constructed = Pin1(digits: value) else {
      throw InvalidFixturePin()
    }
    return constructed
  }

  internal static func statusBytes(_ statusWord: StatusWord) -> Data {
    let encoded = statusWord.encoded
    return Data([
      UInt8(truncatingIfNeeded: encoded >> Self.statusHighByteShift),
      UInt8(truncatingIfNeeded: encoded),
    ])
  }

  internal static func tokenInfoResponse(for serial: ChipSerial) -> Data {
    let serialBytes = Data(serial.value.utf8)
    let versionTlv = Data([Iso7816Values.derIntegerTag, 1, 0])
    var serialTlv = Data([Iso7816Values.derOctetStringTag, UInt8(serialBytes.count)])
    serialTlv.append(serialBytes)
    let body = versionTlv + serialTlv
    var outer = Data([Iso7816Values.derSequenceTag, UInt8(body.count)])
    outer.append(body)
    outer.append(statusBytes(.success))
    return outer
  }

  internal static func readTokenInfoCommand() throws -> CommandApdu {
    let offset = try #require(ReadOffset(value: 0))
    let expected = try #require(ExpectedResponseLength(count: ReadChunkLength.plain.count))
    return .readBinary(offset: offset, expectedLength: expected)
  }

  internal static func accept(
    _ value: String,
    for card: ChipSerial,
    in memory: Pin1Memory
  ) throws {
    let constructed = try pin(value)
    let rawAcceptance = memory.acceptance(
      of: constructed,
      serial: card,
      after: .verified,
      owner: Pin1Memory.Owner()
    )
    let acceptance = try #require(rawAcceptance)
    memory.commit(acceptance)
  }

  internal static func holdsAccepted(_ memory: Pin1Memory, for card: ChipSerial) -> Bool {
    guard let held = memory.checkoutAccepted(serial: card) else { return false }
    _ = held
    return true
  }

  internal static func holdsCandidate(_ memory: Pin1Memory, for card: ChipSerial) -> Bool {
    guard let staged = memory.checkoutCandidate(serial: card) else { return false }
    _ = staged
    return true
  }

  @Test
  internal func fieldThrowingProbeClearsHeldPin1ForThatCardOnly() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-FIELD-A")
    let otherCard = try Self.serial("SYNTHETIC-FIELD-B")
    try Self.accept(Self.digits, for: card, in: memory)
    try Self.accept(Self.otherDigits, for: otherCard, in: memory)

    let channel = ProbeChannel([
      (.readRetryCounter(role: .pin1, references: .citizen), .fail(.linkLost))
    ])

    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeField(
        CardOperations(channel: channel),
        serial: card,
        spending: .heldPin1
      )
    }
    #expect(channel.isExhausted)
    #expect(!Self.holdsAccepted(memory, for: card))
    #expect(Self.holdsAccepted(memory, for: otherCard))
  }

  @Test
  internal func fieldThrowingProbeKeepsUnverifiedCandidate() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-FIELD-A")
    #expect(memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID()))

    let channel = ProbeChannel([
      (.readRetryCounter(role: .pin1, references: .citizen), .fail(.linkLost))
    ])

    #expect(throws: TransportFailure.linkLost) {
      _ = try memory.probeField(
        CardOperations(channel: channel),
        serial: card,
        spending: .entered
      )
    }
    #expect(channel.isExhausted)
    #expect(Self.holdsCandidate(memory, for: card))
  }

  @Test
  internal func fieldSpentAndFloorProbesClearHeldPin1AndRefuseAppropriately() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-FIELD-A")
    try Self.accept(Self.digits, for: card, in: memory)
    let four = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance - 1))

    let spentChannel = ProbeChannel([
      (
        .readRetryCounter(role: .pin1, references: .citizen),
        .reply(Self.statusBytes(.pinIncorrect(remaining: four)))
      )
    ])

    #expect(throws: Pin1Memory.ProbeRefusal.heldPinUnconfirmed(.remaining(four))) {
      _ = try memory.probeField(
        CardOperations(channel: spentChannel),
        serial: card,
        spending: .heldPin1
      )
    }
    #expect(!Self.holdsAccepted(memory, for: card))

    try Self.accept(Self.digits, for: card, in: memory)
    let two = try #require(RetryCount(attemptsRemaining: Self.floorRefusalAttempts))
    let floorChannel = ProbeChannel([
      (
        .readRetryCounter(role: .pin1, references: .citizen),
        .reply(Self.statusBytes(.pinIncorrect(remaining: two)))
      )
    ])

    #expect(throws: Pin1Memory.ProbeRefusal.retryFloor(.refuseLowAttempts, .remaining(two))) {
      _ = try memory.probeField(
        CardOperations(channel: floorChannel),
        serial: card,
        spending: .entered
      )
    }
    #expect(!Self.holdsAccepted(memory, for: card))
  }

  @Test
  internal func fieldPristineProbeKeepsHeldPin1() throws {
    let memory = Pin1Memory()
    let card = try Self.serial("SYNTHETIC-FIELD-A")
    try Self.accept(Self.digits, for: card, in: memory)
    let pristine = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance))

    let channel = ProbeChannel([
      (
        .readRetryCounter(role: .pin1, references: .citizen),
        .reply(Self.statusBytes(.pinIncorrect(remaining: pristine)))
      )
    ])

    let outcome = try memory.probeField(
      CardOperations(channel: channel),
      serial: card,
      spending: .heldPin1
    )
    #expect(outcome == .remaining(pristine))
    #expect(channel.isExhausted)
    #expect(Self.holdsAccepted(memory, for: card))
  }
}
