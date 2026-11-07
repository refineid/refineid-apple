// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The certificates entitled to sign the EU List of Trusted Lists, the
/// one set of certificates this software ships.
///
/// ETSI TS 119 612 V2.3.1 clause 5.3.13 and annex A.1: the list of the
/// lists is authenticated under the certificates the Official Journal
/// of the European Union publishes for it, the notice the list's own
/// scheme information URI names: OJ C, C/2026/1944
/// (`https://eur-lex.europa.eu/eli/C/2026/1944/oj`). The notice lists
/// six certificates by SHA-256 and SHA-1 digest; the six DER files in
/// `TrustedListSigners/`, copied from refineid-core's
/// `crates/doc-sign/trust-anchors/`, hash to `fingerprints`, each equal
/// to one of the notice's SHA-256 digests. The list of the lists
/// repeats the same set in the pointer to itself, and that pointer at
/// sequence number 397 is the copy these bytes were taken from. A
/// future set is re-checked the same way: compare the SHA-256 digests
/// the new notice lists with the certificates the list of the lists
/// carries in its pointer to itself.
public enum EuListOfTheListsSigners {
  /// How many certificates the notice lists.
  public static let count = 6

  /// The SHA-256 digests the notice lists, lowercase hexadecimal, in
  /// the order the pointer lists the certificates.
  public static let fingerprints = [
    "d2064fdd70f6982dcc516b86d9d5c56aea939417c624b2e478c0b29de54f8474",
    "e0a620fbb6747362bb933ac44169d676a553444716cf5f31605f12a22b8396b1",
    "c0641c4f7d56c431b1c924742db7fce9c1eef7d7fd212113a2768486b3abcdc5",
    "df7e29360c34b2b8d6d5f40325c1d4d12c9922cecd33b7407674a74b2b3ca1e5",
    "b63d416744e7098bf9ec2caa596a93bc2468e37f8284ba65ecc061711bcbaa18",
    "236103f03a8031ae8f47f9059bf8de38564cdbfebedde4a597d50f8980aa653b",
  ]

  /// The directory of the DER files inside the module's resources.
  private static let directory = "TrustedListSigners"

  /// The file name of the certificate numbered `number`, without its
  /// extension.
  private static let fileNamePrefix = "eu-lotl-signer-"

  /// The DER file extension.
  private static let fileExtension = "der"

  /// The shipped certificates, DER, in the order of `fingerprints`;
  /// one whose bytes do not hash to its fingerprint is left out, so
  /// nothing is anchored on a changed file.
  public static var certificates: [Data] {
    (1...Self.count).compactMap { number -> Data? in
      guard
        let url = Bundle.module.url(
          forResource: Self.fileNamePrefix + String(number),
          withExtension: Self.fileExtension,
          subdirectory: Self.directory
        ),
        let der = try? Data(contentsOf: url),
        Self.fingerprint(of: der) == Self.fingerprints[number - 1]
      else {
        return nil
      }
      return der
    }
  }

  /// The SHA-256 of `der` in lowercase hexadecimal.
  internal static func fingerprint(of der: Data) -> String {
    SHA256.hash(data: der).map { byte in String(format: "%02x", byte) }.joined()
  }
}
