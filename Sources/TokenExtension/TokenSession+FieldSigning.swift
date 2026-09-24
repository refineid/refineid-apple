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

    // When approval of the certificate is requested, the prior contactless field
    // from the discovery/selection phase is expected to be gone before approval appears.
    // If the card is not physically in the slot or the retained session has already ended,
    // immediately mark a pending sign, release stale state, and throw tokenNotFound so ctkd
    // prompts the user without delay.
    let slotState = token.smartCard.slot.state
    guard slotState == .validCard, token.heldSession.isAvailable else {
      PendingSigningState.shared.recordPendingSign()
      TokenLog.notice(
        "sign: contactless card absent (slotState=\(slotState.rawValue)) "
          + "- tokenNotFound session=\(sessionID)"
      )
      token.heldSession.release()
      throw TKError(.tokenNotFound)
    }

    guard token.heldSession.waitForAvailable(timeout: Self.heldSessionWaitSeconds) else {
      PendingSigningState.shared.recordPendingSign()
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
    } catch {
      throw mapFieldFailure(error, token: token)
    }
  }

  private func mapFieldFailure(
    _ error: any Error,
    token: Token
  ) -> any Error {
    token.heldSession.release()
    switch error {
    case SmartCardChannel.TransportError.responseTimedOut:
      PendingSigningState.shared.recordPendingSign()
      TokenLog.notice(
        "sign: transport timed out - requesting scan via tokenNotFound session=\(sessionID)"
      )
      return TKError(.tokenNotFound)

    case let channelError as SecureMessagingChannel.Failure:
      PendingSigningState.shared.recordPendingSign()
      TokenLog.error(
        "sign: secure channel failed (\(channelError)) - requesting scan session=\(sessionID)"
      )
      return TKError(.tokenNotFound)

    case CardOperationError.sessionUnavailable:
      PendingSigningState.shared.recordPendingSign()
      TokenLog.notice(
        "sign: retained field unavailable - requesting fresh token session=\(sessionID)"
      )
      return TKError(.tokenNotFound)

    case let cardError as CardOperationError:
      _ = cardError
      return TKError(.communicationError)

    case let tokenError as TokenError:
      return tokenError.asTKError

    case let tkError as TKError:
      return tkError

    default:
      PendingSigningState.shared.recordPendingSign()
      TokenLog.error(
        "sign: transport failure (\(error)) - requesting scan via tokenNotFound session=\(sessionID)"
      )
      return TKError(.tokenNotFound)
    }
  }
}
