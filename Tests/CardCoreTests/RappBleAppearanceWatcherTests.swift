// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(CoreBluetooth) && canImport(RappEngine)
  /// What counts as a RAPP peripheral appearing over Bluetooth (RAPP
  /// v26.11.8 §4.6 item 6): the first sighting, or one after the loss hold,
  /// never a sighting while it stays in sight.
  @Suite("RAPP BLE appearance watcher")
  internal struct RappBleAppearanceWatcherTests {
    /// The appearances a watcher reported.
    private final class Appearances: @unchecked Sendable {
      private let lock = NSLock()
      private var seen: [UUID] = []

      var all: [UUID] {
        lock.withLock { seen }
      }

      func record(_ peripheral: UUID) {
        lock.withLock { seen.append(peripheral) }
      }
    }

    /// The gap between two sightings of a peripheral that stays in sight.
    private static let advertisingInterval = Duration.seconds(1)

    @Test("A peripheral that stays in sight appears once")
    internal func stayingInSightAppearsOnce() {
      let appearances = Appearances()
      let watcher = RappBleAppearanceWatcher { appearances.record($0) }
      let phone = UUID()
      var now = ContinuousClock.now
      let sightings = Int(RappBleAppearanceWatcher.lossHoldSeconds) * 2
      for _ in 0..<sightings {
        watcher.sighted(phone, at: now)
        now += Self.advertisingInterval
      }
      #expect(appearances.all == [phone], "no repeated dial while it stays in sight")
    }

    @Test("A peripheral seen again after the loss hold appears again")
    internal func returningAfterTheHoldAppearsAgain() {
      let appearances = Appearances()
      let watcher = RappBleAppearanceWatcher { appearances.record($0) }
      let phone = UUID()
      let first = ContinuousClock.now
      #expect(watcher.sighted(phone, at: first))
      #expect(!watcher.sighted(phone, at: first + RappBleAppearanceWatcher.lossHold - .seconds(1)))
      let back = first + RappBleAppearanceWatcher.lossHold * 2
      #expect(watcher.sighted(phone, at: back))
      #expect(appearances.all == [phone, phone])
    }

    @Test("Each peripheral appears on its own")
    internal func peripheralsAppearApart() {
      let appearances = Appearances()
      let watcher = RappBleAppearanceWatcher { appearances.record($0) }
      let first = UUID()
      let second = UUID()
      let now = ContinuousClock.now
      watcher.sighted(first, at: now)
      watcher.sighted(second, at: now)
      watcher.sighted(first, at: now + Self.advertisingInterval)
      #expect(appearances.all == [first, second])
    }
  }
#endif
