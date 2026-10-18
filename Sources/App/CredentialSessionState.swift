// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import CryptoKit
  import Foundation

  /// What one held card session already knows about its credentials: the
  /// verified PIN 1 the card still holds, the roles whose counters were
  /// probed, and the digits the card refused.
  ///
  /// Lives exactly as long as the session; a new session starts empty.
  internal struct CredentialSessionState {
    internal private(set) var isPin1Authenticated = false
    internal private(set) var probedRoles = Set<CredentialRole>()
    private var negativePinFingerprints = Set<Data>()

    private static func fingerprint(_ digits: String) -> Data {
      Data(SHA256.hash(data: Data(digits.utf8)))
    }

    internal mutating func markPin1Authenticated() {
      isPin1Authenticated = true
    }

    internal mutating func markProbed(_ role: CredentialRole) {
      probedRoles.insert(role)
    }

    internal mutating func recordNegativePin(_ digits: String) {
      negativePinFingerprints.insert(Self.fingerprint(digits))
    }

    /// Forgets the verified state; the refused digits stay refused.
    internal mutating func sessionEnded() {
      isPin1Authenticated = false
      probedRoles.removeAll()
    }

    internal func isNegativePin(_ digits: String) -> Bool {
      negativePinFingerprints.contains(Self.fingerprint(digits))
    }
  }
#endif
