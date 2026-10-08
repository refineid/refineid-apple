// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// The pairing code is what the two peers key the CPace PAKE on.
  ///
  /// A coordinator built without a usable code has nothing to agree a
  /// secret on, and must refuse to be built rather than fall back to a
  /// handshake that agrees on no secret at all.
  @Suite("Pairing refuses to start without a code both peers share")
  internal struct RappPairingCodeRequiredTests {
    private func options(code: String, suffix: String) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: code,
        profiles: ["fi.refineid.card-status.v1"],
        candidate: .init(
          profile: "apple-peer-v1",
          candidateID: "candidate-1",
          parametersCBOR: Data([0xA0])
        ),
        displayName: "Peer",
        platform: "macOS",
        vault: makeVault(suffix: suffix),
        transport: discardingTransport()
      )
    }

    @Test(
      "A requester with a malformed code is refused",
      arguments: ["", "1", "12345", "7KU4M9", "      ", "7K#4M9"]
    )
    internal func requesterRefusesMalformedCode(_ code: String) throws {
      #expect(throws: (any Error).self) {
        try RappPairingCoordinator.requester(
          options: options(code: code, suffix: "requester-malformed"))
      }
    }

    @Test(
      "A custodian with a malformed code is refused",
      arguments: ["", "1", "12345", "7KU4M9", "7K#4M9"]
    )
    internal func custodianRefusesMalformedCode(_ code: String) throws {
      #expect(throws: (any Error).self) {
        try RappPairingCoordinator.custodian(
          options: options(code: code, suffix: "custodian-malformed"))
      }
    }

    @Test("An over-long code is refused rather than truncated")
    internal func overLongCodeIsRefused() throws {
      #expect(throws: (any Error).self) {
        try RappPairingCoordinator.requester(
          options: options(code: "2468139", suffix: "requester-truncated"))
      }
    }

    @Test("A code carrying spaces is normalized rather than refused")
    internal func codeIsNormalizedBeforeUse() throws {
      _ = try RappPairingCoordinator.requester(
        options: options(code: "246 813", suffix: "requester-spaced"))
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
