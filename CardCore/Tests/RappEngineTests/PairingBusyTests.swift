// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 busy answer (section 4.2, PairingBusy Schema and Busy Refusal)")
internal struct PairingBusyTests {
  private static let transports = [RappBleGattProfile.name, streamProfile]
  private static let code = "7KX4M9"

  /// The name the corpus gives a failure to decode a busy answer.
  private static func corpusName(_ error: any Error) -> String {
    switch error {
    case PairingOfferError.retryAfterOutOfRange(let got):
      "RetryAfterOutOfRange { got: \(got) }"

    case PairingOfferError.missingField(let field):
      "MissingField { field: \"\(field)\" }"

    case PairingOfferError.unsupportedVersion:
      "UnsupportedVersion"

    case PairingOfferError.unknownField:
      "UnknownField"

    default:
      "\(error)"
    }
  }

  private static func custodian() throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue), transportProfiles: [streamProfile],
      startedAtMonotonicMs: 0)
  }

  @Test("Busy answers encode and decode to the corpus on both transports")
  internal func busyAnswersReplayTheCorpus() throws {
    let vectors = try CorpusFile.conformance(filePath: #filePath).pairingBusy
    #expect(!vectors.isEmpty)
    for vector in vectors {
      let busy = try PairingBusy(retryAfterMilliseconds: vector.retryAfterMilliseconds)
      let encoded = try Data(hex: vector.encodedHex)
      #expect(try busy.encoded() == encoded, "\(vector.name) bytes")
      #expect(try PairingBusy.decode(encoded) == busy, "\(vector.name) decode")
      for transport in Self.transports {
        guard
          case .busy(let decoded) = try BootstrapAnswer.decode(encoded, transportProfile: transport)
        else {
          Issue.record("\(vector.name) is a busy answer over \(transport)")
          continue
        }
        #expect(decoded == busy, "\(vector.name) over \(transport)")
        #expect(throws: RappBindingError.CustodianBusy) {
          _ = try RappPairingBridge.bootstrapOffer(
            bootstrap: encoded, transportProfile: transport, pairingCode: Self.code,
            startedAtMonotonicMs: 0)
        }
      }
      #expect(try rappPairingBusyRetryAfterMs(encoded) == vector.retryAfterMilliseconds)
    }
  }

  @Test("Malformed busy answers are refused for their stated reason")
  internal func malformedBusyAnswersAreRefused() throws {
    let vectors = try CorpusFile.conformance(filePath: #filePath).rejectedPairingBusy
    #expect(!vectors.isEmpty)
    for vector in vectors {
      let encoded = try Data(hex: vector.encodedHex)
      var reason: String?
      do {
        _ = try PairingBusy.decode(encoded)
      } catch {
        reason = Self.corpusName(error)
      }
      #expect(reason == vector.error, "\(vector.name)")
      #expect(throws: (any Error).self, "\(vector.name)") {
        _ = try BootstrapAnswer.decode(encoded, transportProfile: streamProfile)
      }
      #expect(throws: RappBindingError.InvalidInput, "\(vector.name)") {
        _ = try rappPairingBusyRetryAfterMs(encoded)
      }
    }
  }

  @Test("A custodian's wait is held to the schema's range")
  internal func waitIsHeldToTheRange() throws {
    let least = PairingBusy.minimumRetryAfterMilliseconds
    let greatest = PairingBusy.maximumRetryAfterMilliseconds
    #expect(PairingBusy.untilAdmissible(least - 1).retryAfterMilliseconds == least)
    #expect(PairingBusy.untilAdmissible(greatest + 1).retryAfterMilliseconds == greatest)
    #expect(PairingBusy.untilAdmissible(greatest - 1).retryAfterMilliseconds == greatest - 1)
    #expect(throws: PairingOfferError.retryAfterOutOfRange(least - 1)) {
      _ = try PairingBusy(retryAfterMilliseconds: least - 1)
    }
  }

  @Test("An offer carrying a wait is neither an offer nor a busy answer")
  internal func anOfferCarryingAWaitIsRefused() throws {
    guard
      case .map(var map) = try decodeDeterministicCbor(
        try Self.custodian().bootstrapBytes(nowMonotonicMs: 0))
    else {
      Issue.record("the offer is a map")
      return
    }
    map[PairingBusy.retryAfterField] = .unsigned(PairingBusy.minimumRetryAfterMilliseconds)
    #expect(throws: PairingOfferError.unknownField) {
      _ = try BootstrapAnswer.decode(
        try WireValue.map(map).encoded(), transportProfile: streamProfile)
    }
  }
}
