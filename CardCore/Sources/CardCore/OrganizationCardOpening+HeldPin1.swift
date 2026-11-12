// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OrganizationCardOpening {
  /// Why PIN 1 was not sent.
  public enum Pin1Unsettled: Error, Equatable {
    /// No PIN 1 was typed and none is held for this card, or the held one
    /// was dropped because the card's state shows a refusal since it was
    /// accepted: the holder is asked. Nothing after MSE:Set AT was sent.
    case entryRequired

    /// The card refused this PIN before; nothing was sent.
    case knownRejected
  }

  /// What a PIN 1 opening reads and updates: the held PIN 1, the PINs the
  /// card refused, and the token that holds an accepted value.
  public struct Pin1Records {
    /// The held PIN 1 values.
    public let memory: Pin1Memory

    /// The PINs the card refused.
    public let rejected: RejectedPinMemory

    /// The token an accepted value is held for.
    public let owner: Pin1Memory.Owner

    /// Records over `memory`, `rejected` and `owner`.
    public init(memory: Pin1Memory, rejected: RejectedPinMemory, owner: Pin1Memory.Owner) {
      self.memory = memory
      self.rejected = rejected
      self.owner = owner
    }
  }

  /// A channel PIN 1 opened, and for a typed PIN the copy to hold once
  /// the operation succeeds (``Pin1Memory/commit(_:after:)``).
  public struct Pin1Opening {
    /// The opened channel.
    public let opened: Opened

    /// The typed PIN's acceptance; nil when the held PIN opened it.
    public let acceptance: Pin1Memory.Acceptance?
  }

  /// PACE with the PIN 1 an operation spends: `entered` when the holder
  /// typed one, otherwise the PIN 1 held as accepted for `serial`.
  ///
  /// A held PIN 1 is sent only while MSE:Set AT reports no refusal since
  /// the card accepted it (``PinAdmission``); otherwise it is dropped and
  /// nothing further is sent. A PIN the card refuses is dropped at once
  /// (``forget(after:fingerprint:serial:records:)``). Every other failure
  /// is the one ``pin1(over:_:spending:)`` threw.
  public static func pin1(
    over channel: any CardChannel,
    entered: consuming Pin1?,
    serial: ChipSerial,
    records: Pin1Records
  ) throws -> Pin1Opening {
    let pin: Pin1
    let spending: PinAdmission.Spending
    switch consume entered {
    case .some(let typed):
      pin = typed
      spending = .entered

    case .none:
      guard let held = records.memory.checkoutAccepted(serial: serial) else {
        throw Pin1Unsettled.entryRequired
      }
      pin = held
      spending = .heldPin1
    }
    let fingerprint = pin.fingerprint(boundTo: serial)
    guard !records.rejected.isKnownRejected(fingerprint) else {
      throw Pin1Unsettled.knownRejected
    }
    let acceptance =
      spending == .entered
      ? records.memory.acceptance(of: pin, serial: serial, owner: records.owner) : nil
    let opened: Opened
    do {
      opened = try Self.opened(
        over: channel,
        password: PacePassword(pin1: pin.consumeForSingleTransmission(), spending: spending),
        role: .pin1)
    } catch let failure as PaceEstablishment.Failure {
      throw Self.forget(after: failure, fingerprint: fingerprint, serial: serial, records: records)
    } catch {
      records.memory.clearAccepted(serial: serial)
      throw error
    }
    records.memory.retain(after: opened.pinState, serial: serial)
    try opened.operations.selectFineidApplication()
    return Pin1Opening(opened: opened, acceptance: acceptance)
  }

  /// Drops what `failure` shows the card no longer accepts, and returns
  /// the error to throw.
  ///
  /// A state MSE:Set AT reported decides holding (``Pin1Retention``), and
  /// a held PIN it does not admit asks the holder. A wrong PIN (`63CX`) is
  /// recorded as refused and the held value dropped; a blocked PIN, and a
  /// handshake the card fails without a counter (`6300`, or a token
  /// mismatch), drop the held value; any other failed read or handshake
  /// drops the accepted value.
  private static func forget(
    after failure: PaceEstablishment.Failure,
    fingerprint: PinFingerprint,
    serial: ChipSerial,
    records: Pin1Records
  ) -> any Error {
    switch failure {
    case .heldPinUnconfirmed(let state):
      records.memory.retain(after: state, serial: serial)
      return Pin1Unsettled.entryRequired

    case .retryFloorRefused(_, let state):
      records.memory.retain(after: state, serial: serial)

    case .wrongPin:
      records.rejected.recordRejection(fingerprint)
      records.memory.clear(serial: serial)

    case .credentialBlocked, .cardRejected(.authenticationFailed), .authenticationTokenMismatch:
      records.memory.clear(serial: serial)

    default:
      records.memory.clearAccepted(serial: serial)
    }
    return failure
  }
}
