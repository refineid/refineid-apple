// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension Pin1Memory {
  /// Why a pre-VERIFY PIN 1 probe refuses before commanding the card.
  public enum ProbeRefusal: Error, Equatable, Sendable {
    /// A PIN 1 reused from accepted memory meets a counter that no longer
    /// permits holding; the accepted value is dropped and the holder must
    /// be asked.
    case heldPinUnconfirmed(RetryProbeOutcome)

    /// The retry floor refuses the counter; any accepted PIN 1 for this card
    /// is dropped.
    case retryFloor(RetryFloorVerdict, RetryProbeOutcome)

    /// The card in the reader reports another chip serial; the token's
    /// accepted PIN 1 is dropped before reading any counter.
    case wrongCard
  }

  /// Reads the PIN 1 counter in an open contactless field, applies
  /// ``Pin1Retention``, and checks the retry floor and held-PIN admission.
  ///
  /// A failed counter read or a counter that does not permit holding drops
  /// this card's accepted PIN 1 before returning or throwing, while keeping
  /// an unverified candidate staged before the field opened.
  public func probeField(
    _ operations: CardOperations,
    serial: ChipSerial,
    spending: PinAdmission.Spending
  ) throws -> RetryProbeOutcome {
    let probe = try probeCounter(operations, serial: serial)
    let mayHold = Pin1Retention.permitsHolding(after: probe)
    let verdict = RetryFloor.evaluate(probeOutcome: probe)
    guard verdict == .proceed else {
      throw ProbeRefusal.retryFloor(verdict, probe)
    }
    if !mayHold, spending == .heldPin1 {
      throw ProbeRefusal.heldPinUnconfirmed(probe)
    }
    return probe
  }

  /// Selects the FINEID application, confirms `serial`, reads the PIN 1
  /// counter on a reader, applies ``Pin1Retention``, and checks the retry
  /// floor.
  ///
  /// Any failed read, another card's serial, or a counter that does not
  /// permit holding drops this card's accepted PIN 1 before returning or
  /// throwing.
  public func probeReader(
    _ operations: CardOperations,
    serial: ChipSerial
  ) throws -> RetryProbeOutcome {
    let cardSerial: ChipSerial
    do {
      try operations.selectFineidApplication()
      cardSerial = try operations.readChipSerial()
    } catch {
      clearAccepted(serial: serial)
      throw error
    }
    guard cardSerial == serial else {
      clearAccepted(serial: serial)
      throw ProbeRefusal.wrongCard
    }
    let outcome = try probeCounter(operations, serial: serial)
    let verdict = RetryFloor.evaluate(probeOutcome: outcome)
    guard verdict == .proceed else {
      throw ProbeRefusal.retryFloor(verdict, outcome)
    }
    return outcome
  }

  private func probeCounter(
    _ operations: CardOperations,
    serial: ChipSerial
  ) throws -> RetryProbeOutcome {
    let outcome: RetryProbeOutcome
    do {
      outcome = try operations.probeRetryCounter(role: .pin1)
    } catch {
      clearAccepted(serial: serial)
      throw error
    }
    retain(after: outcome, serial: serial)
    return outcome
  }
}
