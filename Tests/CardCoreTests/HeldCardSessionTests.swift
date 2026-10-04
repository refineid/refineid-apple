// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Regression tests for `HeldCardSession` verifying race-free activity timeout behavior
/// and coordination between early PACE preparation, idle release, and channel leasing.
@Suite(.serialized)
internal struct HeldCardSessionTests {
  // MARK: Nested Types

  /// A fake held channel wrapping `SyntheticPaceCard` with synchronization hooks.
  internal final class TestHeldCardChannel: HeldCardChannel, @unchecked Sendable {
    private let card: SyntheticPaceCard
    private let lock = NSLock()
    private var ssc: UInt64 = 2

    private var endCount = 0
    internal var onEnd: (@Sendable () -> Void)?

    internal var sessionEndCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return endCount
    }

    internal var isSessionEnded: Bool { sessionEndCount > 0 }
    internal var onFirstTransmit: (@Sendable () -> Void)?

    internal var readChunkLength: ReadChunkLength {
      card.readChunkLength
    }

    internal init(card: SyntheticPaceCard) {
      self.card = card
    }

    internal func transmit(_ payload: Data) throws -> Data {
      let hook: (@Sendable () -> Void)?
      lock.lock()
      hook = onFirstTransmit
      onFirstTransmit = nil
      lock.unlock()
      hook?()

      guard !payload.isEmpty else { return try card.transmit(payload) }

      // Check for secure-messaging CLA (0x0C).
      if payload[0] == 0x0C {
        // Protected SELECT FINEID application: answer with protected 9000.
        guard let keys = card.sessionKeys else { throw SyntheticPaceCard.Rejected() }
        lock.lock()
        let counter = ssc
        ssc += 2
        lock.unlock()

        var sscData = Data(repeating: 0, count: 8)
        var beCounter = counter.bigEndian
        withUnsafeBytes(of: &beCounter) { sscData.append(contentsOf: $0) }

        let statusObject = Data([0x99, 0x02, 0x90, 0x00])
        var macInput = sscData
        macInput.append(statusObject)

        let mac = try AesCmac.secureMessagingTag(
          key: keys.macKey,
          message: SecureMessagingChannel.padded(macInput)
        )
        return statusObject + Data([0x8E, UInt8(mac.count)]) + mac + Data([0x90, 0x00])
      }

      return try card.transmit(payload)
    }

    internal func endSession() {
      lock.lock()
      endCount += 1
      let hook = onEnd
      lock.unlock()
      hook?()
    }
  }

  // MARK: Static Properties

  internal static let validCanString = "123456"
  private static let nonceHex = "00112233445566778899AABBCCDDEEFF"
  private static let firstBlockHex = "0102030405060708090A0B0C0D0E0F10"
  private static let secondBlockHex = "1A2B3C4D5E6F708192A3B4C5D6E7F809"
  private static let thirdBlockHex = "2C3D4E5F60718293A4B5C6D7E8F90A1B"
  private static let fourthBlockHex = "3D4E5F60718293A4B5C6D7E8F90A1B2C"

  // MARK: Static Functions

  private static func scalar(_ hex: String) throws -> U384 {
    guard let value = U384(bigEndianBytes: WireHex.data(hex)) else {
      throw SyntheticPaceCard.Rejected()
    }
    return value
  }

  internal static func makeSyntheticCard() throws -> SyntheticPaceCard {
    SyntheticPaceCard(
      accessNumberDigits: validCanString,
      nonce: WireHex.data(nonceHex),
      mappingScalar: try scalar(thirdBlockHex + fourthBlockHex + firstBlockHex),
      agreementScalar: try scalar(fourthBlockHex + firstBlockHex + secondBlockHex)
    )
  }

  // MARK: Tests

  /// Verifies that activity timeout firing during PACE does not close the session.
  @Test
  internal func testActivityTimeoutFiringDuringPACEDoesNotCloseSession() throws {
    guard let can = CardAccessNumber(digits: Self.validCanString) else {
      Issue.record("Failed to create CardAccessNumber")
      return
    }

    let card = try Self.makeSyntheticCard()
    let testChannel = TestHeldCardChannel(card: card)
    let heldSession = HeldCardSession()

    let paceStartedSemaphore = DispatchSemaphore(value: 0)
    let paceResumeSemaphore = DispatchSemaphore(value: 0)

    testChannel.onFirstTransmit = {
      paceStartedSemaphore.signal()
      paceResumeSemaphore.wait()
    }

    heldSession.retain(testChannel)
    heldSession.startPACE(with: can)

    // Wait until PACE worker has started and is actively in transmit holding operationLock.
    let started = paceStartedSemaphore.wait(timeout: .now() + 5)
    try #require(started == .success, "PACE worker did not start within timeout")

    // The activity timeout fires while PACE is actively in flight.
    heldSession.fireActivityTimeoutForTesting()

    // Assert that the session was NOT terminated mid-PACE.
    #expect(!testChannel.isSessionEnded, "Timeout prematurely ended the session mid-PACE")
    #expect(heldSession.current != nil, "Timeout cleared current channel mid-PACE")
    #expect(heldSession.isAvailable, "Held session reported unavailable mid-PACE")

    // Allow PACE worker to continue and finish PACE.
    paceResumeSemaphore.signal()

    // Lease the prepared channel; must succeed and reuse the prepared channel.
    let lease = try heldSession.preparedChannel(accessNumber: can)
    #expect(!testChannel.isSessionEnded, "Session ended after PACE completed")
    #expect(heldSession.isAvailable)
    _ = lease
  }

  /// Verifies that an unclaimed prepared field is safely released when its activity timeout fires.
  @Test
  internal func testUnclaimedPreparedFieldIsReleasedWhenTimeoutFires() throws {
    guard let can = CardAccessNumber(digits: Self.validCanString) else {
      Issue.record("Failed to create CardAccessNumber")
      return
    }

    let card = try Self.makeSyntheticCard()
    let testChannel = TestHeldCardChannel(card: card)
    let heldSession = HeldCardSession()

    heldSession.retain(testChannel)
    heldSession.startPACE(with: can)

    // Wait until PACE preparation finishes.
    let ready = heldSession.waitForPreparation(timeout: 5)
    try #require(ready, "PACE preparation did not finish within timeout")

    // Channel is prepared, but unclaimed by any signer.
    #expect(!testChannel.isSessionEnded, "Channel ended prematurely before timeout")
    #expect(heldSession.isAvailable)

    // Fire the activity timeout for the unclaimed prepared field.
    heldSession.fireActivityTimeoutForTesting()

    // Assert that the unclaimed prepared field is now released.
    #expect(testChannel.isSessionEnded, "Unclaimed prepared field was not released on timeout")
    #expect(heldSession.current == nil, "Current channel was not cleared after release")
    #expect(!heldSession.isAvailable, "Held session still reports available after release")

    // Attempting to claim the released channel must fail.
    #expect(throws: CardOperationError.self) {
      try heldSession.preparedChannel(accessNumber: can)
    }
  }

  /// Verifies that an unused discovery field is released promptly upon timeout.
  @Test
  internal func testUnusedDiscoveryFieldIsReleasedWhenTimeoutFires() throws {
    let card = try Self.makeSyntheticCard()
    let testChannel = TestHeldCardChannel(card: card)
    let heldSession = HeldCardSession()

    heldSession.retain(testChannel)
    #expect(!testChannel.isSessionEnded)
    #expect(heldSession.isAvailable)

    // Timeout fires on unused discovery field.
    heldSession.fireActivityTimeoutForTesting()

    #expect(testChannel.isSessionEnded, "Unused discovery field was not released on timeout")
    #expect(heldSession.current == nil)
    #expect(!heldSession.isAvailable)
  }

  /// Verifies that an actively claimed lease protects the channel from being ended by timeout.
  @Test
  internal func testClaimedLeaseProtectsSessionFromTimeout() throws {
    guard let can = CardAccessNumber(digits: Self.validCanString) else {
      Issue.record("Failed to create CardAccessNumber")
      return
    }

    let card = try Self.makeSyntheticCard()
    let testChannel = TestHeldCardChannel(card: card)
    let heldSession = HeldCardSession()

    heldSession.retain(testChannel)
    heldSession.startPACE(with: can)

    // Lease the channel.
    let lease = try heldSession.preparedChannel(accessNumber: can)
    #expect(!testChannel.isSessionEnded)

    // Fire timeout while lease is held.
    heldSession.fireActivityTimeoutForTesting()

    #expect(!testChannel.isSessionEnded, "Active lease did not protect session from timeout")
    _ = lease
  }

}
