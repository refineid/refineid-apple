// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairingBridge {
  /// The next Noise_XXpsk3 handshake message for this role.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the handshake, and
  ///   ``RappBindingError/ProtocolFailure`` past the handshake deadline.
  public func writeHandshakeFrame(nowMonotonicMs: UInt64) throws -> Data {
    try locked {
      guard case .handshaking(var handshake, let limit) = phase else {
        throw RappBindingError.WrongPhase
      }
      try requireBefore(limit, nowMilliseconds: nowMonotonicMs)
      defer { phase = .handshaking(handshake, deadline: limit) }
      do {
        return try handshake.writeMessage()
      } catch {
        phase = .cancelled
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Consumes one Noise_XXpsk3 handshake message from the peer.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the handshake, and
  ///   ``RappBindingError/ProtocolFailure`` when the message does not verify
  ///   or the handshake deadline passed.
  public func readHandshakeFrame(bytes: Data, nowMonotonicMs: UInt64) throws {
    try locked {
      guard case .handshaking(var handshake, let limit) = phase else {
        throw RappBindingError.WrongPhase
      }
      try requireBefore(limit, nowMilliseconds: nowMonotonicMs)
      do {
        try handshake.readMessage(bytes)
        phase = .handshaking(handshake, deadline: limit)
      } catch {
        phase = .cancelled
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Whether the handshake has finished.
  public func handshakeComplete(nowMonotonicMs _: UInt64) throws -> Bool {
    try locked {
      guard case .handshaking(let handshake, _) = phase else { throw RappBindingError.WrongPhase }
      return handshake.isComplete
    }
  }

  /// Moves from the handshake to the authenticated pairing channel.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before the handshake finished.
  public func enterConfirmation(nowMonotonicMs: UInt64) throws {
    try locked {
      guard case .handshaking(let handshake, let limit) = phase else {
        throw RappBindingError.WrongPhase
      }
      try requireBefore(limit, nowMilliseconds: nowMonotonicMs)
      do {
        phase = .confirming(
          try handshake.intoConfirmation(),
          deadline: PairingPhaseDeadline.after(
            nowMonotonicMs, PairingPhaseDeadline.confirmationMilliseconds))
      } catch let failure as PairingAttemptFailure {
        phase = .cancelled
        throw Self.bindingError(failure.error)
      } catch {
        phase = .cancelled
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Sends this endpoint's label and its parameter echo.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the pairing channel.
  public func sendHello(displayName: String, platform: String, nowMonotonicMs: UInt64) throws
    -> Data
  {
    try withConfirmation(nowMilliseconds: nowMonotonicMs) { confirmation in
      try confirmation.sendHello(displayName: displayName, platform: platform)
    }
  }

  /// Verifies the peer's label and parameter echo.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the echo or the
  ///   peer's role does not match.
  public func receiveHello(bytes: Data, nowMonotonicMs: UInt64) throws -> RappPeerHello {
    try withConfirmation(nowMilliseconds: nowMonotonicMs) { confirmation in
      let hello = try confirmation.receiveHello(bytes)
      return RappPeerHello(
        displayName: hello.displayName,
        platform: hello.platform,
        requestedProfiles: hello.requestedProfiles?.map(\.rawValue))
    }
  }

  /// Sends the grant set: the custodian's grant, or the requester's echo.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for an unregistered or
  ///   unoffered profile.
  public func sendConfirmation(grantedProfiles: [String], nowMonotonicMs: UInt64) throws -> Data {
    let granted = try grantedProfiles.map { name in
      guard let profile = ProfileName(rawValue: name) else {
        throw RappBindingError.InvalidInput
      }
      return profile
    }
    return try withConfirmation(nowMilliseconds: nowMonotonicMs) { confirmation in
      try confirmation.sendConfirmation(grantedProfiles: granted)
    }
  }

  /// Accepts the peer's grant set, which must equal any set already sent.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the two grant sets
  ///   disagree.
  public func receiveConfirmation(bytes: Data, nowMonotonicMs: UInt64) throws -> [String] {
    try withConfirmation(nowMilliseconds: nowMonotonicMs) { confirmation in
      try confirmation.receiveConfirmation(bytes).map(\.rawValue)
    }
  }

  /// Produces the pairing this ceremony agreed, and spends the bridge.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before both grant sets
  ///   arrived.
  public func finishPairing(createdAtMs: UInt64, nowMonotonicMs: UInt64) throws -> RappPairRecord {
    try locked {
      guard case .confirming(let confirmation, let limit) = phase else {
        throw RappBindingError.WrongPhase
      }
      try requireBefore(limit, nowMilliseconds: nowMonotonicMs)
      do {
        let record = try confirmation.intoPairRecord(createdAtMilliseconds: createdAtMs)
        phase = .finished
        return RappPairRecord(record: record)
      } catch let error as PairingError {
        phase = .cancelled
        throw Self.bindingError(error)
      } catch {
        phase = .cancelled
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Abandons the ceremony and spends the bridge.
  public func cancelPairing() {
    locked {
      if case .exhausted = phase { return }
      phase = .cancelled
    }
  }

  private func requireBefore(_ limit: UInt64, nowMilliseconds: UInt64) throws {
    guard nowMilliseconds < limit else {
      phase = .cancelled
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Runs a pairing-channel step, writing the mutated confirmation back.
  private func withConfirmation<Value>(
    nowMilliseconds: UInt64,
    _ body: (inout PairingConfirmation) throws -> Value
  ) throws -> Value {
    try locked {
      guard case .confirming(var confirmation, let limit) = phase else {
        throw RappBindingError.WrongPhase
      }
      try requireBefore(limit, nowMilliseconds: nowMilliseconds)
      defer {
        if case .confirming = phase { phase = .confirming(confirmation, deadline: limit) }
      }
      do {
        return try body(&confirmation)
      } catch let error as PairingError {
        phase = .cancelled
        throw Self.bindingError(error)
      } catch let error as RappBindingError {
        throw error
      } catch {
        phase = .cancelled
        throw RappBindingError.ProtocolFailure
      }
    }
  }
}
