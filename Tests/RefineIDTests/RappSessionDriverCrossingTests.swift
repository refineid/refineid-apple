// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  @testable import CardCore
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// A close that crosses this endpoint's sent protocol_violation while
  /// it waits for the echo is the echo and its reason is acted on (RAPP
  /// v26.11.8 §7.1 item 7).
  @Suite
  internal struct RappSessionDriverCrossingTests {
    @Test("Own protocol_violation crossed by service_withdrawn drops the identity")
    internal func withdrawalCrossingEndsWithdrawn() {
      let close = RappSessionDriver.closeReason(crossingReceived: .serviceWithdrawn)
      #expect(close == .peerClosed(.serviceWithdrawn))
      #expect(PhoneSessionEnd(.handshake(close)) == .withdrawn)
    }

    @Test("Own protocol_violation crossed by card_unavailable drops the identity")
    internal func cardUnavailableCrossingEndsWithdrawn() {
      let close = RappSessionDriver.closeReason(crossingReceived: .cardUnavailable)
      #expect(close == .peerClosed(.cardUnavailable))
      #expect(PhoneSessionEnd(.handshake(close)) == .withdrawn)
    }

    @Test("Own protocol_violation crossed by pairing_revoked forgets the pairing")
    internal func revocationCrossingEndsRevoked() {
      let close = RappSessionDriver.closeReason(crossingReceived: .pairingRevoked)
      #expect(close == .pairRevoked)
      #expect(PhoneSessionEnd(.handshake(close)) == .pairingRevoked)
    }

    @Test("The echo of the sent protocol_violation ends the violation")
    internal func echoEndsViolation() {
      let close = RappSessionDriver.closeReason(crossingReceived: .protocolViolation)
      #expect(close == .protocolViolation)
      #expect(PhoneSessionEnd(.handshake(close)) == .violation)
    }

    @Test("Any other crossing reason ends as the peer's close")
    internal func otherCrossingEndsAsPeerClosed() {
      let close = RappSessionDriver.closeReason(crossingReceived: .normal)
      #expect(close == .peerClosed(.normal))
      #expect(PhoneSessionEnd(.handshake(close)) == .lost)
    }
  }
#endif
