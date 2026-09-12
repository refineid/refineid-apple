// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation
  import Security

  /// The cable-side debug surface: one type that owns every launch mode a
  /// Mac can drive this app with, so the app initializer stays a list of
  /// calls rather than a pile of flag tests.
  ///
  /// Every fix in the reference implementation came from an instrument, not
  /// from reasoning, and on iOS 26 there is no instrument left on the
  /// outside: `log stream --device` is gone, `log collect` fails, and an app
  /// extension's logging is invisible unless it writes somewhere the app can
  /// read. Without modes like these a failure on this device is
  /// indistinguishable from any other failure. Each mode prints to stdout,
  /// flushes, and exits with a status, so
  /// `xcrun devicectl device process launch --console` captures a whole run
  /// without one tap on the device.
  ///
  /// Two kinds of mode, and the difference is the scene:
  ///
  /// - ``DebugLaunchMode/diagnostics``, ``DebugLaunchMode/forgetCan``,
  ///   ``DebugLaunchMode/resetCardState``, ``DebugLaunchMode/setCan``,
  ///   ``DebugLaunchMode/setPin1`` and ``DebugLaunchMode/trace`` only read
  ///   or write this device's own state. They run from the app initializer, before any window exists,
  ///   and exit there.
  /// - ``DebugLaunchMode/prime`` needs a live scene: CoreNFC will not open
  ///   a slot for a process with no foreground window. It is handed to
  ///   ``DebugSceneRunnerView``, which runs it on appear and exits.
  ///
  /// Exit status is the contract: zero when the mode achieved what it was
  /// asked for, non-zero when it did not -- a priming run that stored the
  /// card but never registered it fails, and so does a `--trace` with
  /// nothing to print, because "the extension never ran" is the answer a
  /// script most needs to branch on.
  ///
  /// DEBUG ONLY. Every declaration in this file and in the types it names
  /// sits inside `#if DEBUG`, so a release build contains none of it: no
  /// flag parsing, no reset, and above all no way to write a credential
  /// from a command line.
  ///
  /// No mode prints a PIN, a card access number, a serial or a holder name.
  /// The two credential modes read their value from the command line at
  /// each launch -- a value is never committed, never defaulted, and never
  /// echoed back; only its length and whether the store accepted it.
  ///
  /// Provenance: `--dump-ctk`, `--ctk-reset`, `--test-sign` and the
  /// `--prime-*` family in the donor
  /// `platform/apple/RefineID/Shared/RefineIDApp.swift`.
  internal enum DebugLaunchModes {
    /// A target is a host and a port.
    private static let hostAndPort = 2

    /// Enough of an identifier to name one pairing.
    private static let identifierPrefixLength = 4

    /// The name of the variable carrying an offer to pair with.
    internal static let offerVariable = "REFINEID_PAIR_OFFER"

    /// The selected mode when it needs a window, otherwise nil.
    ///
    /// The app roots its scene in ``DebugSceneRunnerView`` when this is
    /// set, so the mode has a foreground window to run in.
    internal static var sceneMode: DebugLaunchMode? {
      guard let mode = Self.selected(), mode.needsScene else { return nil }
      return mode
    }

    /// Runs the selected mode if it does not need a window, then exits.
    ///
    /// Returns without doing anything when no mode was named, or when the
    /// named one is waiting for the scene instead.
    internal static func runBeforeScene() {
      guard let mode = Self.selected(), !mode.needsScene else { return }
      let report = Self.report(for: mode)
      DebugConsole.emit(report.lines)
      DebugConsole.finish(succeeded: report.succeeded)
    }

    /// The first mode named on the command line, or nil.
    internal static func selected() -> DebugLaunchMode? {
      let arguments = ProcessInfo.processInfo.arguments
      return DebugLaunchMode.allCases.first { arguments.contains($0.rawValue) }
    }

    /// Runs one mode that needs no window.
    internal static func report(for mode: DebugLaunchMode) -> DebugModeReport {
      switch mode {
      case .activationProbe, .browseProbe, .ctkSignProbe, .listenProbe, .managementProbe,
        .offerRemoteReader, .openSafari, .pairWithOffer, .prime, .remoteSignProbe:
        DebugModeReport(
          lines: [mode.rawValue + ": needs a live scene; it is run from the window instead"],
          succeeded: false)

      case .diagnostics:
        DebugModeReport(lines: DebugDiagnosticsReport.lines(), succeeded: true)

      case .forgetCan:
        Self.forgetCardAccessNumber()

      case .paceCheck:
        DebugPaceCheck.perform()

      case .resetCardState:
        DebugModeReport(lines: DebugCardStateReset.perform(), succeeded: true)

      case .setCan, .setPin1, .setPin2:
        Self.credentialReport(for: mode)

      case .localNetworkProbe:
        #if canImport(Network)
          Self.localNetworkReport()
        #else
          DebugModeReport(lines: [mode.rawValue + ": no network stack"], succeeded: false)
        #endif

      case .selectPair:
        Self.selectPairReport()

      case .remoteIdentityProbe:
        #if os(iOS) || os(macOS)
          DebugRemoteIdentityProbe.report()
        #else
          DebugModeReport(
            lines: [mode.rawValue + ": asks a paired phone, which only iOS does"],
            succeeded: false)
        #endif

      case .signDocument, .signProbe, .tokenPublishProbe, .trace:
        Self.probeReport(for: mode)
      }
    }

    #if canImport(Network)
      /// Reads the target from the command line and tries to reach it.
      private static func localNetworkReport() -> DebugModeReport {
        let value = Self.pathValue(after: .localNetworkProbe) ?? ""
        let parts = value.split(separator: ":")
        guard parts.count == Self.hostAndPort, let port = UInt16(parts[1]) else {
          return DebugModeReport(
            lines: ["usage: --local-network-probe <host>:<port>"],
            succeeded: false)
        }
        return DebugLocalNetworkProbe.report(host: String(parts[0]), port: port)
      }
    #endif

    /// Chooses the pairing whose identifier starts with the given prefix.
    private static func selectPairReport() -> DebugModeReport {
      guard let prefix = Self.pathValue(after: .selectPair), !prefix.isEmpty else {
        return DebugModeReport(
          lines: ["usage: --select-pair <identifier prefix>"], succeeded: false)
      }
      let vault = RappDeviceVault()
      guard
        let match = ((try? vault.activePairIDs()) ?? []).first(where: { pairID in
          pairID.prefix(Self.identifierPrefixLength)
            .map { String(format: "%02x", $0) }
            .joined()
            .hasPrefix(prefix)
        })
      else {
        return DebugModeReport(lines: ["no pairing starts with \(prefix)"], succeeded: false)
      }
      do {
        try vault.selectPair(pairID: match)
        return DebugModeReport(lines: ["selected \(prefix)"], succeeded: true)
      } catch {
        return DebugModeReport(lines: ["could not select: \(error)"], succeeded: false)
      }
    }

    /// The modes that drive a reader or read what one left behind.
    private static func probeReport(for mode: DebugLaunchMode) -> DebugModeReport {
      switch mode {
      case .signDocument:
        Self.documentSignatureReport()

      case .signProbe:
        Self.signProbeReport()

      case .tokenPublishProbe:
        TokenPublishProbe.report()

      default:
        Self.traceReport()
      }
    }

    /// Signs a document with the card; a Mac-only mode, because it
    /// drives a reader.
    private static func documentSignatureReport() -> DebugModeReport {
      #if os(macOS)
        return DebugDocumentSignature.report(
          path: Self.pathValue(after: .signDocument)
        )
      #else
        return DebugModeReport(
          lines: [DebugLaunchMode.signDocument.rawValue + ": macOS only"],
          succeeded: false
        )
      #endif
    }

    /// The unvalidated argument after a mode, for the modes whose
    /// value is a path rather than digits.
    private static func pathValue(after mode: DebugLaunchMode) -> String? {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: mode.rawValue),
        arguments.index(after: index) < arguments.endIndex
      else {
        return nil
      }
      let candidate = arguments[arguments.index(after: index)]
      return candidate.isEmpty ? nil : candidate
    }

    /// Signs against the card with the PIN1 given after `--sign-probe`.
    ///
    /// The digits are read from the command line at each launch and are
    /// neither stored nor echoed: only how many arrived, which is what
    /// catches a shell that ate a leading zero.
    private static func signProbeReport() -> DebugModeReport {
      guard let pin = Self.value(after: .signProbe) else {
        return DebugModeReport(
          lines: [DebugLaunchMode.signProbe.rawValue + ": expected digits directly after the flag"],
          succeeded: false)
      }
      return SignProbe.report(pin: pin)
    }

    /// Stores the card access number given after `--set-can`.
    private static func storeCardAccessNumber() -> DebugModeReport {
      Self.storeCredential(
        named: "set-can",
        digits: Self.value(after: .setCan),
        save: CardCredentialStore.save(cardAccessNumber:))
    }

    /// Drops the stored card access number, every copy of it.
    ///
    /// `CardCredentialStore.forgetCardAccessNumber` deletes the keychain
    /// item and, on macOS, withdraws the driver-configuration copy the
    /// token extension reads -- the pair whose halves must never part.
    /// The report says what remains rather than what was done.
    private static func forgetCardAccessNumber() -> DebugModeReport {
      CardCredentialStore.forgetCardAccessNumber()
      let remains = CardCredentialStore.contents().hasCardAccessNumber
      return DebugModeReport(
        lines: ["forget-can: " + (remains ? "a stored number remains" : "nothing stored remains")],
        succeeded: !remains)
    }

    private static func credentialReport(for mode: DebugLaunchMode) -> DebugModeReport {
      switch mode {
      case .setCan:
        Self.storeCardAccessNumber()
      case .setPin1:
        Self.storePin1()
      case .setPin2:
        Self.storePin2()
      default:
        DebugModeReport(lines: [], succeeded: false)
      }
    }

    /// Stores the PIN1 given after `--set-pin1`.
    private static func storePin1() -> DebugModeReport {
      Self.storeCredential(
        named: "set-pin1",
        digits: Self.value(after: .setPin1),
        save: CardCredentialStore.save(pin1:))
    }

    /// Stores the PIN2 given after `--set-pin2`.
    private static func storePin2() -> DebugModeReport {
      Self.storeCredential(
        named: "set-pin2",
        digits: Self.value(after: .setPin2),
        save: CardCredentialStore.save(pin2:))
    }

    /// Writes one credential and reports what the keychain said.
    ///
    /// The keychain status is printed rather than a yes or a no. A refused
    /// write and a write the platform would not build an access control for
    /// are different faults with the same shape from outside, and the
    /// status is what tells them apart. The digits themselves are never
    /// printed -- only how many there were, which is what catches a shell
    /// that ate a leading zero.
    private static func storeCredential(
      named name: String,
      digits: String?,
      save: (String) -> OSStatus
    ) -> DebugModeReport {
      guard let digits else {
        return DebugModeReport(
          lines: [name + ": expected digits directly after the flag"],
          succeeded: false)
      }
      let status = save(digits)
      let stored = status == errSecSuccess
      return DebugModeReport(
        lines: ["\(name): \(stored ? "stored" : "refused") (os \(status))"],
        succeeded: stored)
    }

    /// Prints what the token extension left in the shared trace.
    private static func traceReport() -> DebugModeReport {
      let trace = ExtensionTrace.read()
      guard !trace.isEmpty else {
        return DebugModeReport(
          lines: ["=== extension trace ===", "(nothing recorded)", "=== end ==="],
          succeeded: false)
      }
      return DebugModeReport(
        lines: ["=== extension trace (\(trace.count) lines) ==="] + trace + ["=== end ==="],
        succeeded: true)
    }

    /// The offer to pair with, or an empty string.
    ///
    /// It arrives in the environment rather than after the flag, because
    /// the device tool repeats its own `--arguments` option into the
    /// argument list and the value after a flag is that option, not the
    /// value meant for it.
    ///
    /// It is a bearer secret for as long as it lives, so it is read here
    /// and never printed, stored or defaulted.
    internal static func offerURI() -> String {
      ProcessInfo.processInfo.environment[offerVariable] ?? ""
    }

    /// The digits following a value-taking flag, or nil.
    ///
    /// Refuses anything that is not digits, and refuses to look at all for
    /// a mode that takes no value -- a flag that consumed the next argument
    /// by accident would store whatever happened to follow it.
    private static func value(after mode: DebugLaunchMode) -> String? {
      guard mode.takesValue else { return nil }
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: mode.rawValue),
        arguments.index(after: index) < arguments.endIndex
      else {
        return nil
      }
      let candidate = arguments[arguments.index(after: index)]
      guard !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else { return nil }
      return candidate
    }
  }

#endif
