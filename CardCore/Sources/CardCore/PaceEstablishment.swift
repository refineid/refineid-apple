// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// `id-PACE-ECDH-GM-AES-CBC-CMAC-256` (BSI TR-03110-3 section A.5, ICAO
/// Doc 9303 Part 11 section 4.4) with a ``PacePassword``, over the
/// standardized domain parameter the card's EF.CardAccess lists: the FINEID
/// card's contactless door.
///
/// A run first reads EF.CardAccess and takes the generic-mapping suite over
/// the most preferred listed domain (``CardAccess/genericMappingSuite``).
/// MSE:Set AT then names the suite, the password and the curve; four
/// GENERAL AUTHENTICATE rounds run the protocol. Round one returns a nonce
/// encrypted under a key derived from the password, so only a terminal
/// that knows the password learns `s`. Round two exchanges ephemeral public
/// points and the generic mapping turns them into a fresh generator
/// `G' = s*G + H`, where `H` is the ordinary ECDH point of that exchange.
/// Round three is a second ephemeral exchange, this time on `G'`, whose
/// shared point's x-coordinate is the PACE shared secret. Round four
/// exchanges authentication tokens: each side MACs the point the other
/// sent, so neither uses the session until it has evidence the other
/// derived the same keys. Only the last round clears the command-chaining
/// bit.
///
/// A failed run with the card access number consumes no counter, so a
/// wrong CAN is a recoverable user error. A PIN is different: the
/// organization card takes one of the PIN's tries at the first GENERAL
/// AUTHENTICATE and gives it back only when the handshake completes, so a
/// handshake abandoned after that command costs a try (observed on
/// hardware, refineid-core `doc/reference/pace.md`). MSE:Set AT answers
/// with the PIN's state before any try is spent (BSI TR-03110-3 section
/// B.14.1), and the retry floor decides on that answer before the first
/// GENERAL AUTHENTICATE is sent.
///
/// What comes out is ``Established``: the session keys, and for a PIN the
/// state MSE:Set AT reported. Turning the keys into a channel is
/// `SecureMessagingChannel`'s job, and it is the only thing they are good
/// for.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`; the password, the suite
/// choice, the nonce length and the retry floor follow the refineid-core
/// `crates/pace` handshake.
public struct PaceEstablishment {
  /// What a completed run yields.
  public struct Established: Sendable {
    /// The secure-messaging session keys.
    public let keys: PaceSessionKeys

    /// The PIN's state as MSE:Set AT reported it before the handshake.
    ///
    /// Nil for the card access number. The handshake completed, so the
    /// card returned the try it took; this is the reading the retry floor
    /// and PIN 1 retention decide on.
    public let pinState: RetryProbeOutcome?
  }

  /// Why a PACE run was abandoned.
  ///
  /// Every case is terminal for the attempt: no round can be retried on the
  /// same session, because each one consumes the card's protocol state.
  public enum Failure: Error, Equatable {
    /// The card's authentication token did not match the one derived from
    /// this side's keys. The two sides hold different keys; the session is
    /// abandoned, never retried on these keys.
    case authenticationTokenMismatch

    /// The card answered a PACE command with something other than success.
    case cardRejected(StatusWord)

    /// EF.CardAccess could not be selected or read.
    case cardAccessUnreadable

    /// EF.CardAccess did not parse.
    case cardAccessMalformed(CardAccess.Failure)

    /// EF.CardAccess lists no generic-mapping AES-256 suite over a domain
    /// parameter this build runs; nothing was sent after the read.
    case noSupportedSuite

    /// The retry floor refused the PIN on MSE:Set AT's answer; nothing was
    /// sent after it. The reading the floor judged is carried.
    case retryFloorRefused(RetryFloorVerdict, RetryProbeOutcome)

    /// The card reports the PIN password deactivated (BSI TR-03110-3
    /// section B.14.1); nothing was sent after MSE:Set AT.
    case passwordDeactivated

    /// The card refused the handshake with a PIN password and reports the
    /// tries left (BSI TR-03110-3 section B.14.2): a wrong PIN.
    case wrongPin(remaining: RetryCount)

    /// A response was not the dynamic authentication data the round
    /// expects, or a command could not be encoded within the short form.
    case malformedResponse

    /// The card answered with the terminal's own ephemeral public point
    /// (ICAO Doc 9303 Part 11 section 4.4.1, step 4 d).
    case reflectedPoint

    /// A point the protocol requires to be finite was the point at
    /// infinity, so it has neither an encoding nor an x-coordinate.
    case unusablePoint
  }

  /// The transport this run drives.
  internal let channel: any CardChannel

  /// Where the phases of a run are reported, in development builds.
  internal let diagnostic: (@Sendable (String) -> Void)?

  /// Where the two ephemeral private scalars come from.
  internal let scalarSource: PaceEphemeralScalarSource

  /// A run over `channel` using the platform CSPRNG for its scalars.
  @preconcurrency
  public init(
    channel: any CardChannel, diagnostic: (@Sendable (String) -> Void)? = nil
  ) {
    self.diagnostic = diagnostic
    self.channel = channel
    self.scalarSource = .secureRandom
  }

  /// A run over `channel` drawing its scalars from `scalarSource`.
  ///
  /// Only tests pass anything but `.secureRandom`.
  public init(channel: any CardChannel, scalarSource: PaceEphemeralScalarSource) {
    self.channel = channel
    self.scalarSource = scalarSource
    self.diagnostic = nil
  }

  /// Runs PACE with `password` over the suite EF.CardAccess names.
  ///
  /// The card must accept commands at master-file level, where the read
  /// of EF.CardAccess leaves it; a FINEID card refuses MSE:Set AT from an
  /// application context.
  public func establish(with password: borrowing PacePassword) throws -> Established {
    let cardAccess = try readCardAccess()
    guard let suite = cardAccess.genericMappingSuite else {
      throw Failure.noSupportedSuite
    }
    return try establish(with: password, suite: suite)
  }

  /// Runs PACE with `password` over `suite`.
  public func establish(
    with password: borrowing PacePassword,
    suite: PaceInfo
  ) throws -> Established {
    switch suite.domain {
    case .nistP384:
      try run(NistP384.self, suite: suite, password: password)

    case .brainpoolP384r1:
      try run(BrainpoolP384r1.self, suite: suite, password: password)

    case .nistP256:
      try run(NistP256.self, suite: suite, password: password)
    }
  }

  /// EF.CardAccess, its unreadability told apart from a dead link.
  ///
  /// A transport failure passes through as itself, because a card that
  /// stopped answering is not a card without a suite.
  private func readCardAccess() throws -> CardAccess {
    do {
      return try CardOperations(channel: channel).readCardAccess()
    } catch let failure as CardAccess.Failure {
      throw Failure.cardAccessMalformed(failure)
    } catch CardOperationError.sessionUnavailable {
      throw CardOperationError.sessionUnavailable
    } catch CardOperationError.exchangeUnanswered {
      throw CardOperationError.exchangeUnanswered
    } catch let failure as CardOperationError {
      diagnostic?("PACE EF.CardAccess unreadable: \(failure)")
      throw Failure.cardAccessUnreadable
    }
  }

  /// The whole handshake over `Curve`.
  private func run<Curve: PaceCurve>(
    _: Curve.Type,
    suite: PaceInfo,
    password: borrowing PacePassword
  ) throws -> Established {
    let started = ContinuousClock.now
    let pinState = try setAuthenticationTemplate(suite: suite, password: password)
    let nonce = try recoverNonce(with: password)
    reportPhase("nonce", since: started)

    let mappingScalar = nextScalar(Curve.self)
    let terminalMappingPoint = Curve.multiplyGenerator(by: mappingScalar)
    let cardMappingPoint: CurvePoint<Curve> = try exchange(
      terminalMappingPoint,
      terminalTag: PaceValues.mappingDataTerminalTag,
      cardTag: PaceValues.mappingDataCardTag,
      password: password
    )
    let mappedGenerator = Curve.multiplyGenerator(
      by: U384.reduced(bigEndian: nonce, modulo: Curve.order)
    )
    .adding(Curve.multiply(cardMappingPoint, by: mappingScalar))
    reportPhase("mapping", since: started)

    let agreementScalar = nextScalar(Curve.self)
    let terminalPublicKey = Curve.multiply(mappedGenerator, by: agreementScalar)
    let cardPublicKey: CurvePoint<Curve> = try exchange(
      terminalPublicKey,
      terminalTag: PaceValues.ephemeralPublicKeyTerminalTag,
      cardTag: PaceValues.ephemeralPublicKeyCardTag,
      password: password
    )
    let keys = try Self.sessionKeys(
      sharedSecret: Curve.multiply(cardPublicKey, by: agreementScalar)
    )
    reportPhase("agreement", since: started)

    try confirm(
      keys: keys,
      suite: suite,
      terminalPublicKey: terminalPublicKey,
      cardPublicKey: cardPublicKey,
      password: password
    )
    reportPhase("confirmation", since: started)
    return Established(keys: keys, pinState: pinState)
  }
}
