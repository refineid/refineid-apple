// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.1 BLE segmentation and reassembly (section 5.3)")
internal struct BleSarTests {
  /// The corpus names each violated receive rule.
  private static let errorNames: [String: RappBleSarError] = [
    "att_mtu_too_small": .attMtuTooSmall,
    "invalid_capacity": .invalidCapacity,
    "header_truncated": .headerTruncated,
    "reserved_bits_set": .reservedBitsSet,
    "illegal_flags": .illegalFlags,
    "empty_fragment": .emptyFragment,
    "fragment_over_capacity": .fragmentOverCapacity,
    "sequence_out_of_bounds": .sequenceOutOfBounds,
    "zero_total_length": .zeroTotalLength,
    "unexpected_initial_fragment": .unexpectedInitialFragment,
    "sequence_mismatch": .sequenceMismatch,
    "single_length_mismatch": .singleLengthMismatch,
    "first_fragment_too_short": .firstFragmentTooShort,
    "first_fragment_not_shorter_than_total": .firstFragmentNotShorterThanTotal,
    "illegal_transition": .illegalTransition,
    "total_length_changed": .totalLengthChanged,
    "non_final_fragment_too_short": .nonFinalFragmentTooShort,
    "overflow": .overflow,
    "incomplete_at_last": .incompleteAtLast,
    "reassembly_timeout": .reassemblyTimeout,
  ]

  private static func corpus() throws -> BleSarVectorFile {
    try BleSarVectorFile.load(filePath: #filePath)
  }

  private static func expectedError(_ name: String?) throws -> RappBleSarError {
    try #require(name.flatMap { errorNames[$0] })
  }

  @Test("The corpus is the v26.10.1 SAR corpus with the header and timer the engine uses")
  internal func corpusIdentity() throws {
    let corpus = try Self.corpus()
    #expect(corpus.format == "fi.refineid.rapp.ble-sar-vectors-v1")
    #expect(corpus.protocolDocumentVersion == "26.10.1")
    #expect(corpus.headerSize == RappBleSar.headerSize)
    #expect(corpus.reassemblyTimeoutMs == RappBleSar.reassemblyTimeoutMilliseconds)
  }

  @Test("Payload capacity follows min(mtu - 3, 512) - 6 and the platform limit")
  internal func capacity() throws {
    for vector in try Self.corpus().capacity {
      if let expected = vector.capacity {
        #expect(
          try RappBleSar.payloadCapacity(
            negotiatedAttMtu: vector.negotiatedAttMtu,
            platformValueLimit: vector.platformValueLimit) == expected)
      } else {
        let error = try Self.expectedError(vector.error)
        #expect(throws: error) {
          try RappBleSar.payloadCapacity(
            negotiatedAttMtu: vector.negotiatedAttMtu,
            platformValueLimit: vector.platformValueLimit)
        }
      }
    }
  }

  @Test("Segmentation reproduces every corpus fragment byte for byte")
  internal func segmentation() throws {
    for vector in try Self.corpus().segmentation {
      let fragments = try RappBleSar.segment(
        try Data(hex: vector.messageHex), capacity: vector.capacity)
      #expect(fragments.map(\.hex) == vector.fragmentsHex, "\(vector.name)")
    }
  }

  @Test("Segmented messages reassemble to themselves")
  internal func roundTrip() throws {
    for vector in try Self.corpus().segmentation {
      var machine = RappBleSarReassembler()
      var delivered: [Data] = []
      for fragment in try RappBleSar.segment(
        try Data(hex: vector.messageHex), capacity: vector.capacity)
      {
        if let message = try machine.receive(
          fragment, capacity: vector.capacity, nowMilliseconds: 0)
        {
          delivered.append(message)
        }
      }
      #expect(delivered.map(\.hex) == [vector.messageHex], "\(vector.name)")
      #expect(machine.isIdle)
    }
  }

  @Test("The receive machine accepts and refuses exactly as the corpus states")
  internal func receive() throws {
    for vector in try Self.corpus().receive {
      var machine = RappBleSarReassembler()
      var delivered: [String] = []
      var failure: (RappBleSarError, Int)?
      for (index, fragment) in vector.fragments.enumerated() {
        do {
          if let message = try machine.receive(
            try Data(hex: fragment.hex), capacity: vector.capacity,
            nowMilliseconds: fragment.atMs)
          {
            delivered.append(message.hex)
          }
        } catch let error as RappBleSarError {
          failure = (error, index)
          break
        }
      }
      if vector.error == nil {
        #expect(failure == nil, "\(vector.name)")
        #expect(delivered == vector.messagesHex, "\(vector.name)")
      } else {
        #expect(failure?.0 == (try Self.expectedError(vector.error)), "\(vector.name)")
        #expect(failure?.1 == vector.atFragment, "\(vector.name)")
        #expect(machine.isIdle, "\(vector.name) leaves the machine idle")
      }
    }
  }

  @Test("A running timer refuses the frame without a fragment arriving")
  internal func timerWithoutFragment() throws {
    let message = Data(repeating: 1, count: 600)
    let fragments = try RappBleSar.segment(message, capacity: 503)
    var machine = RappBleSarReassembler()
    #expect(try machine.receive(fragments[0], capacity: 503, nowMilliseconds: 100) == nil)
    try machine.checkTimer(nowMilliseconds: 5_099)
    #expect(throws: RappBleSarError.reassemblyTimeout) {
      try machine.checkTimer(nowMilliseconds: 5_100)
    }
    #expect(machine.isIdle)
  }

  @Test("Segmentation refuses an empty or over-long message and an unusable capacity")
  internal func segmentationLimits() {
    #expect(throws: RappBleSarError.invalidMessageLength) {
      try RappBleSar.segment(Data(), capacity: 503)
    }
    #expect(throws: RappBleSarError.invalidMessageLength) {
      try RappBleSar.segment(
        Data(count: RappBleSar.maximumMessageLength + 1), capacity: 503)
    }
    #expect(throws: RappBleSarError.invalidCapacity) {
      try RappBleSar.segment(Data(count: 10), capacity: RappBleSar.minimumNonFinalPayload - 1)
    }
    #expect(throws: RappBleSarError.invalidCapacity) {
      try RappBleSar.segment(Data(count: 10), capacity: 507)
    }
  }

  @Test("The longest message stays within the sequence bound")
  internal func longestMessage() throws {
    let fragments = try RappBleSar.segment(
      Data(count: RappBleSar.maximumMessageLength), capacity: RappBleSar.minimumNonFinalPayload)
    #expect(fragments.count <= RappBleSar.sequenceLimit)
    var machine = RappBleSarReassembler()
    var delivered: Data?
    for fragment in fragments {
      delivered = try machine.receive(
        fragment, capacity: RappBleSar.minimumNonFinalPayload, nowMilliseconds: 0)
    }
    #expect(delivered?.count == RappBleSar.maximumMessageLength)
  }
}
