// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// The pairing code is what the two peers key the CPace PAKE on.
  ///
  /// An offer carries the identifier derived from the code, not the code,
  /// and a full offer therefore cannot stand in for one. A coordinator
  /// built without a usable code has nothing to agree a secret on, and must
  /// refuse to be built rather than fall back to a handshake that agrees on
  /// no secret at all.
  @Suite("Pairing refuses to start without a code both peers share")
  internal struct RappPairingCodeRequiredTests {
    @Test(
      "A requester with a malformed code is refused",
      arguments: ["", "1", "12345", "7KU4M9", "      ", "7K#4M9"]
    )
    internal func requesterRefusesMalformedCode(_ code: String) throws {
      let options = RappPairingCoordinator.RequesterOptions(
        profiles: ["fi.refineid.card-status.v1"],
        candidates: [
          .init(
            profile: "apple-peer-v1",
            candidateID: "candidate-1",
            parametersCBOR: Data([0xA0])
          )
        ],
        selectedCandidateID: "candidate-1",
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester",
        platform: "macOS",
        vault: makeVault(suffix: "requester-malformed"),
        transport: discardingTransport(),
        code: code
      )
      #expect(throws: (any Error).self) {
        try RappPairingCoordinator.requester(options: options)
      }
    }

    @Test("A proxy with a malformed code is refused")
    internal func proxyRefusesMalformedCode() throws {
      let code = "246813"
      let requesterOptions = RappPairingCoordinator.RequesterOptions(
        profiles: ["fi.refineid.card-status.v1"],
        candidates: [
          .init(
            profile: "apple-peer-v1",
            candidateID: "candidate-1",
            parametersCBOR: Data([0xA0])
          )
        ],
        selectedCandidateID: "candidate-1",
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester",
        platform: "macOS",
        vault: makeVault(suffix: "requester-proxy"),
        transport: discardingTransport(),
        code: code
      )
      let requester = try RappPairingCoordinator.requester(options: requesterOptions)
      let offerURI = try #require(requester.offerURI)

      let proxyOptions = RappPairingCoordinator.ProxyOptions(
        scannedOfferURI: offerURI,
        selectedCandidateID: "candidate-1",
        displayName: "Proxy",
        platform: "iOS",
        vault: makeVault(suffix: "proxy-malformed"),
        transport: discardingTransport(),
        code: "1"
      )
      #expect(throws: (any Error).self) {
        try RappPairingCoordinator.proxy(options: proxyOptions)
      }
    }

    @Test("An over-long code keys the PAKE on its first six digits")
    internal func overLongCodeIsTruncatedToTheCodeLength() throws {
      let requesterOptions = RappPairingCoordinator.RequesterOptions(
        profiles: ["fi.refineid.card-status.v1"],
        candidates: [
          .init(
            profile: "apple-peer-v1",
            candidateID: "candidate-1",
            parametersCBOR: Data([0xA0])
          )
        ],
        selectedCandidateID: "candidate-1",
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester",
        platform: "macOS",
        vault: makeVault(suffix: "requester-truncated"),
        transport: discardingTransport(),
        code: "2468139"
      )
      let requester = try RappPairingCoordinator.requester(options: requesterOptions)
      #expect(requester.offerURI != nil)
    }

    @Test("A code carrying spaces is normalized rather than refused")
    internal func codeIsNormalizedBeforeUse() throws {
      let requesterOptions = RappPairingCoordinator.RequesterOptions(
        profiles: ["fi.refineid.card-status.v1"],
        candidates: [
          .init(
            profile: "apple-peer-v1",
            candidateID: "candidate-1",
            parametersCBOR: Data([0xA0])
          )
        ],
        selectedCandidateID: "candidate-1",
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester",
        platform: "macOS",
        vault: makeVault(suffix: "requester-spaced"),
        transport: discardingTransport(),
        code: "246 813"
      )
      let requester = try RappPairingCoordinator.requester(options: requesterOptions)
      #expect(requester.offerURI != nil)
    }

    /// A transport that discards every frame, for the refusals that never
    /// reach the wire.
    private func discardingTransport() -> RappClosureFrameTransport {
      RappClosureFrameTransport(
        sender: { _ in
          // A refused attempt never reaches the wire.
        },
        closer: {
          // A refused attempt never opens one.
        }
      )
    }

    private func makeVault(suffix: String) -> RappDeviceVault {
      RappDeviceVault(
        accessGroup: nil,
        servicePrefix: "fi.refineid.tests.cpacerequired.\(UUID().uuidString).\(suffix)"
      )
    }
  }
#endif
