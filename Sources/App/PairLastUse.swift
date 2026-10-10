// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import Foundation

  /// When each pairing last had a session, so records announce the most
  /// recently used pairings first.
  internal enum PairLastUse {
    private static let keyPrefix = "rapp.pair.lastUsedMs."
    private static let millisecondsPerSecond: Double = 1_000

    internal static func milliseconds(pairID: Data) -> UInt64? {
      guard let stored = UserDefaults.standard.object(forKey: key(pairID)) as? Int, stored >= 0
      else { return nil }
      return UInt64(stored)
    }

    internal static func markUsed(pairID: Data, at date: Date) {
      let value = Int(max(0, date.timeIntervalSince1970) * millisecondsPerSecond)
      UserDefaults.standard.set(value, forKey: key(pairID))
    }

    private static func key(_ pairID: Data) -> String {
      keyPrefix + pairID.map { String(format: "%02x", $0) }.joined()
    }
  }
#endif
