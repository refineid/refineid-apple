// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
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
    /// The double group size boundary for 4-character formatting.
    public static let doubleGroupSize = 4
    /// The offer lifetime RAPP v26.10.1 §3.3 fixes: 60 seconds from the
    /// moment the custodian shows the code.
    public static let offerLifetimeMilliseconds: UInt64 = 60_000

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
  }
#endif
