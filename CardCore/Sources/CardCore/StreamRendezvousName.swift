// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// The published names and attributes one side listens under and the
/// other browses for (RAPP discovery hierarchy §4.2 and §4.3).
///
/// Every instance name is fresh and random. Nothing derived from a
/// rendezvous token or a pairing code is published, so a listener on the
/// network can neither search the code space offline nor recognize the
/// same phone over time. A custodian in session mode may publish rotating
/// hints so a requester dials the phone that holds its pairing.
public enum StreamRendezvousName {
  // MARK: Static Properties

  /// Random bytes in an ephemeral instance name: eight hex characters.
  private static let ephemeralByteCount = 4

  private static let ephemeralPrefix = "refineid-"

  /// The attributes a custodian in pairing mode publishes.
  public static let pairingAttributes = ["v": "1", "mode": "pairing"]

  /// The attributes a custodian in session mode publishes.
  public static let sessionAttributes = ["v": "1", "mode": "session"]

  /// The attribute that carries the rotating discovery hints.
  public static let hintsKey = "hints"

  /// The most pairings a custodian publishes hints for (§4.3).
  public static let maximumHintCount = 4

  /// The length of one hint rotation window: 15 minutes.
  public static let hintEpochSeconds: UInt64 = 900

  /// Bytes of the HMAC one hint carries.
  private static let hintByteCount = 8

  /// Bytes of the per-pairing hint key.
  private static let hintKeyByteCount = 32

  private static let hintKeyInfo = Data("RAPP-discovery-hint-v1".utf8)

  private static let hintSeparator: Character = ","

  // MARK: Static Functions

  /// A fresh random instance name, drawn whenever advertising starts.
  public static func ephemeralName() -> String {
    var bytes = [UInt8](repeating: 0, count: ephemeralByteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "The system random source failed")
    return ephemeralPrefix + hex(Data(bytes))
  }

  /// The hint rotation window `date` falls in.
  public static func hintEpoch(at date: Date) -> UInt64 {
    UInt64(max(0, date.timeIntervalSince1970)) / hintEpochSeconds
  }

  /// One pairing's hint for one rotation window.
  ///
  /// The key is HKDF-Expand over the rendezvous token and the hint is the
  /// first eight bytes of HMAC-SHA-256 over the window number, encoded as
  /// an unsigned 64-bit big-endian integer.
  public static func discoveryHint(rendezvousToken: Data, epoch: UInt64) -> String {
    let key = HKDF<SHA256>.expand(
      pseudoRandomKey: SymmetricKey(data: rendezvousToken),
      info: hintKeyInfo,
      outputByteCount: hintKeyByteCount)
    var window = epoch.bigEndian
    let message = Data(bytes: &window, count: MemoryLayout<UInt64>.size)
    let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
    return hex(Data(mac.prefix(hintByteCount)))
  }

  /// The session-mode record for the given pairings at `date`.
  ///
  /// Hints are published for at most four pairings; a record with none
  /// is the minimal record.
  public static func sessionRecord(
    rendezvousTokens: [Data], at date: Date
  ) -> [String: String] {
    var record = sessionAttributes
    let epoch = hintEpoch(at: date)
    let hints = rendezvousTokens.prefix(maximumHintCount).map { token in
      discoveryHint(rendezvousToken: token, epoch: epoch)
    }
    if !hints.isEmpty {
      record[hintsKey] = hints.joined(separator: String(hintSeparator))
    }
    return record
  }

  /// Whether a published record is a session-mode custodian.
  public static func isSessionRecord(_ record: [String: String]) -> Bool {
    sessionAttributes.allSatisfy { key, value in record[key] == value }
  }

  /// Whether a session-mode record may hold the pairing with this token.
  ///
  /// A record with hints names it only through a hint for the current or
  /// an adjacent window; a minimal record may hold any pairing.
  public static func sessionRecord(
    _ record: [String: String], mayHold rendezvousToken: Data, at date: Date
  ) -> Bool {
    guard isSessionRecord(record) else { return false }
    guard let published = record[hintsKey] else { return true }
    let hints = Set(published.split(separator: hintSeparator).map(String.init))
    let epoch = hintEpoch(at: date)
    let windows = [epoch &- 1, epoch, epoch &+ 1]
    return windows.contains { window in
      hints.contains(discoveryHint(rendezvousToken: rendezvousToken, epoch: window))
    }
  }

  private static func hex(_ bytes: Data) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
