// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The password a PACE run authenticates the channel with, as the run
/// needs it: the MSE:Set AT password reference and the nonce key.
///
/// The citizen cards take the card access number printed on the card; the
/// organization cards take PIN 1 or PIN 2 instead (FINEID S1 v4.0,
/// organizational cards, section 2.1; FINEID S4-2 v4.0 section 6), under
/// the card's own security-data-object references, the ones its VERIFY
/// uses (S4-2 v4.0 section 4.2).
///
/// The password never travels. Both sides derive the nonce key
/// `K_pi = SHA-256(password || 00000003)` (BSI TR-03110-3 section A.2.3),
/// the password encoded as its character string, one ISO/IEC 8859-1 octet
/// per character (table 5, appendix D.2.1.4). A CAN and a PIN are both
/// ASCII digits, their own ISO/IEC 8859-1 octets, so both are encoded as
/// the digits as they stand.
///
/// A PIN password is a PIN's one transmission: building it consumes the
/// PIN, so one entry opens at most one handshake. The type holds only the
/// derived key, which determines the PIN by search over the digit space,
/// so it is noncopyable, not `CustomStringConvertible` and not `Codable`.
public struct PacePassword: ~Copyable {
  /// The MSE:Set AT `83` password reference.
  internal let reference: UInt8

  /// The PIN whose counter a failed handshake spends; nil for the card
  /// access number, which has none.
  internal let credential: CredentialRole?

  /// `K_pi`.
  internal let key: Data

  /// The card access number of a citizen card.
  public init(cardAccessNumber: CardAccessNumber) {
    reference = PaceValues.passwordReferenceCan
    credential = nil
    key = cardAccessNumber.derivedPasswordKey()
  }

  /// PIN 1 of an organization card.
  public init(pin1: consuming Pin1Transmission) {
    reference = FineidValues.organizationReference(for: .pin1)
    credential = .pin1
    key = PaceKeyDerivation.derivedKey(from: Data(pin1.store.bytes), for: .password)
  }

  /// PIN 2 of an organization card.
  public init(pin2: consuming Pin2Transmission) {
    reference = FineidValues.organizationReference(for: .pin2)
    credential = .pin2
    key = PaceKeyDerivation.derivedKey(from: Data(pin2.store.bytes), for: .password)
  }
}
