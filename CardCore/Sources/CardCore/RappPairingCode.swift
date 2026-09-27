// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import CryptoKit
  import Foundation
  import RappEngine
  import Security

  /// Generates, formats, and validates 4-character alphanumeric pairing codes
  /// for simple, secure out-of-band peer pairing without QR codes.
  public enum RappPairingCode {
    // MARK: Static Properties

    /// The standard character length of a numeric pairing code.
    public static let codeLength = 6

    /// The number of digits in one formatted group.
    public static let groupSize = 3

    private static let sha256ByteCount = 32
    private static let defaultOfferIdByteCount = 16
    private static let defaultPairingSecretByteCount = 32
    @usableFromInline internal static let defaultLifetimeMilliseconds: UInt64 = 180_000
    @usableFromInline internal static let emptyCborMap = Data([0b1010_0000])

    /// Decimal digits alphabet [0-9].
    private static let alphabet: [Character] = Array("0123456789")

    // MARK: Static Functions

    /// Generates a fresh cryptographically secure random 6-digit numeric pairing code.
    public static func generate() -> String {
      var bytes = [UInt8](repeating: 0, count: codeLength)
      _ = SecRandomCopyBytes(kSecRandomDefault, codeLength, &bytes)
      return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Normalizes raw input: extracts only digits and truncates to code length.
    public static func normalize(_ input: String) -> String {
      let filtered = input.filter { char in
        ("0"..."9").contains(char)
      }
      return String(filtered.prefix(codeLength))
    }

    /// Formats a numeric pairing code with a space after 3 digits (e.g., "123 456").
    public static func formatted(_ input: String) -> String {
      let digits = normalize(input)
      if digits.count >= groupSize {
        let firstPart = digits.prefix(groupSize)
        let secondPart = digits.dropFirst(groupSize)
        return secondPart.isEmpty ? "\(firstPart) " : "\(firstPart) \(secondPart)"
      }
      return digits
    }

    /// Checks if a string is a valid complete 6-digit pairing code.
    public static func isValid(_ code: String) -> Bool {
      let filtered = code.filter { char in
        ("0"..."9").contains(char)
      }
      return filtered.count == codeLength
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
