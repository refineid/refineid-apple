// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// One authentication signature by an organization card held against the
/// phone, in the field the mint kept open.
///
/// The card opens only with PACE and PIN 1 as the password (FINEID S1
/// v4.0, organizational cards, section 2.1), so the PIN is settled before
/// the card is touched -- the PIN 1 the card accepted before, the staged
/// candidate, or the one just typed -- and the signature runs its own PACE
/// on the plain channel the mint held, through the same opening the
/// reader path uses (``OrganizationCardOpening/pin1(over:entered:serial:records:)``):
/// the retry floor and the held PIN 1 rule decide on the state MSE:Set AT
/// reports, before the card takes a try, and a refused PIN is never sent
/// again. A completed PACE counts as PIN 1 verified, so no VERIFY is sent.
/// The chip serial is read in the channel and must be the prime's before
/// the card signs, and the signature is checked against the prime's
/// certificate before it is returned.
internal struct OrganizationFieldSignature {
  /// The token this signature belongs to.
  private let token: Token

  internal init(token: Token) {
    self.token = token
  }

  /// Opens the card with the PIN 1 `origin` names and signs `request`.
  ///
  /// The accepted PIN 1 is taken from memory by the opening itself, which
  /// checks it against the card's state first; a candidate or a typed PIN
  /// is sent as typed.
  internal func perform(
    pin1: consuming Pin1,
    origin: AuthorizedPin1.Origin,
    request: SignRequest
  ) throws -> Data {
    let serial = token.chipSerial
    let entered: Pin1?
    if origin == .acceptedMemory {
      _ = consume pin1
      entered = nil
    } else {
      entered = .some(consume pin1)
    }
    // The lease holds the channel's lock until the signature returns.
    let lease = try token.heldSession.plainChannel()
    defer { _ = lease.channel }
    let opening: OrganizationCardOpening.Pin1Opening
    do {
      opening = try OrganizationCardOpening.pin1(
        over: lease.channel,
        entered: entered,
        serial: serial,
        records: OrganizationCardOpening.Pin1Records(
          memory: Pin1Memory.shared,
          rejected: CredentialMemory.rejectedPins,
          owner: token.pin1Owner))
    } catch OrganizationCardOpening.Pin1Unsettled.entryRequired {
      throw TokenError.authenticationRequired
    } catch OrganizationCardOpening.Pin1Unsettled.knownRejected {
      throw TokenError.pinAlreadyRejected
    } catch let failure as PaceEstablishment.Failure {
      // A handshake that broke part way may have spent a try the card
      // returns only on completion: an unverified candidate is dropped.
      Pin1Memory.shared.clearCandidate(serial: serial)
      let refusal = OrganizationSignature.refusal(failure, pin: .pin1)
      throw refusal is PaceEstablishment.Failure ? TokenError.signRefused : refusal
    } catch {
      Pin1Memory.shared.clearCandidate(serial: serial)
      throw error
    }
    let signature = try sign(request, in: opening.opened.operations)
    if let acceptance = opening.acceptance {
      Pin1Memory.shared.commit(acceptance, after: opening.opened.pinState)
    }
    return signature
  }

  /// The chip serial checked, then the signature, checked against the
  /// prime's certificate.
  private func sign(_ request: SignRequest, in operations: CardOperations) throws -> Data {
    guard try operations.readChipSerial() == token.chipSerial else {
      TokenLog.error("sign: card in the field is not the token's card")
      throw TokenError.signRefused
    }
    let raw = try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    guard
      let signature = request.wireSignature(from: raw),
      request.isSatisfied(by: signature, from: token.leafPublicKey)
    else {
      throw TokenError.signatureMalformed
    }
    return signature
  }
}
