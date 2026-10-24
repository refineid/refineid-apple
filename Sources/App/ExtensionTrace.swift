// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
  import Foundation
  import Security

  /// A rolling record of what the extensions did, kept where the containing
  /// app can read it.
  ///
  /// The extensions run inside `ctkd`, and on iOS 26 there is no way in from
  /// a cable: `log stream --device` is gone, `log collect` fails, and the
  /// file ``TokenLog`` writes sits in a container no other process may open.
  /// The extensions therefore write their trace into one keychain item in
  /// the access group the binaries share, and the app's diagnostics screen
  /// shows it.
  ///
  /// Development builds only. TestFlight and Release define no `DEBUG` and
  /// exclude this file, so a shipped binary carries neither the trace nor
  /// its keychain service. A test run records nothing and never touches the
  /// keychain.
  ///
  /// The buffer is bounded at ``maximumBytes`` and drops the oldest half
  /// when it overflows. Halving rather than dropping one line at a time
  /// keeps the cost of an append flat: the expensive trim happens once per
  /// several hundred lines instead of on every line past the cap. Two
  /// processes appending in the same instant can lose a line: this is an
  /// instrument for reading control flow, not a ledger.
  ///
  /// Nothing secret is written. Sizes, INS bytes, status words, timings and
  /// typed reasons only -- never a PIN, a card access number, a serial or a
  /// holder name. The buffer is a plaintext keychain item, read by a screen
  /// the holder can share from.
  ///
  /// The item lives in the data-protection keychain in the shared access
  /// group, which macOS names explicitly and iOS takes as the default, so
  /// access follows the entitlement rather than the signature of the build
  /// that created it. It is `WhenUnlockedThisDeviceOnly`, matching
  /// ``PrimeStore``, and non-synchronizable, so it is never backed up,
  /// restored elsewhere, or sent to iCloud.
  internal enum ExtensionTrace {
    /// Lines recorded in memory but not yet written to the shared item.
    ///
    /// `@unchecked Sendable` is sound because every access holds the lock:
    /// CryptoTokenKit calls a token on its own threads and a slot-state
    /// observation fires on another, so two writers are the ordinary case
    /// rather than an exotic one.
    internal final class Pending: @unchecked Sendable {
      /// Serialises the threads that reach the waiting lines.
      private let lock = NSLock()

      /// The lines waiting to be written, oldest first.
      private var lines: [String] = []

      /// Adds one line to the waiting set.
      internal func record(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
      }

      /// Removes and returns everything waiting.
      internal func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let drained = lines
        lines.removeAll()
        return drained
      }
    }

    /// How large the stored trace may grow, in bytes.
    ///
    /// Big enough to hold several whole login attempts end to end, small
    /// enough that reading and rewriting it stays cheap.
    internal static let maximumBytes: Int = 20_000

    /// How much of the buffer a trim keeps: the newer half.
    internal static let survivingFraction: Int = 2

    /// Whether this process records: never in a test run.
    internal static let isRecording = !TestCredentialEnvironment.isTestMode

    /// Keychain service the trace lives under.
    private static let service: String = "fi.refineid.trace"

    /// Single well-known account: one trace per device.
    private static let account: String = "latest"

    /// Cap on one line, so a single runaway message cannot displace the
    /// whole trace.
    internal static let maximumLineLength: Int = 512

    /// Separates two lines in the stored blob.
    private static let separator: Character = "\n"

    /// What a line may not contain: the blob is line-delimited, so a line
    /// carrying its own delimiter could forge trace entries.
    private static let forbidden: CharacterSet = .newlines

    /// The lines recorded in this process but not yet written out.
    private static let pending = Pending()

    /// Appends one line and writes the buffer out immediately.
    ///
    /// Never throws and never reports: a diagnostic that can fail a caller
    /// is a diagnostic that gets removed from the path it was meant to
    /// watch. Use this everywhere the cost of a keychain round trip does
    /// not matter, which is everywhere outside a live contactless field.
    internal static func append(_ line: String) {
      Self.record(line)
      Self.flush()
    }

    /// Empties the trace, in memory and on the device.
    ///
    /// Answers with the keychain's own status, so a clear that did not
    /// clear says why instead of looking like a button that does nothing.
    @discardableResult
    internal static func clear() -> OSStatus {
      _ = Self.pending.drain()
      guard Self.isRecording else { return errSecSuccess }
      return SecItemDelete(Self.query() as CFDictionary)
    }

    /// Writes everything recorded so far into the shared item.
    internal static func flush() {
      let recorded = Self.pending.drain()
      guard Self.isRecording, !recorded.isEmpty else { return }
      var buffer = Self.storedText() ?? ""
      for line in recorded {
        buffer += line + String(Self.separator)
      }
      Self.write(Self.trimmed(buffer))
    }

    /// Records one line without paying for a keychain write.
    ///
    /// The contactless path has about two seconds of field for a whole
    /// signature, and a keychain round trip per APDU spends it on the wrong
    /// thing. Lines recorded this way reach the item at the next
    /// ``append(_:)``, ``flush()`` or ``read()`` -- all of which happen once
    /// the operation that produced them has ended.
    internal static func record(_ line: String) {
      guard Self.isRecording else { return }
      Self.pending.record(Self.stamped(line))
    }

    /// Every line currently held, oldest first.
    ///
    /// Flushes before reading, so a caller inside the writing process is
    /// never shown a trace that is missing what it just recorded.
    internal static func read() -> [String] {
      Self.flush()
      guard Self.isRecording, let text = Self.storedText(), !text.isEmpty else { return [] }
      return
        text
        .split(separator: Self.separator)
        .map(String.init)
    }

    /// The tail of `buffer` that fits the cap, cut on line boundaries.
    ///
    /// A pure function, so a test exercises the rule without the keychain
    /// around it.
    internal static func trimmed(_ buffer: String) -> String {
      var text = buffer
      while text.utf8.count > Self.maximumBytes {
        let lines = text.split(separator: Self.separator, omittingEmptySubsequences: false)
        guard lines.count > 1 else { break }
        text =
          lines
          .suffix(max(1, lines.count / Self.survivingFraction))
          .joined(separator: String(Self.separator))
      }
      return text
    }

    /// Item coordinates shared by every operation.
    ///
    /// The accessibility attribute belongs on the write: a search that
    /// filtered on it would miss an item written under any other policy
    /// instead of replacing it.
    private static func query() -> [String: Any] {
      var coordinates: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
        kSecUseDataProtectionKeychain as String: true,
        kSecAttrSynchronizable as String: false,
      ]
      if let group = CardCredentialStore.sharedKeychainGroup {
        coordinates[kSecAttrAccessGroup as String] = group
      }
      return coordinates
    }

    /// When a line was written, to the millisecond.
    ///
    /// Two signatures inside the same second are the ordinary case on a TLS
    /// handshake, and a trace that cannot tell them apart cannot say which
    /// one failed. A fresh formatter per call: `ISO8601DateFormatter` is not
    /// `Sendable`.
    private static func stamp() -> String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: Date())
    }

    /// One line stamped, flattened onto a single line, and clamped.
    internal static func stamped(_ line: String) -> String {
      let flattened = line.components(separatedBy: Self.forbidden).joined(separator: " ")
      return Self.stamp() + " " + String(flattened.prefix(Self.maximumLineLength))
    }

    /// The stored blob, or nil when nothing has been traced yet.
    private static func storedText() -> String? {
      var search = Self.query()
      search[kSecReturnData as String] = true
      search[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
        let data = item as? Data
      else {
        return nil
      }
      return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored blob, creating the item when there is none.
    private static func write(_ text: String) {
      let data = Data(text.utf8)
      let updated = SecItemUpdate(
        Self.query() as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
      guard updated == errSecItemNotFound else { return }
      var insert = Self.query()
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      SecItemAdd(insert as CFDictionary, nil)
    }
  }
#endif
