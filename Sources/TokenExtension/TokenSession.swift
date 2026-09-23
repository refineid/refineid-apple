// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
// swiftlint:disable:previous attributes
import CryptoTokenKit
import Foundation
import Security

/// One session against a published token.
///
/// Advertises the certificate-selected client-authentication shapes the card
/// can sign, prompts for PIN1 through the system UI, and performs a signature.
///
/// The two transports part company at the first line of `sign`, and
/// deliberately so. The contact path is unchanged: a fresh exclusive
/// session, a retry-floor check, VERIFY PIN1 (consumed once, rejection
/// remembered), MSE:SET + PSO:CDS, and the raw card signature normalized
/// for Security.framework. The contactless path has none of that room. It runs
/// inside a field that lasts about two seconds after the mint, so it
/// takes the PIN before it touches the card at all, works in the session
/// the mint held open, reads nothing the prime already knows, and logs
/// nothing - a single diagnostic APDU there was measured costing the
/// whole handshake.
///
/// Provenance: the contactless order is the donor
/// `platform/apple/RefineIDTokenExtension/TokenSession.swift`, whose
/// transport was a Rust FFI relay; here it is CardCore's own PACE,
/// secure messaging and card operations.
internal final class TokenSession: TKSmartCardTokenSession, TKTokenSessionDelegate {
  private static let idPrefixLength = 8

  /// PIN1 collected by the most recent `beginAuth`, consumed by the next
  /// `sign` and cleared immediately after (one prompt = one signature =
  /// one PIN use).
  internal var collectedPin: String?

  /// PIN2 collected by a qualified `beginAuth`, held for a minute.
  ///
  /// The card still verifies PIN2 immediately before every qualified
  /// signature; what this holds is the entry, so a batch of documents
  /// is one prompt rather than one prompt per document. See
  /// ``Pin2Window`` for what that window does and does not do.
  internal var pin2Window = Pin2Window()

  /// Ephemeral session identifier for logging correlation.
  internal let sessionID: String

  /// Installs this session as CryptoTokenKit's operation delegate.
  ///
  /// CryptoTokenKit dispatches key operations only through this weak
  /// delegate. Conformance alone does not install it.
  override internal init(token: TKToken) {
    let sess = "sess-" + UUID().uuidString.prefix(Self.idPrefixLength)
    self.sessionID = String(sess)
    super.init(token: token)
    delegate = self
    let tokenDesc = (token as? Token)?.tokenID ?? "unknown"
    TokenLog.info("TokenSession.init: session=\(sessionID) token=\(tokenDesc)")
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }

  /// The key profile behind one published object ID, or nil for a key
  /// this token did not publish.
  private static func profile(
    for keyObjectID: TKToken.ObjectID,
    of token: Token
  ) -> CardKeyProfile? {
    if (keyObjectID as? String) == Token.signObjectID {
      return token.signKeyProfile
    }
    return token.keyProfile
  }

  internal func tokenSession(
    _: TKTokenSession,
    beginAuthFor operation: TKTokenOperation,
    constraint: Any
  ) throws -> TKTokenAuthOperation {
    guard let cardToken = token as? Token, !cardToken.isRevoked else {
      throw TKError(.tokenNotFound)
    }

    // The constraint names the credential: each published key carries
    // its own, so the qualified key can never be satisfied by a PIN1
    // flow or vice versa.
    switch constraint as? String {
    case Pin2AuthOperation.signDataConstraint:
      TokenLog.notice(
        "beginAuth: op=\(operation.rawValue) - presenting PIN2 sheet "
          + "session=\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"
      )
      return Pin2AuthOperation { [weak self] pin in self?.pin2Window.hold(pin) }

    case Pin1AuthOperation.signDataConstraint:
      return beginPin1Auth(cardToken: cardToken, operation: operation)

    default:
      // Each key names the credential it spends, and a constraint that
      // names neither must not be answered by guessing. Falling through
      // to PIN1 would collect whatever the holder typed for another
      // credential and spend PIN1's attempts on it, which is how a
      // sheet for one PIN blocks the other.
      TokenLog.error(
        "beginAuth: op=\(operation.rawValue) - unknown constraint "
          + "\(String(describing: constraint)); refusing"
      )
      throw TKError(.authenticationFailed)
    }
  }

  private func beginPin1Auth(
    cardToken: Token,
    operation: TKTokenOperation
  ) -> TKTokenAuthOperation {
    let correlationID = "pin-" + UUID().uuidString.prefix(Self.idPrefixLength)
    let instanceID = cardToken.cardInstanceID
    let hasAccepted = VolatileAcceptedPin1.shared.hasPin(for: instanceID)
    let hasPending = TransientCandidatePin1.shared.hasPending(for: instanceID)
    let hasStored = CardCredentialStore.contents().hasPin1
    if hasAccepted || hasPending || hasStored {
      TokenLog.info(
        "beginAuth: op=\(operation.rawValue) correlation=\(correlationID) "
          + "session=\(sessionID) - satisfied from memory"
      )
      return TKTokenAuthOperation()
    }
    if OnDemandPinExperiment.isEnabled, cardToken.interface == .fieldWithDeadline {
      TokenLog.notice(
        "beginAuth: op=\(operation.rawValue) correlation=\(correlationID) "
          + "session=\(sessionID) - presenting PIN sheet"
      )
      // Cancel activity timeout while presenting native PIN sheet so the live
      // session is retained for the signature that follows.
      cardToken.heldSession.cancelActivityTimeout()
      let operationID = UUID()
      return Pin1AuthOperation(
        correlationID: correlationID,
        operationID: operationID,
        capture: { pin in
          let staged = TransientCandidatePin1.shared.stage(
            digits: pin,
            for: instanceID,
            operationID: operationID,
            correlationID: correlationID
          )
          TokenLog.notice("pinAuth: staged candidate correlation=\(correlationID) staged=\(staged)")
        },
        onCancel: { cancelledOpID in
          TransientCandidatePin1.shared.cancel(operationID: cancelledOpID)
          TokenLog.notice("pinAuth: cancelled candidate correlation=\(correlationID)")
        }
      )
    }

    TokenLog.notice(
      "beginAuth: op=\(operation.rawValue) correlation=\(correlationID) session=\(sessionID) - presenting PIN sheet"
    )
    return Pin1AuthOperation(correlationID: correlationID) { [weak self] pin in
      self?.collectedPin = pin
    }
  }

  internal func tokenSession(
    _: TKTokenSession,
    supports operation: TKTokenOperation,
    keyObjectID: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) -> Bool {
    guard let token = token as? Token else {
      TokenLog.error("supports: session token is not a RefineID Token")
      return false
    }
    guard !token.isRevoked else { return false }
    guard let profile = Self.profile(for: keyObjectID, of: token) else {
      return false
    }
    let supported =
      operation == .signData
      && SigningAlgorithmResolver.advertises(algorithm, profile: profile)
    TokenLog.notice(
      "supports: op=\(operation.rawValue) algo=\(SigningAlgorithmResolver.describe(algorithm)) "
        + "profile=\(String(describing: profile)) -> \(supported ? "YES" : "NO")"
    )
    return supported
  }

  /// The signature the system asked for, timed end to end.
  ///
  /// Entry and exit are traced here rather than in the two transport
  /// bodies below, so that every signature costs exactly two lines
  /// whichever way the card was reached, and so that the elapsed time
  /// covers the whole of what Safari waited for. The exchanges in
  /// between arrive from ``SmartCardChannel``.
  internal func tokenSession(
    _: TKTokenSession,
    sign dataToSign: Data,
    keyObjectID: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    let started = ContinuousClock.now
    TokenLog.notice(
      "sign: entry session=\(sessionID) input=\(dataToSign.count)B "
        + "algo=\(SigningAlgorithmResolver.describe(algorithm))"
    )
    do {
      let signature = try signed(
        dataToSign: dataToSign,
        keyObjectID: keyObjectID,
        algorithm: algorithm
      )
      PendingSigningState.shared.clear()
      TokenLog.notice(
        "sign: exit ok session=\(sessionID) out=\(signature.count)B ms=\(Self.elapsed(since: started))"
      )
      return signature
    } catch {
      TokenLog.error(
        "sign: exit failed session=\(sessionID) \(error) ms=\(Self.elapsed(since: started))")
      throw error
    }
  }

  /// Routes one signature to its key, then to the transport the card
  /// was reached over.
  private func signed(
    dataToSign: Data,
    keyObjectID: TKToken.ObjectID,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard let cardToken = token as? Token else {
      throw TKError(.badParameter)
    }
    cardToken.heldSession.cancelActivityTimeout()
    guard !cardToken.isRevoked else {
      throw TKError(.tokenNotFound)
    }
    if (keyObjectID as? String) == Token.signObjectID {
      return try qualifiedThroughReader(
        token: cardToken,
        dataToSign: dataToSign,
        algorithm: algorithm
      )
    }
    // Which interface, not which secrecy: a card on a reader's antenna
    // needs the same PACE channel as one held against a phone, but it can
    // afford everything the contact path does inside that channel --
    // reading the serial, reading the counters, and so reusing a
    // card-bound PIN instead of asking for one per signature.
    TokenLog.trace(
      "sign: interface=\(cardToken.interface) "
        + "held session=\(cardToken.heldSession.current != nil)")
    switch cardToken.interface {
    case .contact, .steadyField:
      return try signThroughReader(
        token: cardToken,
        unsealingWith: cardToken.sealedAccessNumber,
        dataToSign: dataToSign,
        algorithm: algorithm
      )

    case .fieldWithDeadline:
      guard let accessNumber = cardToken.sealedAccessNumber else {
        // Unreachable: this token is only ever minted from a prime, and a
        // prime without a usable number is refused there.
        throw TKError(.authenticationNeeded)
      }
      return try signInField(
        token: cardToken,
        accessNumber: accessNumber,
        dataToSign: dataToSign,
        algorithm: algorithm
      )
    }
  }

  /// The signature taken through a reader, in one exclusive session
  /// opened here.
  ///
  /// With a card access number the card is on the reader's antenna and
  /// the session is unsealed with PACE first; everything after that is
  /// the same flow the contact path runs, because a reader's field lasts
  /// as long as the work does.
  private func signThroughReader(
    token: Token,
    unsealingWith accessNumber: CardAccessNumber?,
    dataToSign: Data,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard
      let request = SigningAlgorithmResolver.resolve(
        algorithm,
        input: dataToSign,
        profile: token.keyProfile
      )
    else {
      TokenLog.error("sign: no matching algorithm - returning badParameter")
      throw TKError(.badParameter)
    }
    // The freshly-entered PIN (from a preceding beginAuth), if any. When
    // nil, performSign may still proceed from card-bound accepted-PIN memory;
    // otherwise it throws authenticationRequired and the system prompts.
    let entered = collectedPin.flatMap { $0.isEmpty ? nil : $0 }
    collectedPin = nil

    // getSmartCard() returns the card but not necessarily inside an open
    // session; open one explicitly (the reference does this on every sign),
    // synchronously - no Swift concurrency on the ctkd thread, which hangs.
    let smartCard = try requestedSmartCard()
    do {
      let signature = try SmartCardChannel(smartCard, waits: .reader).withSession { channel in
        try ReaderSignature.perform(
          in: channel,
          unsealingWith: accessNumber,
          enteredPin: entered,
          request: request,
          token: token
        )
      }
      TokenLog.trace("sign: reader path produced \(signature.count) DER bytes")
      return signature
    } catch let error as TokenError {
      TokenLog.error("sign: failed \(error)")
      throw error.asTKError
    } catch let error as CardOperationError {
      // A raw card error (e.g. a signing SW) must not escape unmapped.
      // Fail as a communication error, not authenticationFailed, so a
      // genuine card-sign failure ends the handshake instead of re-looping
      // the PIN prompt (it is not a wrong PIN).
      TokenLog.error("sign: card failed \(error)")
      throw TKError(.communicationError)
    } catch {
      // A PACE refusal, a secure-messaging fault or a transport timeout
      // must not escape unmapped either: ctkd answers a raw Swift error
      // by re-looping the PIN prompt, and none of these is a wrong PIN.
      TokenLog.error("sign: failed unmapped \(error)")
      throw TKError(.communicationError)
    }
  }

  deinit {
    TokenLog.info("TokenSession.deinit: session=\(sessionID)")
  }
}
