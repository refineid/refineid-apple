// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Observation

  /// The Mac's one switch for remote use, which is the pairing (hierarchy
  /// specification §5.2, STPA §29): Bluetooth and local-network discovery,
  /// sessions with the phone, and the phone's identity.
  ///
  /// Each launch restores it on only while an active pairing remains after
  /// the idle-expiry sweep, and off otherwise (CC-101). While it is off
  /// nothing remote runs, and the app asks macOS for no local-network or
  /// Bluetooth permission. The holder's click turning it on starts the
  /// watches whose Bluetooth manager and first Bonjour browse ask for them
  /// (CC-96), and the registry follows the paired phone or offers the code
  /// entry. The holder's click turning it off forgets every pairing (RAPP
  /// v26.10.29 §4.6 item 6, CC-100). It also turns off, keeping the
  /// pairings as they are, when the last pairing ends other than by that
  /// click and as the app quits. A card in this Mac's reader suspends it:
  /// the switch keeps its state and its watches stop until the card leaves
  /// (CC-102).
  @MainActor
  @Observable
  internal final class RemoteUseSwitch {
    // MARK: Nested Types

    /// What the requester does as the switch moves.
    internal enum Move: Equatable, Sendable {
      /// The holder turned remote use off: forget every pairing.
      case forgetting

      /// Remote use stopped without the holder's click, the pairings kept
      /// as they are: the last one ended otherwise, or the app quits.
      case stopped

      /// The holder turned remote use on: follow the paired phone, or
      /// offer the code entry.
      case turnedOn
    }

    // MARK: Static Properties

    internal static let shared = RemoteUseSwitch(
      bluetooth: BluetoothReadinessWatch(),
      localNetwork: LocalNetworkPermissionWatch()
    ) { move in
      PersistentTokenRegistry.shared.remoteUseChanged(move)
    }

    // MARK: Properties

    /// Whether remote use is on.
    internal private(set) var isOn: Bool

    /// Whether a card in this Mac's reader suspends remote use.
    internal private(set) var isSuspended = false

    /// What the Bluetooth watch says blocks remote use.
    internal private(set) var bluetoothBlockage: RemoteUseBlockage?

    /// What the local-network watch says blocks remote use.
    internal private(set) var localNetworkBlockage: RemoteUseBlockage?

    /// The watch whose manager asks for Bluetooth permission.
    @ObservationIgnored internal let bluetoothWatch: any RemoteUseWatch

    /// The watch whose browse asks for local-network permission.
    @ObservationIgnored internal let localNetworkWatch: any RemoteUseWatch

    /// Tells the requester how the switch moved.
    @ObservationIgnored private let follow: @MainActor (Move) -> Void

    /// Whether the launch has decided remote use; before it, a suspension
    /// that ends starts nothing.
    @ObservationIgnored private var hasStarted = false

    /// Whether the holder clicked the switch before the launch decided:
    /// the click stands.
    @ObservationIgnored private var holderClickedFirst = false

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

    /// A switch with the two watches and what follows a move.
    internal init(
      bluetooth: any RemoteUseWatch,
      localNetwork: any RemoteUseWatch,
      follow: @escaping @MainActor (Move) -> Void
    ) {
      isOn = RemoteAccessGate.isEnabled
      bluetoothWatch = bluetooth
      localNetworkWatch = localNetwork
      self.follow = follow
    }

    // MARK: Functions

    /// Restores remote use at launch: on while `pairingRemains`, an active
    /// pairing left after the launch's idle-expiry sweep, and off otherwise;
    /// suspended while `suspended`, a card in this Mac's reader.
    ///
    /// A launch that restores it on, unsuspended, starts the watches without
    /// the holder's click; macOS granted their permissions when the holder
    /// turned remote use on and paired (CC-101). Suspended, nothing starts
    /// until the card leaves (CC-102). A click the holder made before the
    /// launch decided stands.
    internal func start(pairingRemains: Bool, suspended: Bool) {
      hasStarted = true
      guard !holderClickedFirst else {
        suspend(suspended)
        return
      }
      RemoteAccessGate.setEnabled(pairingRemains)
      isOn = pairingRemains
      isSuspended = suspended
      if pairingRemains, !suspended {
        startWatches()
      }
    }

    /// Keeps remote use off until the launch decides it, so nothing remote
    /// runs before the pairings are swept and the readers looked at.
    internal func holdUntilLaunched() {
      RemoteAccessGate.setEnabled(false)
      isOn = false
    }

    /// A card in this Mac's reader arrived, `suspended`, or left: the
    /// watches stop while it is there and run again once it leaves, while
    /// remote use is on.
    internal func suspend(_ suspended: Bool) {
      guard suspended != isSuspended else { return }
      isSuspended = suspended
      guard hasStarted, isOn else { return }
      if suspended {
        stopWatches()
      } else {
        startWatches()
      }
    }

    /// The holder's click: on turns remote use on, off forgets every
    /// pairing.
    internal func toggle() {
      if !hasStarted {
        holderClickedFirst = true
      }
      if isOn {
        move(on: false, as: .forgetting)
      } else {
        move(on: true, as: .turnedOn)
      }
    }

    /// Turns remote use off, keeping the pairings as they are: the last one
    /// ended other than by the holder's click, or the app quits.
    internal func stop() {
      move(on: false, as: .stopped)
    }

    /// The app is active again, perhaps back from the settings where the
    /// holder allowed the local network: a refusal the watch reported is
    /// asked afresh, and stands until the new browse answers.
    internal func recheckLocalNetwork() {
      guard isOn, !isSuspended, localNetworkBlockage != nil else { return }
      localNetworkWatch.stop()
      localNetworkWatch.start { [weak self] blockage in
        self?.localNetworkBlockage = blockage
      }
    }

    private func move(on wanted: Bool, as move: Move) {
      guard wanted != isOn else { return }
      RemoteAccessGate.setEnabled(wanted)
      isOn = wanted
      if !isSuspended {
        if wanted {
          startWatches()
        } else {
          stopWatches()
        }
      }
      follow(move)
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
