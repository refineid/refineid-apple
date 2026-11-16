// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import RappRequester
import Testing

/// The remote-use switch's decision core against recording watches and a
/// recording choice: restoration at launch, the holder's click, the
/// suspension a card makes, and what blocks remote use (hierarchy
/// specification §5.2, STPA CC-95, CC-101, CC-102).
@Suite
@MainActor
internal struct RemoteUseSwitchDecisionTests {
  /// A watch that records what the switch asks of it, and reports what a
  /// test says it found.
  internal final class RecordingWatch: RemoteUseWatch {
    internal private(set) var starts = 0
    internal private(set) var stops = 0
    private var report: (@MainActor (RemoteUseBlockage?) -> Void)?

    internal var isWatching: Bool {
      report != nil
    }

    internal func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void) {
      starts += 1
      self.report = report
    }

    internal func stop() {
      stops += 1
      report = nil
    }

    internal func found(_ blockage: RemoteUseBlockage?) {
      report?(blockage)
    }
  }

  /// The holder's choice, kept in memory for the test.
  internal final class RecordingSetting: RemoteUseSetting {
    internal var isEnabled = false
    internal private(set) var writes: [Bool] = []

    internal func setEnabled(_ enabled: Bool) {
      isEnabled = enabled
      writes.append(enabled)
    }
  }

  /// The moves the switch reported to the requester.
  internal final class Moves {
    internal var value: [RemoteUseSwitch.Move] = []
  }

  /// A switch on recording watches and a recording choice.
  internal struct Rig {
    internal let remoteUse: RemoteUseSwitch
    internal let bluetooth: RecordingWatch
    internal let localNetwork: RecordingWatch
    internal let setting: RecordingSetting
    internal let moves: Moves
  }

  /// A switch whose stored choice starts `isOn`.
  internal static func rig(isOn: Bool) -> Rig {
    let bluetooth = RecordingWatch()
    let localNetwork = RecordingWatch()
    let setting = RecordingSetting()
    setting.isEnabled = isOn
    let moves = Moves()
    let remoteUse = RemoteUseSwitch(
      bluetooth: bluetooth,
      localNetwork: localNetwork,
      setting: setting
    ) { move in
      moves.value.append(move)
    }
    return Rig(
      remoteUse: remoteUse, bluetooth: bluetooth, localNetwork: localNetwork, setting: setting,
      moves: moves)
  }

  @Test
  internal func aLaunchWithoutAPairingStartsOffAndWatchesNothing() {
    let rig = Self.rig(isOn: true)
    rig.remoteUse.start(pairingRemains: false, suspended: false)

    #expect(!rig.remoteUse.isOn)
    #expect(!rig.setting.isEnabled)
    #expect(rig.bluetooth.starts == 0)
    #expect(rig.localNetwork.starts == 0)
    #expect(rig.moves.value.isEmpty)
  }

  @Test
  internal func aLaunchWithAPairingRestoresItOnWithoutAClick() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)

    #expect(rig.remoteUse.isOn)
    #expect(rig.setting.isEnabled)
    #expect(rig.bluetooth.starts == 1)
    #expect(rig.localNetwork.starts == 1)
    #expect(rig.moves.value.isEmpty)
  }

  @Test
  internal func holdingUntilLaunchKeepsRemoteUseOff() {
    let rig = Self.rig(isOn: true)
    rig.remoteUse.holdUntilLaunched()

    #expect(!rig.remoteUse.isOn)
    #expect(!rig.setting.isEnabled)
    #expect(rig.bluetooth.starts == 0)
  }

  @Test
  internal func theHoldersClickOnStartsTheWatches() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: false, suspended: false)
    rig.remoteUse.toggle()

    #expect(rig.remoteUse.isOn)
    #expect(rig.setting.isEnabled)
    #expect(rig.bluetooth.starts == 1)
    #expect(rig.localNetwork.starts == 1)
    #expect(rig.moves.value == [.turnedOn])
  }

  @Test
  internal func theHoldersClickOffForgetsThePairings() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)
    rig.remoteUse.toggle()

    #expect(!rig.remoteUse.isOn)
    #expect(!rig.setting.isEnabled)
    #expect(rig.bluetooth.stops == 1)
    #expect(rig.localNetwork.stops == 1)
    #expect(rig.moves.value == [.forgetting])
  }

  @Test
  internal func stoppingKeepsThePairings() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)
    rig.remoteUse.stop()

    #expect(!rig.remoteUse.isOn)
    #expect(rig.moves.value == [.stopped])
  }

  @Test
  internal func aClickBeforeTheLaunchDecidesStands() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.toggle()
    rig.remoteUse.start(pairingRemains: false, suspended: false)

    #expect(rig.remoteUse.isOn)
  }

  @Test
  internal func aCardInTheReaderStopsTheWatchesUntilItLeaves() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)
    rig.remoteUse.suspend(true)

    #expect(rig.remoteUse.isSuspended)
    #expect(rig.bluetooth.stops == 1)
    #expect(rig.localNetwork.stops == 1)

    rig.remoteUse.suspend(false)

    #expect(!rig.remoteUse.isSuspended)
    #expect(rig.bluetooth.starts == 2)
    #expect(rig.localNetwork.starts == 2)
    #expect(rig.remoteUse.isOn)
  }

  @Test
  internal func aSuspensionWhileOffStartsNothingWhenItEnds() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.suspend(true)
    rig.remoteUse.suspend(false)

    #expect(rig.bluetooth.starts == 0)
    #expect(rig.localNetwork.starts == 0)
  }

  @Test
  internal func aRefusedPermissionIsNamedBeforeBluetoothThatIsOff() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)
    rig.bluetooth.found(.bluetoothOff)

    #expect(rig.remoteUse.blockage == .bluetoothOff)

    rig.localNetwork.found(.localNetworkNotAllowed)

    #expect(rig.remoteUse.blockage == .localNetworkNotAllowed)

    rig.localNetwork.found(nil)

    #expect(rig.remoteUse.blockage == .bluetoothOff)
  }

  @Test
  internal func nothingBlocksWhileRemoteUseIsOff() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: false, suspended: false)

    #expect(rig.remoteUse.blockage == nil)
  }

  @Test
  internal func recheckingTheLocalNetworkAsksOnlyWhileItIsRefused() {
    let rig = Self.rig(isOn: false)
    rig.remoteUse.start(pairingRemains: true, suspended: false)
    rig.remoteUse.recheckLocalNetwork()

    #expect(rig.localNetwork.stops == 0)
    #expect(rig.localNetwork.starts == 1)

    rig.localNetwork.found(.localNetworkNotAllowed)
    rig.remoteUse.recheckLocalNetwork()

    #expect(rig.localNetwork.stops == 1)
    #expect(rig.localNetwork.starts == 2)
  }
}
