// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import Security

/// Names and TXT records of the stream service (RAPP v26.10.21 §4.5 and the
/// transport hierarchy §4.3).
///
/// The instance name is drawn at random for every listener; the records
/// carry only values keyed by a pairing's static agreement, so nothing on
/// the network names a person, a device or a pairing to anyone else.
public enum StreamRendezvousName {
  // MARK: Static Properties

  private static let ephemeralByteCount = 4

  private static let ephemeralPrefix = "refineid-"

  /// The TXT record of a listener offering a pairing.
  public static let pairingAttributes = ["v": "1", "mode": "pairing"]

  /// Seconds a discovery hint epoch lasts; a custodian refreshes its
  /// session record on this cadence.
  public static let hintEpochSeconds: UInt64 = 900

  /// Seconds a custodian keeps its withdrawn record up before it
  /// unregisters, within the 2 to 10 seconds the specification allows.
  public static let withdrawalAnnouncementSeconds: UInt64 = 3

  // MARK: Static Functions

  /// A fresh random instance name for one listener.
  public static func ephemeralName() -> String {
    var bytes = [UInt8](repeating: 0, count: ephemeralByteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "The system random source failed")
    return ephemeralPrefix + bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// The custodian's `mode=session` record announcing the discovery hints
  /// of its most recently used pairings (transport hierarchy §4.3).
  public static func sessionRecord(candidates: [RappAnnouncementCandidate]) -> [String: String] {
    dictionary(rappSessionRecord(candidates: candidates))
  }

  /// The custodian's `mode=withdrawn` record; empty when the random
  /// source fails.
  public static func withdrawnRecord(candidates: [RappAnnouncementCandidate]) -> [String: String] {
    (try? rappWithdrawnRecord(candidates: candidates)).map(dictionary) ?? [:]
  }

  /// Whether a session record carries one of the pairing's discovery hints.
  public static func sessionRecord(
    _ record: [String: String], holds pair: RappPairRecord, at date: Date
  ) -> Bool {
    pair.matchesDiscoveryRecord(entries(record), unixTimeSeconds: unixTime(date))
  }

  /// Whether `record`, published under `instance`, withdraws `pair`.
  public static func withdrawnRecord(
    _ record: [String: String], instance: String, withdraws pair: RappPairRecord, at date: Date
  ) -> Bool {
    pair.matchesWithdrawnRecord(
      instance: instance, txt: entries(record), unixTimeSeconds: unixTime(date))
  }

  /// Whole seconds since 1970 at `date`, never negative.
  public static func unixTime(_ date: Date) -> UInt64 {
    UInt64(max(0, date.timeIntervalSince1970))
  }

  private static func entries(_ record: [String: String]) -> [RappTxtEntry] {
    record.map { RappTxtEntry(key: $0.key, value: $0.value) }
  }

  private static func dictionary(_ entries: [RappTxtEntry]) -> [String: String] {
    Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
  }
}
