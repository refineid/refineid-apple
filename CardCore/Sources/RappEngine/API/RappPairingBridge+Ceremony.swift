// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairingBridge {
  /// Publishes an offer this endpoint will answer as the requester.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when a value is malformed or
  ///   the lifetime exceeds the specification's ceiling.
  public static func createRequesterOffer(  // swiftlint:disable:this function_parameter_count
    offerId: Data,
    pairingSecret: Data,
    profiles: [String],
    transports: [RappTransportCandidate],
    offerTtlMs: UInt64,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let candidates = try transports.map { candidate in
      TransportCandidate(
        profile: candidate.profile,
        candidateIdentifier: candidate.candidateId,
        parameters: try decodedParameters(candidate.parametersCbor))
    }
    let published: PairingOffer
    do {
      published = try PairingOffer(
        offerIdentifier: offerId,
        pairingSecret: pairingSecret,
        suites: [RappNoise.pairingSuite],
        profiles: profiles,
        transports: candidates,
        offerLifetimeMilliseconds: offerTtlMs)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try RappPairingBridge(
      role: .requester, offer: published, startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Answers a scanned offer as the proxy.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when the text is not a valid
  ///   offer.
  public static func fromScannedOffer(
    uri: String,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let scanned: PairingOffer
    do {
      scanned = try PairingOffer.from(uri: uri)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try RappPairingBridge(
      role: .proxy, offer: scanned, startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Names a ceremony failure in the public vocabulary.
  internal static func bindingError(_ error: PairingError) -> RappBindingError {
    switch error {
    case .offerExpired:
      .OfferExpired

    case .candidateNotUnique, .offer, .invalidGrantSet, .unsupportedProfile:
      .InvalidInput

    default:
      .ProtocolFailure
    }
  }

  /// Decodes a candidate's public parameters.
  private static func decodedParameters(_ bytes: Data) throws -> [String: WireValue] {
    guard !bytes.isEmpty else { return [:] }
    guard case .map(let parameters)? = try? decodeDeterministicCbor(bytes) else {
      throw RappBindingError.InvalidInput
    }
    return parameters
  }

  /// The exact text a pairing code must carry.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` once the offer's lifetime has
  ///   elapsed.
  public func offerUri(nowMonotonicMs: UInt64) throws -> String {
    try locked {
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      do {
        return try offer.uri()
      } catch {
        throw RappBindingError.InvalidInput
      }
    }
  }

  /// How long the offer lives, in milliseconds.
  public func offerTtlMs() -> UInt64 {
    locked { offer.offerLifetimeMilliseconds }
  }

  /// The transports the offer advertises.
  public func offerCandidates() -> [RappOfferCandidate] {
    locked {
      offer.transports.map { candidate in
        let bleParams = BleProfile.parameters(of: candidate)
        return RappOfferCandidate(
          profile: candidate.profile,
          candidateId: candidate.candidateIdentifier,
          streamEndpoints: StreamProfile.endpoints(of: candidate),
          bleServiceUUID: bleParams?.serviceUUID,
          blePsm: bleParams?.psm
        )
      }
    }
  }

  /// Starts the handshake over one advertised transport.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` past the deadline,
  ///   ``RappBindingError/WrongPhase`` outside the offer phase, and
  ///   ``RappBindingError/InvalidInput`` for an unknown candidate.
  public func begin(candidateId: String, nowMonotonicMs: UInt64) throws {
    try locked {
      guard case .offer = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      do {
        phase = .handshaking(
          try PairingHandshake.begin(
            .init(
              role: role,
              offer: offer,
              candidateIdentifier: candidateId,
              localKeys: localKeys,
              deadline: deadline,
              nowMilliseconds: nowMonotonicMs)))
      } catch let failure as PairingAttemptFailure {
        throw Self.bindingError(failure.error)
      } catch {
        throw RappBindingError.InvalidInput
      }
    }
  }

  /// The next handshake frame for this role.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the handshake, and
  ///   ``RappBindingError/OfferExpired`` past the deadline.
  public func writeHandshakeFrame(nowMonotonicMs: UInt64) throws -> Data {
    try locked {
      guard case .handshaking(var handshake) = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      defer { phase = .handshaking(handshake) }
      do {
        return try handshake.writeMessage()
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Consumes one handshake frame from the peer.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the handshake,
  ///   ``RappBindingError/OfferExpired`` past the deadline, and
  ///   ``RappBindingError/ProtocolFailure`` when the frame does not verify.
  public func readHandshakeFrame(bytes: Data, nowMonotonicMs: UInt64) throws {
    try locked {
      guard case .handshaking(var handshake) = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      defer { phase = .handshaking(handshake) }
      do {
        try handshake.readMessage(bytes)
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Whether the handshake has finished.
  public func handshakeComplete(nowMonotonicMs _: UInt64) throws -> Bool {
    try locked {
      guard case .handshaking(let handshake) = phase else { throw RappBindingError.WrongPhase }
      return handshake.isComplete
    }
  }

  /// Moves from the handshake to the confirmation exchange.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before the handshake finished,
  ///   and ``RappBindingError/OfferExpired`` past the deadline.
  public func enterConfirmation(nowMonotonicMs: UInt64) throws {
    try locked {
      guard case .handshaking(let handshake) = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      do {
        phase = .confirming(try handshake.intoConfirmation())
      } catch let error as PairingError {
        throw Self.bindingError(error)
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Sends this endpoint's label and its parameter echo.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the confirmation
  ///   exchange.
  public func sendHello(displayName: String, platform: String) throws -> Data {
    try withConfirmation { confirmation in
      try confirmation.sendHello(displayName: displayName, platform: platform)
    }
  }

  /// Verifies the peer's label and parameter echo.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the echo or the
  ///   peer's role does not match.
  public func receiveHello(bytes: Data, nowMs _: UInt64) throws -> RappPeerHello {
    try withConfirmation { confirmation in
      let hello = try confirmation.receiveHello(bytes)
      return RappPeerHello(
        displayName: hello.displayName,
        platform: hello.platform,
        requestedProfiles: hello.requestedProfiles?.map(\.rawValue))
    }
  }

  /// Sends the locally confirmed grant set.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for an unregistered or
  ///   unoffered profile.
  public func sendConfirmation(grantedProfiles: [String]) throws -> Data {
    let granted = try grantedProfiles.map { name in
      guard let profile = ProfileName(rawValue: name) else {
        throw RappBindingError.InvalidInput
      }
      return profile
    }
    return try withConfirmation { confirmation in
      try confirmation.sendConfirmation(grantedProfiles: granted)
    }
  }

  /// Accepts the peer's grant confirmation, which must equal the local one.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the two grant sets
  ///   disagree.
  public func receiveConfirmation(bytes: Data, nowMs _: UInt64) throws -> [String] {
    try withConfirmation { confirmation in
      try confirmation.receiveConfirmation(bytes).map(\.rawValue)
    }
  }

  /// Produces the pairing this ceremony agreed, and spends the bridge.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before both confirmations
  ///   arrived.
  public func finishPairing(createdAtMs: UInt64) throws -> RappPairRecord {
    try locked {
      guard case .confirming(let confirmation) = phase else { throw RappBindingError.WrongPhase }
      do {
        let record = try confirmation.intoPairRecord(createdAtMilliseconds: createdAtMs)
        phase = .finished
        return RappPairRecord(record: record)
      } catch let error as PairingError {
        throw Self.bindingError(error)
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Abandons the ceremony and spends the bridge.
  public func cancelPairing() {
    locked { phase = .cancelled }
  }

  /// Abandons the current candidate, restoring the offer when one may still
  /// be tried.
  ///
  /// - Returns: whether the offer was restored.
  /// - Throws: ``RappBindingError/WrongPhase`` when no candidate is running.
  public func candidateFailed(nowMonotonicMs: UInt64) throws -> Bool {
    try locked {
      switch phase {
      case .handshaking, .cpace:
        guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else { return false }
        phase = .offer
        return true
      default:
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// Runs a confirmation-phase step, writing the mutated confirmation back.
  private func withConfirmation<Value>(
    _ body: (inout PairingConfirmation) throws -> Value
  ) throws -> Value {
    try locked {
      guard case .confirming(var confirmation) = phase else { throw RappBindingError.WrongPhase }
      defer { phase = .confirming(confirmation) }
      do {
        return try body(&confirmation)
      } catch let error as PairingError {
        throw Self.bindingError(error)
      } catch let error as RappBindingError {
        throw error
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }
}
