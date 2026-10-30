// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct RejectedPinMemoryTests {
  @Test
  internal func rememberedRejectionIsFound() throws {
    let memory = RejectedPinMemory()
    let serial = try #require(ChipSerial(value: "9990000001"))
    guard let pin = Pin1(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let fingerprint = pin.fingerprint(boundTo: serial)

    #expect(!memory.isKnownRejected(fingerprint))
    memory.recordRejection(fingerprint)
    #expect(memory.isKnownRejected(fingerprint))
  }

  @Test
  internal func rejectionOnOneCardDoesNotBlockAnother() throws {
    let memory = RejectedPinMemory()
    let cardA = try #require(ChipSerial(value: "9990000001"))
    let cardB = try #require(ChipSerial(value: "9990000002"))
    guard let pin = Pin1(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }

    memory.recordRejection(pin.fingerprint(boundTo: cardA))
    #expect(!memory.isKnownRejected(pin.fingerprint(boundTo: cardB)))
  }

  @Test
  internal func differentPinOnSameCardIsUnaffected() throws {
    let memory = RejectedPinMemory()
    let serial = try #require(ChipSerial(value: "9990000001"))
    guard
      let wrongPin = Pin1(digits: "111111"),
      let otherPin = Pin1(digits: "222222")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }

    memory.recordRejection(wrongPin.fingerprint(boundTo: serial))
    #expect(!memory.isKnownRejected(otherPin.fingerprint(boundTo: serial)))
  }

  @Test
  internal func reenteringTheSameWrongPinIsCaughtByAFreshValue() throws {
    // The scenario the memory exists for: the user re-types the exact
    // wrong PIN. The new entry is a fresh Pin1 value, but its fingerprint
    // matches the recorded rejection, so no second attempt is burned.
    let memory = RejectedPinMemory()
    let serial = try #require(ChipSerial(value: "9990000001"))
    guard
      let firstEntry = Pin1(digits: "123456"),
      let reentered = Pin1(digits: "123456")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    memory.recordRejection(firstEntry.fingerprint(boundTo: serial))

    #expect(memory.isKnownRejected(reentered.fingerprint(boundTo: serial)))
  }

  @Test
  internal func concurrentRecordingIsSafe() async throws {
    let memory = RejectedPinMemory()
    let serial = try #require(ChipSerial(value: "9990000001"))
    let workerCount = 64

    await withTaskGroup(of: Void.self) { group in
      for worker in 0..<workerCount {
        group.addTask {
          let digits = String(repeating: "\(worker % 10)", count: 6)
          guard let pin = Pin1(digits: digits) else { return }
          memory.recordRejection(pin.fingerprint(boundTo: serial))
        }
      }
    }

    guard let checkPin = Pin1(digits: "333333") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    #expect(memory.isKnownRejected(checkPin.fingerprint(boundTo: serial)))
  }
}
