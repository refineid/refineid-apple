// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A deterministic identity card used by demonstrations and automated tests.
///
/// The virtual card models card state separately from device state. Card
/// mutations therefore change the same retry counters and factory flags that a
/// physical card changes, while setup changes only the simulated device. No
/// global switch lives in CardCore: a caller must explicitly construct and
/// retain an instance.
public actor VirtualIDCard {
  internal var current: Snapshot

  internal var activationRequired: Bool {
    current.card.pin1.isFactoryValue || current.card.pin2.isFactoryValue
  }

  internal var activationEntryDigitCount: Int {
    current.card.activationScheme.activationEntryDigitCount
  }

  /// Creates a card preset to the given scenario.
  public init(scenario: Scenario = .factoryFreshNearField) {
    current = scenario.snapshot
  }

  /// Creates a card holding exactly the given snapshot.
  public init(snapshot: Snapshot) {
    current = snapshot
  }

  /// Reads the current snapshot without changing anything.
  public func inspect() -> Snapshot {
    current
  }

  /// Replaces the entire snapshot, queued faults included.
  public func replace(with snapshot: Snapshot) {
    current = snapshot
  }

  /// Discards all state and starts over from the scenario's snapshot.
  public func reset(to scenario: Scenario) {
    current = scenario.snapshot
  }

  /// Queues a fault to fire on its next matching operation.
  public func enqueue(_ fault: Fault) {
    current.faults.append(fault)
  }

  /// Discards every queued fault.
  public func clearFaults() {
    current.faults = []
  }

  /// Restores the simulated device to a fresh state, leaving the card as is.
  public func forgetDeviceState() {
    current.device = DeviceState()
  }

  /// Opens a connection, checking the CAN on the near-field transport.
  ///
  /// A successful near-field connection to an activated card also stores
  /// the CAN on the device.
  public func connect(cardAccessNumber: String) -> ConnectionResult {
    if let failure = reachabilityFailure() {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(failure)
    }
    if let fault = consumeFault(for: .connect, phase: .beforeCommand) {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(fault)
    }
    if current.card.transport == .nearField,
      !digitsAreValid(
        cardAccessNumber,
        within: CardAccessNumber.digitCount...CardAccessNumber.digitCount)
        || cardAccessNumber != current.card.cardAccessNumber
    {
      current.device.connectedCardAccessNumber = nil
      return .incorrectCardAccessNumber
    }
    current.device.connectedCardAccessNumber =
      current.card.transport == .nearField
      ? current.card.cardAccessNumber
      : nil
    if let fault = consumeFault(for: .connect, phase: .afterCardExecution) {
      current.device.connectedCardAccessNumber = nil
      return .unavailable(fault)
    }
    if current.card.transport == .nearField, !activationRequired {
      current.device.storedCardAccessNumber = current.card.cardAccessNumber
    }
    return .connected(current)
  }

  /// Reads the three retry counters without spending an attempt.
  public func probeCredentials() -> ProbeResult {
    if let failure = operationFailure() {
      return .unavailable(failure)
    }
    if let fault = consumeFault(for: .probeCredentials, phase: .beforeCommand) {
      return fault == .malformedResponse ? .unreadable : .unavailable(fault)
    }
    let report = RetryReport(
      pin1: current.card.pin1.attemptsRemaining,
      pin2: current.card.pin2.attemptsRemaining,
      puk: current.card.puk.attemptsRemaining)
    if let fault = consumeFault(
      for: .probeCredentials,
      phase: .afterCardExecution)
    {
      return fault == .malformedResponse ? .unreadable : .unavailable(fault)
    }
    return .report(report)
  }

  /// Changes PIN 1 after verifying the current PIN 1.
  public func changePIN1(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin1,
      operation: .changePIN1,
      current: entered,
      new: new)
  }

  /// Changes PIN 2 after verifying the current PIN 2.
  public func changePIN2(current entered: String, new: String) -> MutationResult {
    change(
      role: .pin2,
      operation: .changePIN2,
      current: entered,
      new: new)
  }

  /// Sets a new PIN 1 after verifying the PUK.
  public func resetPIN1(puk: String, new: String) -> MutationResult {
    reset(role: .pin1, operation: .resetPIN1, puk: puk, new: new)
  }

  /// Sets a new PIN 2 after verifying the PUK.
  public func resetPIN2(puk: String, new: String) -> MutationResult {
    reset(role: .pin2, operation: .resetPIN2, puk: puk, new: new)
  }

}
