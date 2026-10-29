// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation

/// What one held card session already knows about its credentials: the
/// verified PIN 1 the card still holds, the roles whose counters were
/// probed, and the digits the card refused.
///
/// Lives exactly as long as the session: a new session starts empty, so
/// nothing learned about one card is held against another.
internal struct CredentialSessionState: Equatable {
  internal private(set) var probedRoles = Set<CredentialRole>()
  private var negativePinFingerprints = Set<Data>()

  private static func fingerprint(_ digits: String) -> Data {
    Data(SHA256.hash(data: Data(digits.utf8)))
  }

  internal mutating func markProbed(_ role: CredentialRole) {
    probedRoles.insert(role)
  }

  /// The card refused `digits` for `role`: the digits are never sent
  /// again in this session, and the role's counter is probed again before
  /// its next verification, since the refusal spent an attempt (RAPP
  /// v26.10.29 §10.2).
  internal mutating func recordNegativePin(_ digits: String, role: CredentialRole) {
    negativePinFingerprints.insert(Self.fingerprint(digits))
    probedRoles.remove(role)
  }

  /// Forgets everything the session learned.
  internal mutating func sessionEnded() {
    probedRoles.removeAll()
    negativePinFingerprints.removeAll()
  }

  internal func isNegativePin(_ digits: String) -> Bool {
    negativePinFingerprints.contains(Self.fingerprint(digits))
  }
}
