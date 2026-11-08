// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// Scans passively for RAPP BLE peripherals and reports each appearance
  /// (RAPP v26.11.2 §4.5 item 6, §4.6 item 6; hierarchy specification §3).
  ///
  /// The advertisement carries only the RAPP service UUID, so an appearance
  /// names a peripheral, not a pairing: the owner dials it with the pairing
  /// it means and the peripheral's routing says whether it holds it. A
  /// peripheral appears when it is first seen, or seen again after
  /// ``lossHold`` without a sighting; sightings while it stays in sight are
  /// not appearances. The watcher connects to nothing itself.
  public final class RappBleAppearanceWatcher: NSObject, @unchecked Sendable {
    /// Seconds without a sighting after which a peripheral counts as gone,
    /// so its next sighting is an appearance.
    public static let lossHoldSeconds: Int64 = 30

    /// ``lossHoldSeconds`` as a duration.
    public static let lossHold = Duration.seconds(lossHoldSeconds)

    private let onAppeared: @Sendable (UUID) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.ble-appearance")
    private var manager: CBCentralManager?
    private var lastSeen: [UUID: ContinuousClock.Instant] = [:]
    internal private(set) var cancelled = false

    /// Reports each peripheral that appears through `onAppeared`, on the
    /// watcher's queue.
    @preconcurrency
    public init(onAppeared: @escaping @Sendable (UUID) -> Void) {
      self.onAppeared = onAppeared
      super.init()
    }

    /// Starts scanning once Bluetooth is powered on.
    public func start() {
      queue.async { [weak self] in
        guard let self, !cancelled, manager == nil else { return }
        manager = CBCentralManager(
          delegate: self, queue: queue,
          options: [CBCentralManagerOptionShowPowerAlertKey: false])
      }
    }

    /// Stops scanning and forgets what was in sight.
    public func cancel() {
      queue.async { [weak self] in
        guard let self else { return }
        cancelled = true
        manager?.stopScan()
        manager?.delegate = nil
        manager = nil
        lastSeen = [:]
      }
    }

    /// One sighting of `peripheral` at `now`: reports it when it is an
    /// appearance, and answers whether it was.
    @discardableResult
    internal func sighted(_ peripheral: UUID, at now: ContinuousClock.Instant) -> Bool {
      let appeared = lastSeen[peripheral].map { seen in now - seen >= Self.lossHold } ?? true
      lastSeen[peripheral] = now
      if appeared {
        onAppeared(peripheral)
      }
      return appeared
    }
  }
#endif
