// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
// swiftlint:disable:previous attributes
import CryptoTokenKit
import Foundation

extension TokenSession {
  private static let heldSessionWaitSeconds: TimeInterval = 3

  /// The contactless signature, in the order the field allows.
  ///
  /// That order is the whole of it, and no other order works. Nothing on
  /// this path writes: the lines it takes are recorded in memory and
  /// written out by the exit line in ``tokenSession(_:sign:keyObjectID:algorithm:)``,
  /// because a keychain round trip inside the field is exactly the kind
  /// of cost that was measured losing the handshake.
  internal func signInField(
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

    // The first on-demand token publishes its identity without opening PACE.
    // Resolve the missing PIN first so CryptoTokenKit can show its secure sheet.
    // The next sign call then requests a fresh field with the entered PIN ready.
    let pin1 = try resolveAuthorizedPin(token: token)

    // The user may have spent longer than the system field allows in the PIN
    // sheet, or the field was released early during certificate selection.
    // A replacement token will take a new field and prepare PACE.
    guard token.heldSession.waitForAvailable(timeout: Self.heldSessionWaitSeconds) else {
      TokenLog.notice(
        "sign: retained field unavailable before verify (released or expired) - tokenNotFound session=\(sessionID)"
      )
      throw TKError(.tokenNotFound)
    }

    return try performedInField(
      token: token, accessNumber: accessNumber, pin1: pin1, request: request
    )
  }

  private func resolveAuthorizedPin(token: Token) throws -> Pin1 {
    if let accepted = VolatileAcceptedPin1.shared.checkout(for: token.cardInstanceID) {
      TokenLog.trace(
        "sign: session=\(sessionID) token=\(token.tokenID) pin1 source=accepted authorized=true"
      )
      return accepted
    }
    if let candidate = TransientCandidatePin1.shared.checkout(for: token.cardInstanceID) {
      TokenLog.trace(
        "sign: session=\(sessionID) token=\(token.tokenID) pin1 source=candidate authorized=true"
      )
      return candidate
    }
    if let stored = CardCredentialStore.pin1() {
      TokenLog.trace(
        "sign: session=\(sessionID) token=\(token.tokenID) pin1 source=stored authorized=true"
      )
      return stored
    }
    let entered = collectedPin.flatMap { $0.isEmpty ? nil : $0 }
    collectedPin = nil
    if let entered, let pin = Pin1(digits: entered) {
      TokenLog.trace(
        "sign: session=\(sessionID) token=\(token.tokenID) pin1 source=prompt authorized=true"
      )
      return pin
    }
    TokenLog.trace(
      "sign: session=\(sessionID) token=\(token.tokenID) pin1 source=none authorized=false"
    )
    throw TKError(.authenticationNeeded)
  }

  /// Runs the field signature and maps every way it can end.
  internal func performedInField(
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
      // counter in an unknowable state (card moved away from antenna).
      // Release held session and request fresh card scan via tokenNotFound.
      TokenLog.notice(
        "sign: transport timed out - requesting card scan via tokenNotFound session=\(sessionID)"
      )
      token.heldSession.release()
      throw TKError(.tokenNotFound)
    } catch let error as SecureMessagingChannel.Failure {
      // The retained channel is desynchronized or broken by link drop.
      // Release the hold and request a fresh scan via tokenNotFound.
      TokenLog.error(
        "sign: secure channel failed (\(error)) - requesting card scan via tokenNotFound session=\(sessionID)"
      )
      token.heldSession.release()
      throw TKError(.tokenNotFound)
    } catch CardOperationError.sessionUnavailable {
      // The system ended the mint field before Safari asked us to sign.
      // `tokenNotFound` tells CryptoTokenKit that this token instance no
      // longer has a card behind it, so a retry may open a replacement
      // NFC field and mint a fresh instance. Keep every real
      // PACE, APDU and card failure on the communication-error path below.
      TokenLog.notice(
        "sign: retained field unavailable - requesting fresh token via tokenNotFound session=\(sessionID)"
      )
      token.heldSession.release()
      throw TKError(.tokenNotFound)
    } catch let error as TokenError {
      token.heldSession.release()
      throw error.asTKError
    } catch let error as TKError {
      token.heldSession.release()
      throw error
    } catch {
      // A PACE refusal, a secure-messaging fault or a signing SW must not
      // escape unmapped, and must not look like a wrong PIN: a genuine
      // card failure ends the handshake instead of re-looping the prompt.
      token.heldSession.release()
      throw TKError(.communicationError)
    }
  }
}
