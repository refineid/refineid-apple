// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Observation

/// The requester's one switch for remote use, which is the pairing
/// (hierarchy specification §5.2, STPA §29): Bluetooth and local-network
/// discovery, sessions with the phone, and the phone's identity.
///
/// Each launch restores it on only while an active pairing remains after the
/// idle-expiry sweep, and off otherwise (CC-101). While it is off nothing
/// remote runs, and the app asks the platform for no local-network or
/// Bluetooth permission. The holder's click turning it on starts the watches
/// whose Bluetooth manager and first browse ask for them (CC-96), and the
/// requester follows the paired phone or offers the code entry. The holder's
/// click turning it off forgets every pairing (RAPP v26.11.8 §4.6 item 6,
/// CC-100). It also turns off, keeping the pairings as they are, as the app
/// quits; a pairing that ends otherwise leaves it on. A card in the
/// requester's reader suspends it: the switch keeps its state and its watches
/// stop until the card leaves (CC-102).
///
/// The watches, the stored choice and what follows a move all come in
/// through interfaces, so the decision core runs against test doubles.
@preconcurrency
@MainActor
@Observable
public final class RemoteUseSwitch {
  // MARK: Nested Types

  /// What the requester does as the switch moves.
  public enum Move: Equatable, Sendable {
    /// The holder turned remote use off: forget every pairing.
    case forgetting

    /// Remote use stopped without the holder's click, the pairings kept as
    /// they are: the app quits, or a click off could not finish.
    case stopped

    /// The holder turned remote use on: follow the paired phone, or offer
    /// the code entry.
    case turnedOn
  }

  // MARK: Properties

  /// Whether remote use is on.
  public private(set) var isOn: Bool

  /// Whether a card in the requester's reader suspends remote use.
  public private(set) var isSuspended = false

  /// What the Bluetooth watch says blocks remote use.
  public private(set) var bluetoothBlockage: RemoteUseBlockage?

  /// What the local-network watch says blocks remote use.
  public private(set) var localNetworkBlockage: RemoteUseBlockage?

  /// The watch whose manager asks for Bluetooth permission.
  @ObservationIgnored public let bluetoothWatch: any RemoteUseWatch

  /// The watch whose browse asks for local-network permission.
  @ObservationIgnored public let localNetworkWatch: any RemoteUseWatch

  /// Where the holder's choice is read and recorded.
  @ObservationIgnored private let setting: any RemoteUseSetting

  /// Tells the requester how the switch moved.
  @ObservationIgnored private let follow: any RemoteUseFollowing

  /// Whether the launch has decided remote use; before it, a suspension that
  /// ends starts nothing.
  @ObservationIgnored private var hasStarted = false

  /// Whether the holder clicked the switch before the launch decided: the
  /// click stands.
  @ObservationIgnored private var holderClickedFirst = false

  // MARK: Computed Properties

  /// What blocks remote use while it is on, if anything.
  ///
  /// A refused permission needs the holder in System Settings, so it is
  /// named before Bluetooth that is merely off.
  public var blockage: RemoteUseBlockage? {
    guard isOn else { return nil }
    return localNetworkBlockage ?? bluetoothBlockage
  }

  // MARK: Lifecycle

  /// A switch with the two watches, the stored choice and what follows a
  /// move.
  @preconcurrency
  public init(
    bluetooth: any RemoteUseWatch,
    localNetwork: any RemoteUseWatch,
    setting: any RemoteUseSetting,
    follow: any RemoteUseFollowing
  ) {
    isOn = setting.isEnabled
    bluetoothWatch = bluetooth
    localNetworkWatch = localNetwork
    self.setting = setting
    self.follow = follow
  }

  // MARK: Functions

  /// Restores remote use at launch: on while `pairingRemains`, an active
  /// pairing left after the launch's idle-expiry sweep, and off otherwise;
  /// suspended while `suspended`, a card in the requester's reader.
  ///
  /// A launch that restores it on, unsuspended, starts the watches without
  /// the holder's click; the platform granted their permissions when the
  /// holder turned remote use on and paired (CC-101). Suspended, nothing
  /// starts until the card leaves (CC-102). A click the holder made before
  /// the launch decided stands.
  public func start(pairingRemains: Bool, suspended: Bool) {
    hasStarted = true
    guard !holderClickedFirst else {
      suspend(suspended)
      return
    }
    setting.setEnabled(pairingRemains)
    isOn = pairingRemains
    isSuspended = suspended
    if pairingRemains, !suspended {
      startWatches()
    }
  }

  /// Keeps remote use off until the launch decides it, so nothing remote runs
  /// before the pairings are swept and the readers looked at.
  public func holdUntilLaunched() {
    setting.setEnabled(false)
    isOn = false
  }

  /// A card in the requester's reader arrived, `suspended`, or left: the
  /// watches stop while it is there and run again once it leaves, while
  /// remote use is on.
  public func suspend(_ suspended: Bool) {
    guard suspended != isSuspended else { return }
    isSuspended = suspended
    guard hasStarted, isOn else { return }
    if suspended {
      stopWatches()
    } else {
      startWatches()
    }
  }

  /// The holder's click: on turns remote use on, off forgets every pairing.
  public func toggle() {
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
  public func stop() {
    move(on: false, as: .stopped)
  }

  /// The app is active again, perhaps back from the settings where the holder
  /// allowed the local network: a refusal the watch reported is asked afresh,
  /// and stands until the new browse answers.
  public func recheckLocalNetwork() {
    guard isOn, !isSuspended, localNetworkBlockage != nil else { return }
    localNetworkWatch.stop()
    localNetworkWatch.start { [weak self] blockage in
      self?.localNetworkBlockage = blockage
    }
  }

  private func move(on wanted: Bool, as move: Move) {
    guard wanted != isOn else { return }
    setting.setEnabled(wanted)
    isOn = wanted
    if !isSuspended {
      if wanted {
        startWatches()
      } else {
        stopWatches()
      }
    }
    follow.remoteUseChanged(move)
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
