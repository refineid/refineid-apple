// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Observation

  /// The Mac's one switch for remote use (hierarchy specification §5.2,
  /// STPA §27): Bluetooth and local-network discovery, sessions with the
  /// phone, and the phone's identity.
  ///
  /// Off by default, and the choice is kept across restarts. While it is
  /// off nothing remote runs, and the app asks macOS for no local-network or
  /// Bluetooth permission. Turning it on starts the watches whose Bluetooth
  /// manager and first Bonjour browse ask for them (CC-96), and the registry
  /// follows the paired phone; turning it off stops all of it at once and
  /// keeps the pairing (CC-94).
  @MainActor
  @Observable
  internal final class RemoteUseSwitch {
    // MARK: Static Properties

    internal static let shared = RemoteUseSwitch(
      bluetooth: BluetoothReadinessWatch(),
      localNetwork: LocalNetworkPermissionWatch()
    ) {
      PersistentTokenRegistry.shared.remoteUseChanged()
    }

    // MARK: Properties

    /// Whether the holder has remote use on.
    internal private(set) var isOn: Bool

    /// What the Bluetooth watch says blocks remote use.
    internal private(set) var bluetoothBlockage: RemoteUseBlockage?

    /// What the local-network watch says blocks remote use.
    internal private(set) var localNetworkBlockage: RemoteUseBlockage?

    /// The watch whose manager asks for Bluetooth permission.
    @ObservationIgnored internal let bluetoothWatch: any RemoteUseWatch

    /// The watch whose browse asks for local-network permission.
    @ObservationIgnored internal let localNetworkWatch: any RemoteUseWatch

    /// Tells the requester the switch moved.
    @ObservationIgnored private let follow: @MainActor () -> Void

    // MARK: Computed Properties

    /// What blocks remote use while it is on, if anything.
    ///
    /// A refused permission needs the holder in System Settings, so it is
    /// named before Bluetooth that is merely off.
    internal var blockage: RemoteUseBlockage? {
      guard isOn else { return nil }
      return localNetworkBlockage ?? bluetoothBlockage
    }

    // MARK: Lifecycle

    /// A switch on the holder's stored choice, with the two watches and
    /// what follows a change.
    internal init(
      bluetooth: any RemoteUseWatch,
      localNetwork: any RemoteUseWatch,
      follow: @escaping @MainActor () -> Void
    ) {
      isOn = RemoteAccessGate.isEnabled
      bluetoothWatch = bluetooth
      localNetworkWatch = localNetwork
      self.follow = follow
    }

    // MARK: Functions

    /// Starts the watches at launch when the stored choice is on; off, the
    /// launch asks macOS for nothing.
    internal func start() {
      guard isOn else { return }
      startWatches()
    }

    /// Turns remote use the other way, as a click on the switch asks.
    internal func toggle() {
      turn(on: !isOn)
    }

    /// Records the holder's choice and acts on it at once.
    internal func turn(on wanted: Bool) {
      guard wanted != isOn else { return }
      RemoteAccessGate.setEnabled(wanted)
      isOn = wanted
      if wanted {
        startWatches()
      } else {
        stopWatches()
      }
      follow()
    }

    private func startWatches() {
      bluetoothWatch.start { [weak self] blockage in
        self?.bluetoothBlockage = blockage
      }
      localNetworkWatch.start { [weak self] blockage in
        self?.localNetworkBlockage = blockage
      }
    }

    private func stopWatches() {
      bluetoothWatch.stop()
      localNetworkWatch.stop()
      bluetoothBlockage = nil
      localNetworkBlockage = nil
    }
  }

#endif
