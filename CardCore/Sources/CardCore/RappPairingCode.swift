// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import CryptoKit
  import Foundation
  import RappEngine
  import Security

  /// Generates, formats, and validates 6-character Crockford Base32 pairing codes
  /// for simple, secure out-of-band peer pairing without QR codes per RAPP v26.10.1 §3.1.
  public enum RappPairingCode {
    // MARK: Static Properties

    /// The standard character length of a Crockford Base32 pairing code.
    public static let codeLength = 6

    /// The number of characters in one formatted group.
    public static let groupSize = 2

    /// Crockford Base32 alphabet (32 symbols, excluding I, L, O, U).
    public static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static let alphabetSet = Set(alphabet)
    /// ASCII whitespace (SPACE, TAB, LF, VT, FF, CR) and the hyphen, removed by step 4.
    private static let strippedScalars: Set<Unicode.Scalar> = [
      " ", "\t", "\n", "\u{0B}", "\u{0C}", "\r", "-",
    ]
    private static let asciiLowercase = Unicode.Scalar("a").value...Unicode.Scalar("z").value
    private static let sha256ByteCount = 32
    private static let defaultPairingSecretByteCount = 32
    /// The double group size boundary for 4-character formatting.
    public static let doubleGroupSize = 4
    @usableFromInline internal static let defaultLifetimeMilliseconds: UInt64 = 180_000
    @usableFromInline internal static let emptyCborMap = Data([0b1010_0000])

    // MARK: Static Functions

    /// Generates a fresh cryptographically secure random 6-character Crockford Base32 pairing code.
    ///
    /// The alphabet size divides the byte range evenly, so reducing each
    /// random byte modulo the alphabet size draws every symbol uniformly.
    public static func generate() -> String {
      var bytes = [UInt8](repeating: 0, count: codeLength)
      let status = SecRandomCopyBytes(kSecRandomDefault, codeLength, &bytes)
      precondition(status == errSecSuccess, "The system random source failed")
      return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Applies the Crockford Base32 canonicalization pipeline per RAPP v26.10.1 §3.1.
    ///
    /// NFKC first, then ASCII-only uppercasing, removal of ASCII whitespace
    /// and hyphens, and the Crockford decode aliases (I and L to 1, O to 0).
    /// Returns the canonical string, which may be shorter or longer than a
    /// code, or an empty string when any character is outside the alphabet
    /// or is the rejected U. ``isValid(_:)`` decides the exact length.
    public static func normalize(_ input: String) -> String {
      var result = ""
      for scalar in input.precomposedStringWithCompatibilityMapping.unicodeScalars {
        if strippedScalars.contains(scalar) { continue }
        let upper =
          asciiLowercase.contains(scalar.value)
          ? Character(scalar).uppercased() : String(scalar)
        switch upper {
        case "I", "L":
          result.append("1")

        case "O":
          result.append("0")

        case _ where upper.count == 1 && alphabetSet.contains(Character(upper)):
          result.append(upper)

        default:
          return ""
        }
      }
      return result
    }

    /// Formats a pairing code into two-character clusters: "XX XX XX" (e.g., "7K X4 M9").
    public static func formatted(_ input: String) -> String {
      let normalized = normalize(input)
      guard normalized.count > groupSize else {
        return normalized
      }
      guard normalized.count > doubleGroupSize else {
        let firstGroup = normalized.prefix(groupSize)
        let secondGroup = normalized.dropFirst(groupSize)
        return "\(firstGroup) \(secondGroup)"
      }
      let firstGroup = normalized.prefix(groupSize)
      let secondGroup = normalized.dropFirst(groupSize).prefix(groupSize)
      let thirdGroup = normalized.dropFirst(doubleGroupSize)
      return "\(firstGroup) \(secondGroup) \(thirdGroup)"
    }

    /// Checks if a string is a valid complete 6-character Crockford Base32 pairing code.
    public static func isValid(_ code: String) -> Bool {
      let normalized = normalize(code)
      return normalized.count == codeLength && normalized.allSatisfy { alphabetSet.contains($0) }
    }

    /// Derives the placeholder pairing secret for the initial offer URI.
    ///
    /// The true 32-byte shared pairing secret is dynamically established via
    /// CPace PAKE (draft-irtf-cfrg-cpace-21) during the pairing handshake.
    public static func pairingSecret(for rawCode: String) -> Data {
      let code = normalize(rawCode)
      let count = Int(
        (try? RappPlatformEntropy().pairingSecret().count) ?? defaultPairingSecretByteCount)
      let hash = SHA256.hash(data: Data("refineid-rapp-pairing-secret-v1:\(code)".utf8))
      if count <= sha256ByteCount {
        return Data(hash.prefix(count))
      }
      return Data(hash) + Data(repeating: 0, count: count - sha256ByteCount)
    }

    /// Derives the pairing offer identifier deterministically from the 6-digit code
    /// using CPace manual offer derivation.
    public static func offerIdentifier(for rawCode: String) -> Data {
      let code = normalize(rawCode)
      if let offerId = try? cpaceDeriveManualOfferId(code: code) {
        return offerId
      }
      let hash = SHA256.hash(data: Data("refineid-rapp-offer-id-v1:\(code)".utf8))
      return Data(hash)
    }

    /// Derives the full pairing offer for the given 4-character code and candidate.
    public static func pairingOffer(
      for rawCode: String,
      profiles: [String] = [
        "fi.refineid.card-status.v1",
        "fi.refineid.authentication.v1",
        "fi.refineid.document-signing.v1",
      ],
      candidate: RappTransportCandidate = RappTransportCandidate(
        profile: rappStreamProfileName(),
        candidateId: "stream-1",
        parametersCbor: emptyCborMap
      ),
      lifetimeMilliseconds: UInt64 = defaultLifetimeMilliseconds
    ) throws -> (bridge: RappPairingBridge, uri: String) {
      let code = normalize(rawCode)
      guard isValid(code) else { throw RappBindingError.InvalidInput }
      let secret = pairingSecret(for: code)
      let offerId = offerIdentifier(for: code)
      let clock = RappPlatformClock()
      let startedAt = clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.createRequesterOffer(
        offerId: offerId,
        pairingSecret: secret,
        profiles: profiles,
        transports: [candidate],
        offerTtlMs: lifetimeMilliseconds,
        startedAtMonotonicMs: startedAt
      )
      let uri = try bridge.offerUri(nowMonotonicMs: startedAt)
      return (bridge: bridge, uri: uri)
    }
  }
#endif
