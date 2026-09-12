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
  /// PIN1 collected by the most recent `beginAuth`, consumed by the next
  /// `sign` and cleared immediately after (one prompt = one signature =
  /// one PIN use).
  private var collectedPin: String?

  /// PIN2 collected by a qualified `beginAuth`, held for a minute.
  ///
  /// The card still verifies PIN2 immediately before every qualified
  /// signature; what this holds is the entry, so a batch of documents
  /// is one prompt rather than one prompt per document. See
  /// ``Pin2Window`` for what that window does and does not do.
  internal var pin2Window = Pin2Window()

  /// Installs this session as CryptoTokenKit's operation delegate.
  ///
  /// CryptoTokenKit dispatches key operations only through this weak
  /// delegate. Conformance alone does not install it.
  override internal init(token: TKToken) {
    super.init(token: token)
    delegate = self
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
      TokenLog.notice("beginAuth: op=\(operation.rawValue) - presenting PIN sheet")
      return Pin1AuthOperation { [weak self] pin in self?.collectedPin = pin }

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
      "sign: entry input=\(dataToSign.count)B "
        + "algo=\(SigningAlgorithmResolver.describe(algorithm))"
    )
    do {
      let signature = try signed(
        dataToSign: dataToSign,
        keyObjectID: keyObjectID,
        algorithm: algorithm
      )
      TokenLog.notice(
        "sign: exit ok out=\(signature.count)B ms=\(Self.elapsed(since: started))"
      )
      return signature
    } catch {
      TokenLog.error("sign: exit failed \(error) ms=\(Self.elapsed(since: started))")
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

  /// The contactless signature, in the order the field allows.
  ///
  /// That order is the whole of it, and no other order works. Nothing on
  /// this path writes: the lines it takes are recorded in memory and
  /// written out by the exit line in ``tokenSession(_:sign:keyObjectID:algorithm:)``,
  /// because a keychain round trip inside the field is exactly the kind
  /// of cost that was measured losing the handshake.
  private func signInField(
    token: Token,
    accessNumber: CardAccessNumber,
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
      throw TKError(.badParameter)
    }
    // The PIN the system collected through beginAuth, or the one the
    // holder explicitly chose to store for automatic signing. The
    // system-driven path often asks for a signature with no usable PIN
    // interface, so the stored value is what makes Safari independent of
    // the containing app after one-time setup.
    let entered = collectedPin.flatMap { $0.isEmpty ? nil : $0 }
    collectedPin = nil
    let authorized: Pin1?
    let pinSource: String
    if let entered {
      authorized = Pin1(digits: entered)
      pinSource = "prompt"
    } else if let stored = CardCredentialStore.pin1() {
      authorized = consume stored
      pinSource = "stored"
    } else {
      authorized = nil
      pinSource = "none"
    }
    // Which of the two supplied the PIN is the first thing a failed
    // contactless login needs to know, and it is sayable without saying
    // anything about the PIN itself.
    //
    // Taken as a `Bool` first, and not asked inside the trace call:
    // ``TokenLog/trace(_:)`` takes an autoclosure so a shipped build
    // never builds the line, and a closure that borrows the noncopyable
    // `authorized` here makes the compiler report a copy of a
    // noncopyable value at the `consume` above.
    let authorizedPinPresent = authorized != nil
    TokenLog.trace("sign: pin1 source=\(pinSource) authorized=\(authorizedPinPresent)")
    // Ask for the PIN BEFORE touching the card. A contactless token uses
    // its explicitly stored credential rather than the live token's
    // accepted-PIN memory, so a signature with no PIN can
    // only end in this throw - and reaching it after PACE leaves the card
    // mid-secure-channel, where the next PACE attempt dies on SELECT with
    // SW 6999.
    guard let pin1 = authorized else {
      throw TKError(.authenticationNeeded)
    }
    return try performedInField(
      token: token, accessNumber: accessNumber, pin1: pin1, request: request)
  }

  /// Runs the field signature and maps every way it can end.
  private func performedInField(
    token: Token,
    accessNumber: CardAccessNumber,
    pin1: consuming Pin1,
    request: SignRequest
  ) throws -> Data {
    do {
      let signature = FieldSignature(
        token: token,
        accessNumber: accessNumber
      )
      return try signature.perform(pin1: pin1, request: request)
    } catch SmartCardChannel.TransportError.responseTimedOut {
      // A timed-out transmit leaves the card and our secure-messaging
      // counter in an unknowable state. End and forget that held session
      // so the next system attempt starts with a genuinely fresh field.
      token.heldSession.release()
      throw TKError(.communicationError)
    } catch let error as SecureMessagingChannel.Failure {
      // The retained channel is no longer trustworthy and fail-stops, so
      // a retry through it can only fail the same way. Release the hold;
      // the next attempt gets tokenNotFound and a genuinely fresh mint.
      TokenLog.error("sign: secure channel failed \(error)")
      token.heldSession.release()
      throw TKError(.communicationError)
    } catch CardOperationError.sessionUnavailable {
      // The system ended the mint field before Safari asked us to sign.
      // `tokenNotFound` tells CryptoTokenKit that this token instance no
      // longer has a card behind it, so a retry may open a replacement
      // NFC field and mint a fresh instance. Keep every real
      // PACE, APDU and card failure on the communication-error path below.
      TokenLog.trace("sign: retained field unavailable - requesting a fresh token")
      throw TKError(.tokenNotFound)
    } catch let error as TokenError {
      throw error.asTKError
    } catch let error as TKError {
      throw error
    } catch {
      // A PACE refusal, a secure-messaging fault or a signing SW must not
      // escape unmapped, and must not look like a wrong PIN: a genuine
      // card failure ends the handshake instead of re-looping the prompt.
      throw TKError(.communicationError)
    }
  }
}
