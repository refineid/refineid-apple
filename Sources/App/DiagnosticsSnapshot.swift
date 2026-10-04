// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// One reading of everything that decides whether a login can work, taken
/// all at once so the parts can be compared against each other.
///
/// The parts only mean something together. A registered smart-card token
/// with no prime behind it fails differently from a prime with no
/// registration; a missing stored PIN explains a signature that was never
/// attempted; an extension trace with no `createToken` line in it says
/// the failure happened before our code ran at all. Reading them one
/// screen at a time loses exactly the comparison that diagnoses.
///
/// Deliberately not localized. A diagnostic that changes wording with the
/// device language cannot be diffed against yesterday's capture, and this
/// is read by whoever is holding the card, not by everyone.
///
/// Nothing here prints a card access number, a PIN, a complete PKCS#15
/// serial or a holder name. The public token identifier deliberately
/// includes the nine-character serial printed on the card, so the holder
/// can match system state to the plastic. Everything else is presence,
/// counts, sizes, identifiers, status and typed reasons only. Keychain
/// items are counted, never described: a certificate's label carries the
/// holder's name.
internal struct DiagnosticsSnapshot: Sendable {
  /// One titled block of lines.
  internal struct Section: Sendable {
    /// What the block is about; also its identity in a list.
    internal let title: String

    /// The lines, in the order they were collected.
    internal let lines: [String]
  }

  /// What is printed for a section that found nothing.
  private static let nothing = "(none)"

  /// Enough of an identifier to tell two pairings apart.
  private static let identifierPrefixLength = 4

  /// The blocks, in reading order.
  internal let sections: [Section]

  /// The whole snapshot as plain text, for the share and copy actions.
  ///
  /// Getting a trace off the phone is the point of the screen: a photo of
  /// a scrolling list is not evidence anybody can grep.
  internal var text: String {
    sections
      .map { section in
        (["== " + section.title + " =="] + section.lines).joined(separator: "\n")
      }
      .joined(separator: "\n\n")
  }

  /// Reads everything, now, on the caller's thread.
  ///
  /// Every part reads an already-known store or CryptoTokenKit's passive
  /// state. It never enumerates token keychain items: that query can ask
  /// the extension to mint a token and present an NFC reader sheet, so a
  /// diagnostic capture doing it would alter the failure being observed.
  internal static func collect() -> Self {
    Self(
      sections: [
        Self.registeredTokens(),
        Self.watcherTokens(),
        Self.driverConfigurations(),
        Self.primeStore(),
        Self.network(),
        Self.pairings(),
        Self.credentialPolicy(),
        Self.transportPolicy(),
        Self.keychainCounts(),
        Self.extensionTrace(),
      ])
  }

  /// What the system has been told to ask for later.
  ///
  /// This is what priming leaves behind, and its absence is the first
  /// thing to check when the system never presents the card.
  private static func registeredTokens() -> Section {
    #if os(iOS)
      let registered = TKSmartCardTokenRegistrationManager.default
        .registeredSmartCardTokens
        .sorted()
      return Section(
        title: "Registered smart-card tokens (\(registered.count))",
        lines: registered.isEmpty ? [Self.nothing] : registered)
    #else
      return Section(
        title: "Registered smart-card tokens",
        lines: ["not available on this platform"])
    #endif
  }

  /// What CryptoTokenKit is publishing right now.
  ///
  /// The watcher and the registration list disagree often, and the
  /// disagreement is the diagnosis: registered but never published means
  /// the mint refused, published but not registered means the system will
  /// not ask for it.
  private static func watcherTokens() -> Section {
    let watcher = TKTokenWatcher()
    let tokens = watcher.tokenIDs.sorted()
    let lines = tokens.map { tokenID -> String in
      let info = watcher.tokenInfo(forTokenID: tokenID)
      return tokenID
        + "  slot=" + (info?.slotName ?? "?")
        + " driver=" + (info?.driverName ?? "?")
    }
    return Section(
      title: "Token watcher (\(tokens.count))",
      lines: lines.isEmpty ? [Self.nothing] : lines)
  }

  /// What the host app can see of its own token extensions.
  ///
  /// `ctkd` purges these for a smart-card driver class as soon as that
  /// driver creates a token, so an empty list here is normal after a
  /// successful mint and suspicious before one.
  private static func driverConfigurations() -> Section {
    let configurations = TKTokenDriver.Configuration.driverConfigurations
    let lines = configurations.keys.sorted().map { classID -> String in
      guard let driver = configurations[classID] else {
        return classID + ": 0 token configuration(s)"
      }
      var desc = classID + ": \(driver.tokenConfigurations.count) token configuration(s)"
      for (instance, config) in driver.tokenConfigurations.sorted(by: { $0.key < $1.key }) {
        desc += " [\(instance): \(config.keychainItems.count) item(s)]"
      }
      return desc
    }
    return Section(
      title: "Driver configurations (\(configurations.count))",
      lines: lines.isEmpty ? [Self.nothing] : lines)
  }

  /// What this device holds for each primed card, presence only.
  private static func primeStore() -> Section {
    let primes = PrimeStore.presence()
    let lines = primes.map { prime in
      prime.instance
        + "  can=" + Self.yesNo(prime.hasCardAccessNumber)
        + " leaf=\(prime.certificateBytes)B"
        + " issuer=\(prime.issuerBytes)B"
        + " serial=" + Self.yesNo(prime.hasTokenSerial)
    }
    return Section(
      title: "Prime store (\(primes.count))",
      lines: lines.isEmpty ? [Self.nothing] : lines)
  }

  /// Which network this device is on.
  ///
  /// Two devices that cannot find each other are usually not on one
  /// network, and nothing else in a capture says which one either is on.
  /// The address is the device's own and names no person.
  private static func network() -> Section {
    var lines: [String] = []
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let first = addresses else {
      return Section(title: "Network", lines: [Self.nothing])
    }
    defer { freeifaddrs(addresses) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let interface = pointer.pointee
      guard
        let name = interface.ifa_name.map({ String(cString: $0) }),
        name == "en0" || name == "awdl0",
        let address = interface.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET)
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
          nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      let printable = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
      guard let numeric = String(bytes: printable, encoding: .utf8) else { continue }
      lines.append(name + ": " + numeric)
    }
    return Section(title: "Network", lines: lines.isEmpty ? [Self.nothing] : lines)
  }

  /// The pairings this device can serve or ask through.
  ///
  /// Identifiers only, and only their first bytes: a pairing names two
  /// devices and nothing about the person holding either.
  private static func pairings() -> Section {
    let vault = RappDeviceVault()
    var lines: [String] = []
    do {
      let active = try vault.activePairIDs()
      lines.append("active: \(active.count)")
      for pairID in active {
        lines.append("id: " + pairID.map { String(format: "%02x", $0) }.joined())
      }
      if let selected = try vault.selectedPairID() {
        lines.append("selected: " + Self.shortIdentifier(selected))
      } else {
        lines.append("selected: none")
      }
    } catch {
      lines.append("vault error: \(error)")
    }
    return Section(title: "Pairings", lines: lines)
  }

  /// The leading bytes of an identifier, which is enough to tell two apart.
  private static func shortIdentifier(_ identifier: Data) -> String {
    identifier.prefix(Self.identifierPrefixLength)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  /// How a contactless signature obtains PIN1.
  ///
  /// Presence only. A diagnostic must never read or print the digits.
  private static func credentialPolicy() -> Section {
    let contents = CardCredentialStore.contents()
    var lines = [
      "CAN stored: " + Self.yesNo(contents.hasCardAccessNumber),
      "PIN 1 stored: " + Self.yesNo(contents.hasPin1),
      "policy: direct use, no software expiry",
    ]
    if OnDemandPinExperiment.isEnabled {
      lines.append(
        "on-demand PIN experiment: active (native prompt only without stored credential)")
    }
    return Section(
      title: "Contactless signing credential",
      lines: lines)
  }

  /// Which transports the platform can offer.
  ///
  /// Selection is automatic: the extension serves whichever live slot
  /// CryptoTokenKit gives it.
  private static func transportPolicy() -> Section {
    Section(
      title: "Transport policy",
      lines: [
        "selection: automatic",
        "platform offers near field: " + Self.yesNo(SupportedCardTransports.offersNearField),
      ])
  }

  /// Why raw keychain item counts are not collected here.
  ///
  /// A `com.apple.token` identity/certificate/key search is active on
  /// iOS, even with authentication UI skipped: it was measured opening a
  /// "Ready to Scan" sheet from the diagnostics screen. The typed store
  /// sections above already report the app-owned records without a broad
  /// keychain search, and the token watcher reports ctkd's published
  /// state without waking a card.
  private static func keychainCounts() -> Section {
    Section(
      title: "Keychain items",
      lines: [
        "token identity/certificate/key: not queried (would request NFC)",
        "app records: reported by the typed sections above",
      ])
  }

  /// What the extensions left behind, oldest first.
  private static func extensionTrace() -> Section {
    let trace = ExtensionTrace.read()
    return Section(
      title: "Extension trace (\(trace.count))",
      lines: trace.isEmpty ? ["(nothing recorded)"] : trace)
  }

  /// A boolean as something readable in a list of facts.
  private static func yesNo(_ value: Bool) -> String {
    value ? "yes" : "no"
  }
}
