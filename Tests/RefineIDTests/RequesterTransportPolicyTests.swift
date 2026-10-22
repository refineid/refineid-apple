// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// Which transport the requester dials, and which advertiser over
/// Bluetooth (RAPP transport hierarchy §3, STPA CC-53, CC-72).
@Suite
internal struct RequesterTransportPolicyTests {
  /// The smallest step of the clock the refusal window runs on.
  private static let tick = Duration.milliseconds(1)

  private static func policy(
    streamInSight: Bool, streamFailed: Bool = false, bluetoothUsable: Bool = true
  ) -> RequesterTransportPolicy {
    RequesterTransportPolicy(
      streamInSight: streamInSight, streamFailedInSight: streamFailed,
      bluetoothUsable: bluetoothUsable)
  }

  @Test("Bonjour showing the phone sends the dial over the stream")
  internal func streamFirst() {
    #expect(Self.policy(streamInSight: true).nextDial == .stream)
  }

  @Test("No Bonjour record sends the dial over Bluetooth")
  internal func bluetoothWithoutBonjour() {
    #expect(Self.policy(streamInSight: false).nextDial == .bluetooth)
  }

  @Test("A stream dial that failed under a lingering record tries Bluetooth next")
  internal func failedStreamFallsBack() {
    #expect(Self.policy(streamInSight: true, streamFailed: true).nextDial == .bluetooth)
  }

  @Test("Without Bluetooth the stream is tried while Bonjour shows the phone, else nothing")
  internal func unusableBluetooth() {
    #expect(
      Self.policy(streamInSight: true, streamFailed: true, bluetoothUsable: false).nextDial
        == .stream)
    #expect(Self.policy(streamInSight: false, bluetoothUsable: false).nextDial == nil)
  }

  @Test("The advertiser that routed is dialed first")
  internal func routedPeerIsPreferred() {
    var peers = RequesterBluetoothPeers()
    let phone = UUID()
    peers.routed(phone)
    let dialing = peers.dialing(at: .now)
    #expect(dialing.preferred == phone)
    #expect(dialing.avoided.isEmpty)
  }

  @Test("A refusing advertiser is passed over for the window, then dialed again")
  internal func refusalLastsTheWindow() {
    var peers = RequesterBluetoothPeers()
    let stranger = UUID()
    let refused = ContinuousClock.now
    peers.refused(stranger, at: refused)
    #expect(
      peers.dialing(at: refused + RequesterBluetoothPeers.refusalWindow - Self.tick).avoided
        == [stranger])
    #expect(peers.dialing(at: refused + RequesterBluetoothPeers.refusalWindow).avoided.isEmpty)
  }

  @Test("The preferred advertiser that refuses is preferred no more")
  internal func refusingPreferredIsDropped() {
    var peers = RequesterBluetoothPeers()
    let phone = UUID()
    let now = ContinuousClock.now
    peers.routed(phone)
    peers.refused(phone, at: now)
    let dialing = peers.dialing(at: now)
    #expect(dialing.preferred == nil)
    #expect(dialing.avoided == [phone])
    peers.routed(phone)
    #expect(peers.dialing(at: now).avoided.isEmpty)
  }
}
