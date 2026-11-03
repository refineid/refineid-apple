// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The phone's statements at the end of a session are told apart from a
  /// lost connection, and only a loss waits a back-off before the next dial
  /// (RAPP v26.11.2 §4.5 item 6, §4.6 item 4).
  @MainActor
  @Suite(.serialized)
  internal struct PhoneSessionEndTests {
    @Test("A withdrawal close, in session or in place of ready, is a withdrawal")
    internal func withdrawalIsItsOwnEnd() {
      #expect(PhoneSessionEnd(.operation(.serviceWithdrawn)) == .withdrawn)
      #expect(PhoneSessionEnd(.handshake(.peerClosed(.serviceWithdrawn))) == .withdrawn)
    }

    @Test("A revocation close is a revocation, and a delivered notice its own end")
    internal func revocationIsItsOwnEnd() {
      #expect(PhoneSessionEnd(.operation(.pairRevoked)) == .pairingRevoked)
      #expect(PhoneSessionEnd(.handshake(.pairRevoked)) == .pairingRevoked)
      #expect(
        PhoneSessionEnd(.handshake(.revocationNoticeDelivered)) == .revocationNoticeDelivered)
    }

    @Test("A card_unavailable close drops the identity as a withdrawal does")
    internal func cardUnavailableIsAWithdrawal() {
      #expect(PhoneSessionEnd(.operation(.peerClosed(.cardUnavailable))) == .withdrawn)
      #expect(PhoneSessionEnd(.handshake(.peerClosed(.cardUnavailable))) == .withdrawn)
    }

    @Test("A protocol violation, sent or received, is its own end and no loss")
    internal func violationIsItsOwnEnd() {
      #expect(PhoneSessionEnd(.operation(.protocolViolation)) == .violation)
      #expect(PhoneSessionEnd(.operation(.peerClosed(.protocolViolation))) == .violation)
      #expect(PhoneSessionEnd(.handshake(.protocolViolation)) == .violation)
      #expect(PhoneSessionEnd(.handshake(.peerClosed(.protocolViolation))) == .violation)
      #expect(PhoneSessionEnd(.handshake(.protocolFailure)) == .lost)
    }

    @Test("A lost transport, a local close and an ordinary close are losses")
    internal func everythingElseIsALoss() {
      #expect(PhoneSessionEnd(.transportFailure) == .lost)
      #expect(PhoneSessionEnd(.operation(.transportClosed)) == .lost)
      #expect(PhoneSessionEnd(.localRequest) == .lost)
      #expect(PhoneSessionEnd(.operation(.peerClosed(.normal))) == .lost)
    }

    @Test("The phone's withdrawal takes its identity at once and leaves no back-off")
    internal func withdrawalLeavesTheNextDialToTheAnnouncement() {
      let registry = PersistentTokenRegistry.shared
      let wasEnabled = RemoteAccessGate.isEnabled
      RemoteAccessGate.setEnabled(false)
      defer {
        RemoteAccessGate.setEnabled(wasEnabled)
        registry.holderIsAdvertising = false
        registry.holderRecordListed = false
        registry.sessionSlot = RequesterSessionSlot()
      }
      registry.holderIsAdvertising = true
      registry.holderRecordListed = true
      registry.certificateDER = Data(repeating: 1, count: 3)
      registry.sessionSlot = RequesterSessionSlot()
      let now = ContinuousClock.now
      let dialled = registry.sessionSlot.dial(over: .stream, at: now)
      #expect(dialled)
      registry.sessionSlot.established()
      registry.sessionSlot.released()

      registry.holderWithdrew()

      #expect(registry.certificateDER == nil)
      #expect(!registry.holderIsAdvertising)
      #expect(!registry.transportPolicy.streamInSight)
      #expect(registry.sessionSlot.nextDialAt == nil)
      #expect(registry.sessionSlot.mayDial(at: now))
    }

    @Test("A lost session waits the back-off; a withdrawal does not")
    internal func onlyALossWaits() {
      let now = ContinuousClock.now
      var lost = RequesterSessionSlot()
      let lostDialled = lost.dial(over: .stream, at: now)
      #expect(lostDialled)
      lost.established()
      lost.ended(at: now)
      #expect(!lost.mayDial(at: now))

      var withdrawn = RequesterSessionSlot()
      let withdrawnDialled = withdrawn.dial(over: .stream, at: now)
      #expect(withdrawnDialled)
      withdrawn.established()
      withdrawn.released()
      #expect(withdrawn.mayDial(at: now))
    }

    @Test("The phone's announcement after a withdrawal is dialled over the stream")
    internal func announcementPicksTheStream() {
      var policy = RequesterTransportPolicy()
      policy.remoteUseOn = true
      policy.streamInSight = false
      policy.bluetoothUsable = false
      #expect(policy.nextDial == nil, "withdrawn and no Bluetooth: nothing to dial")
      policy.streamInSight = true
      #expect(policy.nextDial == .stream)
    }
  }
#endif
