// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  @preconcurrency import CoreBluetooth
  import Security

  /// Watches this Mac's Bluetooth while remote use is on.
  ///
  /// Creating its manager is what asks macOS for Bluetooth permission, so
  /// none exists while remote use is off (CC-96). Bluetooth switched off or
  /// refused to this app blocks remote use. A build not entitled to
  /// Bluetooth reaches the phone over the stream only, so Bluetooth is no
  /// part of its remote use and nothing is watched.
  @MainActor
  internal final class BluetoothReadinessWatch: NSObject, RemoteUseWatch,
    CBCentralManagerDelegate
  {
    /// The sandbox entitlement that lets an app use Bluetooth.
    private static let bluetoothEntitlement = "com.apple.security.device.bluetooth"

    /// Whether this build's sandbox lets it use Bluetooth.
    private static var entitled: Bool {
      guard let task = SecTaskCreateFromSelf(nil) else { return false }
      let value = SecTaskCopyValueForEntitlement(
        task, bluetoothEntitlement as CFString, nil)
      return value as? Bool ?? false
    }

    // MARK: Properties

    private var manager: CBCentralManager?
    private var report: (@MainActor (RemoteUseBlockage?) -> Void)?

    // MARK: Computed Properties

    internal var isWatching: Bool {
      manager != nil
    }

    // MARK: Static Functions

    /// What a manager in `state` says blocks remote use.
    nonisolated internal static func blockage(for state: CBManagerState) -> RemoteUseBlockage? {
      switch state {
      case .poweredOff:
        .bluetoothOff

      case .unauthorized:
        .bluetoothNotAllowed

      case .poweredOn, .resetting, .unknown, .unsupported:
        nil

      @unknown default:
        nil
      }
    }

    // MARK: Functions

    internal func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void) {
      guard manager == nil, Self.entitled else { return }
      self.report = report
      manager = CBCentralManager(
        delegate: self, queue: .main,
        options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    internal func stop() {
      manager?.delegate = nil
      manager = nil
      report = nil
    }

    nonisolated internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
      let blockage = Self.blockage(for: central.state)
      // The manager calls back on the main queue it was given.
      MainActor.assumeIsolated {
        report?(blockage)
      }
    }
  }

#endif
