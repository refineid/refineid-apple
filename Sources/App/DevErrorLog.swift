// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
  import CryptoTokenKit
  import Foundation
  import notify
  import os
  import Security

  /// The recent errors of every RefineID process, for the development
  /// error display.
  ///
  /// The app and both token extensions report here. The extensions run in
  /// processes of their own, so the entries live in one keychain item in
  /// the access group the three binaries share, and a Darwin notification
  /// tells the app to read them again.
  ///
  /// Development builds only. TestFlight and Release define no `DEBUG` and
  /// exclude this file, so a shipped binary carries none of it. A message
  /// names the event and its reason and nothing else: never a PIN or its
  /// length, a card access number, a name, certificate content, a device
  /// name or a serial number.
  ///
  /// Every entry also goes to the unified log, subsystem `fi.refineid.ReFineID`
  /// category `errors`, so `log stream` and Console show it beside the
  /// other traces.
  ///
  /// Two processes reporting in the same instant can lose an entry: this
  /// is an instrument for noticing failures, not a ledger.
  internal enum DevErrorLog {
    // MARK: Nested Types

    /// The process an entry came from.
    internal enum Source: String, Codable, Sendable {
      case app = "app"
      case rappTokenExtension = "rapp-token"
      case tokenExtension = "token"
    }

    /// One reported error.
    internal struct Entry: Codable, Equatable, Sendable {
      /// Tells two entries with the same text apart.
      internal let identifier: UUID
      /// When the error was reported.
      internal let date: Date
      /// The process that reported it.
      internal let source: Source
      /// The event and its reason.
      internal let message: String
      /// How many times in a row it was reported.
      internal let occurrences: Int

      /// The message, with how many times in a row it came.
      internal var text: String {
        occurrences > 1 ? "\(message) (x\(occurrences))" : message
      }
    }

    // MARK: Static Properties

    /// How many entries the log keeps; the oldest go first.
    internal static let capacity = 50

    /// The longest message kept, in characters.
    internal static let maximumMessageLength = 240

    /// The Darwin notification posted after every change to the log.
    internal static let changedNotification = "fi.refineid.dev-errors.changed"

    /// The launch argument with which a UI test records and shows errors.
    internal static let uiTestOptInArgument = "--ui-test-dev-errors"

    /// Whether this process records errors: never in a test run, unless a
    /// UI test opted in, so a test's failures never reach a developer's
    /// own display.
    internal static let isRecording =
      !TestCredentialEnvironment.isTestMode
      || ProcessInfo.processInfo.arguments.contains(uiTestOptInArgument)

    /// The unified-log channel every entry is also written to.
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "errors")

    /// Keychain service the log lives under, beside the extension trace.
    private static let service = "fi.refineid.trace"

    /// Single well-known account: one log per device.
    private static let account = "errors"

    /// Suffix of the keychain access group the three binaries share.
    private static let sharedGroupSuffix = "fi.refineid.ReFineID"

    /// The entitlement naming this binary's keychain access groups.
    private static let accessGroupsEntitlement = "keychain-access-groups"

    /// How a bridged Foundation error describes itself.
    private static let bridgedErrorPrefix = "Error Domain="

    /// What the description of a privately nested type carries in place
    /// of its enclosing scope.
    private static let unknownContextPattern = #"\(unknown context at \$[0-9a-f]+\)\."#

    /// What an identifier may begin with.
    private static let identifierHeads = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))

    /// What an identifier may continue with.
    private static let identifierCharacters = Self.identifierHeads.union(.decimalDigits)

    /// Serialises the read-modify-write of one process.
    private static let lock = NSLock()

    // MARK: Static Functions

    /// Records one error, writes it to the unified log and wakes the app.
    ///
    /// Never throws and never fails its caller: a report that could break
    /// the path it watches would be taken out of it.
    internal static func report(_ message: String, source: Source) {
      guard Self.isRecording else { return }
      let entry = Entry(
        identifier: UUID(), date: Date(), source: source, message: Self.sanitized(message),
        occurrences: 1)
      Self.logger.error("\(source.rawValue, privacy: .public): \(entry.message, privacy: .public)")
      Self.lock.withLock {
        Self.write(Self.appending(entry, to: Self.stored()))
      }
      Self.post()
    }

    /// Every entry held, oldest first.
    internal static func read() -> [Entry] {
      guard Self.isRecording else { return [] }
      return Self.lock.withLock { Self.stored() }
    }

    /// Forgets every entry, for every process.
    internal static func clear() {
      guard Self.isRecording else { return }
      Self.lock.withLock {
        _ = SecItemDelete(Self.query() as CFDictionary)
      }
      Self.post()
    }

    /// `entries` with `entry` added last, cut to the newest ``capacity``.
    ///
    /// An error reported again straight after itself takes the place of
    /// the earlier one and counts it, so a loop that fails the same way on
    /// every pass shows as one line rather than pushing out everything
    /// before it.
    internal static func appending(_ entry: Entry, to entries: [Entry]) -> [Entry] {
      var kept = entries
      var added = entry
      if let last = kept.last, last.source == entry.source, last.message == entry.message {
        kept.removeLast()
        added = Entry(
          identifier: entry.identifier, date: entry.date, source: entry.source,
          message: entry.message,
          occurrences: last.occurrences + entry.occurrences)
      }
      kept.append(added)
      return Array(kept.suffix(Self.capacity))
    }

    /// `entry` as one line of text: when, from where, and what.
    ///
    /// The time is ISO 8601 in `timeZone`, so a pasted line still says
    /// which day it came from.
    internal static func line(for entry: Entry, timeZone: TimeZone) -> String {
      let time = Date.ISO8601FormatStyle(timeZone: timeZone).format(entry.date)
      return "\(time) \(entry.source.rawValue) \(entry.text)"
    }

    /// `entries` as lines of text, in the order given.
    internal static func transcript(of entries: [Entry], timeZone: TimeZone) -> String {
      entries.map { Self.line(for: $0, timeZone: timeZone) }.joined(separator: "\n")
    }

    /// `message` on one line and no longer than ``maximumMessageLength``.
    internal static func sanitized(_ message: String) -> String {
      let flattened = message.components(separatedBy: .controlCharacters).joined(separator: " ")
      return String(flattened.prefix(Self.maximumMessageLength))
    }

    /// The case an error names, without the values it carries.
    ///
    /// A CryptoTokenKit error is named by its code, any other bridged
    /// Foundation error by its domain and code.
    internal static func reason(_ error: any Error) -> String {
      if let tokenError = error as? TKError {
        return "TKError \(Self.codeName(tokenError.code))"
      }
      guard !String(describing: error).hasPrefix(Self.bridgedErrorPrefix) else {
        let bridged = error as NSError
        return "\(bridged.domain) \(bridged.code)"
      }
      return Self.caseName(of: error)
    }

    /// The case `value` is, as `name(inner)` where its payload is itself
    /// one case and as `name` where it carries anything else.
    ///
    /// Counts, labels, lists and text never pass: what a payload holds is
    /// how a secret would reach the display. A value that is no case at all
    /// is named by its type.
    internal static func caseName(of value: Any) -> String {
      let described = String(describing: value)
        .replacingOccurrences(
          of: Self.unknownContextPattern, with: "", options: .regularExpression)
      return Self.reduced(described) ?? String(describing: type(of: value))
    }

    /// The name of a CryptoTokenKit error code.
    private static func codeName(_ code: TKError.Code) -> String {
      switch code {
      case .authenticationFailed:
        "authenticationFailed"

      case .authenticationNeeded:
        "authenticationNeeded"

      case .badParameter:
        "badParameter"

      case .canceledByUser:
        "canceledByUser"

      case .communicationError:
        "communicationError"

      case .corruptedData:
        "corruptedData"

      case .notImplemented:
        "notImplemented"

      case .objectNotFound:
        "objectNotFound"

      case .tokenNotFound:
        "tokenNotFound"

      default:
        "code \(code.rawValue)"
      }
    }

    /// `described` reduced to its case names, or nil when it is no case.
    private static func reduced(_ described: String) -> String? {
      let head = described.prefix { $0 != "(" }
      let components = head.split(separator: ".", omittingEmptySubsequences: false)
      guard let name = components.last, components.allSatisfy(Self.isIdentifier) else {
        return nil
      }
      let payload = described.dropFirst(head.count)
      guard !payload.isEmpty else { return String(name) }
      guard Self.isOneGroup(payload),
        let inner = Self.reduced(String(payload.dropFirst().dropLast()))
      else { return String(name) }
      return "\(name)(\(inner))"
    }

    /// Whether `text` is one Swift identifier.
    private static func isIdentifier(_ text: Substring) -> Bool {
      guard let first = text.unicodeScalars.first, Self.identifierHeads.contains(first) else {
        return false
      }
      return text.unicodeScalars.allSatisfy(Self.identifierCharacters.contains)
    }

    /// Whether `group` is one parenthesised group from its first character
    /// to its last.
    private static func isOneGroup(_ group: Substring) -> Bool {
      var depth = 0
      for (index, character) in zip(group.indices, group) {
        if character == "(" {
          depth += 1
        } else if character == ")" {
          depth -= 1
        }
        if depth == 0 {
          return group.index(after: index) == group.endIndex
        }
      }
      return false
    }

    /// The stored entries, or none when nothing is stored or it is unreadable.
    private static func stored() -> [Entry] {
      var search = Self.query()
      search[kSecReturnData as String] = true
      search[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
        let data = item as? Data,
        let entries = try? JSONDecoder().decode([Entry].self, from: data)
      else { return [] }
      return entries
    }

    /// Replaces the stored entries, creating the item when there is none.
    private static func write(_ entries: [Entry]) {
      guard let data = try? JSONEncoder().encode(entries) else { return }
      let updated = SecItemUpdate(
        Self.query() as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
      guard updated == errSecItemNotFound else { return }
      var insert = Self.query()
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(insert as CFDictionary, nil)
    }

    /// Item coordinates shared by every operation.
    ///
    /// The data-protection keychain in the shared group, which macOS names
    /// explicitly and iOS takes as the default. Accessible after the first
    /// unlock, so a phone serving a computer from a locked screen still
    /// records what went wrong.
    private static func query() -> [String: Any] {
      var coordinates: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
        kSecUseDataProtectionKeychain as String: true,
        kSecAttrSynchronizable as String: false,
      ]
      #if os(macOS)
        if let group = Self.sharedGroup() {
          coordinates[kSecAttrAccessGroup as String] = group
        }
      #endif
      return coordinates
    }

    #if os(macOS)
      /// The shared keychain group named in this binary's entitlements.
      private static func sharedGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let value = SecTaskCopyValueForEntitlement(
          task, Self.accessGroupsEntitlement as CFString, nil)
        let groups = value as? [String] ?? []
        return groups.first { $0.hasSuffix(Self.sharedGroupSuffix) }
      }
    #endif

    /// Tells every process that the log changed.
    private static func post() {
      notify_post(Self.changedNotification)
    }
  }
#endif
