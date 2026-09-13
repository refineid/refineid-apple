// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation
  import SwiftUI

  /// The window a scene-bound debug mode runs in.
  ///
  /// Two modes cannot run the way the rest do. CoreNFC will not open a
  /// slot for a process with no foreground window, and the system PIN
  /// sheet needs a live run loop. Running either in the app initializer
  /// gets a refusal that looks exactly like a broken card path. This view
  /// exists only to be on screen while the work runs: it prints to stdout
  /// as it goes and exits the process when the work is done, so
  /// `xcrun devicectl device process launch --console` still sees a run
  /// that starts, narrates itself, and ends with a status.
  ///
  /// Progress is printed line by line rather than collected, because both
  /// modes block on a system sheet the holder has to answer. A run that
  /// printed only at the end would say nothing at all about the hold that
  /// never completed.
  ///
  /// DEBUG only.
  ///
  /// Provenance: the auto-starting `SafariIdentityPrimeView` used by
  /// `--prime-safari --prime-auto` in the donor
  /// `platform/apple/RefineID/Local/SafariIdentityPrimeView.swift`.
  internal struct DebugSceneRunnerView: View {
    @Environment(\.scenePhase)
    private var scenePhase
    @State private var hasStarted = false

    /// The mode this window was opened to run.
    internal let mode: DebugLaunchMode

    internal var body: some View {
      VStack {
        if mode == .activationProbe, !hasStarted {
          Button("Start read-only activation probe") {
            hasStarted = true
            Task { await Self.run(mode) }
          }
          .buttonStyle(.borderedProminent)
          .accessibilityHint("Reads card activation state without changing the card")
        } else {
          ProgressView()
        }
        Text(verbatim: "RefineID debug: " + mode.rawValue)
      }
      .padding()
      #if os(macOS)
        .task {
          guard mode != .activationProbe, !hasStarted else { return }
          hasStarted = true
          await Self.run(mode)
        }
      #else
        .task(id: scenePhase) {
          guard mode != .activationProbe, scenePhase == .active, !hasStarted else { return }
          hasStarted = true
          await Self.run(mode)
        }
      #endif
    }

    /// Runs the mode and ends the process with its status.
    private static func run(_ mode: DebugLaunchMode) async {
      switch mode {
      case .browseProbe, .listenProbe, .offerRemoteReader, .pairWithOffer:
        await runPairingMode(mode)

      case .activationProbe:
        #if REFINEID_LOCAL_CARD && os(iOS)
          let report = await CardMaintenance.debugActivationSignals()
          DebugConsole.emit(report.lines)
          DebugConsole.finish(succeeded: report.succeeded)
        #else
          DebugConsole.emit("activation-probe: NFC is unavailable on macOS")
          DebugConsole.finish(succeeded: false)
        #endif

      case .ctkSignProbe:
        let report = await Self.offMainThread(CtkSignProbe.report)
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)

      case .managementProbe:
        DebugConsole.finish(succeeded: await DebugCardManagementProbe.run())

      case .remoteIdentityProbe, .remoteSignProbe:
        await runRelayProbe(mode)

      case .openSafari:
        #if os(iOS)
          await Self.openRequestedPage()
        #else
          DebugConsole.emit([mode.rawValue + ": opens mobile Safari, which only iOS has"])
          DebugConsole.finish(succeeded: false)
        #endif

      case .prime:
        DebugConsole.finish(succeeded: await Self.prime())

      case .diagnostics, .forgetCan, .localNetworkProbe, .paceCheck,
        .resetCardState, .selectPair, .setCan,
        .setPin1, .setPin2, .signDocument, .signProbe, .tokenPublishProbe, .trace:
        DebugConsole.emit(mode.rawValue + ": runs before the window opens, not here")
        DebugConsole.finish(succeeded: false)
      }
    }

    #if os(iOS)
      /// Opens the page named after `--open-safari` and reports whether the
      /// system took it.
      private static func openRequestedPage() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: DebugLaunchMode.openSafari.rawValue),
          arguments.index(after: index) < arguments.endIndex
        else {
          DebugConsole.emit("open-safari: expected an address after the flag")
          DebugConsole.finish(succeeded: false)
        }
        let raw = arguments[arguments.index(after: index)]
        let urlString =
          (raw.hasPrefix("https://") || raw.hasPrefix("http://"))
          ? raw : "https://" + raw
        guard let url = URL(string: urlString) else {
          DebugConsole.emit("open-safari: invalid url: " + raw)
          DebugConsole.finish(succeeded: false)
        }
        let opened = await UIApplication.shared.open(url)
        DebugConsole.emit("open-safari: opened: " + String(opened))
        DebugConsole.finish(succeeded: opened)
      }
    #endif

    /// Runs one of the cable-driven pairing modes.
    ///
    /// Only the four pairing modes reach this; anything else has been
    /// handled by the caller's own switch.
    /// Runs a probe that asks the paired phone, and reports what came back.
    ///
    /// A probe blocks on the relay and hops to the main queue to publish, so
    /// running it on the main thread deadlocks the hop.
    private static func runRelayProbe(_ mode: DebugLaunchMode) async {
      #if os(iOS) || os(macOS)
        let work: @Sendable () -> DebugModeReport =
          mode == .remoteIdentityProbe
          ? DebugRemoteIdentityProbe.report
          : DebugRemoteSignProbe.report
        let report = await Self.offMainThread(work)
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)
      #else
        DebugConsole.emit([mode.rawValue + ": asks a paired phone"])
        DebugConsole.finish(succeeded: false)
      #endif
    }

    private static func runPairingMode(_ mode: DebugLaunchMode) async {
      switch mode {
      case .browseProbe:
        // The type is fixed to what the relay browses, so the probe answers
        // for the path that is failing rather than one that is not used.
        let report = await DebugBrowseProbe.run(type: "_refineid-rly._tcp")
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)

      case .listenProbe:
        let report = await DebugListenProbe.run()
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)

      case .offerRemoteReader:
        let report = await DebugPairWithOffer.offer()
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)

      case .pairWithOffer:
        let report = await DebugPairWithOffer.run(offerURI: DebugLaunchModes.offerURI())
        DebugConsole.emit(report.lines)
        DebugConsole.finish(succeeded: report.succeeded)

      default:
        DebugConsole.emit(mode.rawValue + ": not a pairing mode")
        DebugConsole.finish(succeeded: false)
      }
    }

    /// Runs blocking work off the main thread and waits for it there.
    ///
    /// The signature the extension services blocks inside the Security
    /// framework until the system PIN sheet has been answered. On the main
    /// thread it would block the run loop that has to present that sheet,
    /// so the sheet never appears and the probe reports a refusal nobody
    /// was offered the chance to satisfy.
    private static func offMainThread(
      _ work: @escaping @Sendable () -> DebugModeReport
    ) async -> DebugModeReport {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: work())
        }
      }
    }

    /// Runs the card priming flow with no interface but the system sheet.
    ///
    /// Succeeds only when the card was registered. Priming that stores the
    /// card details and then fails to register leaves a device that looks
    /// set up and cannot log in, which is precisely the failure this mode
    /// exists to catch, so it exits non-zero.
    private static func prime() async -> Bool {
      DebugConsole.emit("=== prime ===")
      #if REFINEID_LOCAL_CARD && os(iOS)
        let contents = CardCredentialStore.contents()
        DebugConsole.emit("card access number stored: \(contents.hasCardAccessNumber)")
        DebugConsole.emit(
          "near field available: \(SupportedCardTransports.offersNearField)")
        guard let pin1 = ProcessInfo.processInfo.environment["REFINEID_DEBUG_PIN1"],
          !pin1.isEmpty
        else {
          DebugConsole.emit("prime: REFINEID_DEBUG_PIN1 is required")
          return false
        }
        guard let storedAccessNumber = CardCredentialStore.displayedCardAccessNumber() else {
          DebugConsole.emit("prime: a stored card access number is required")
          DebugConsole.emit("=== end ===")
          return false
        }
        let outcome = await CardPriming.prime(
          cardAccessNumber: storedAccessNumber,
          pin1: pin1,
          progress: { line in
            DebugConsole.emit("progress: " + line)
          },
          step: { step, state in
            DebugConsole.emit("step: \(step) \(state)")
          })
        DebugConsole.emit("stored: \(outcome.stored)")
        DebugConsole.emit("registered: \(outcome.registered)")
        DebugConsole.emit("summary: " + outcome.summary)
        DebugConsole.emit("primed cards now: \(PrimeStore.storedCount())")
        DebugConsole.emit(
          "registered smart cards now: "
            + "\(TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens.count)")
        DebugConsole.emit("=== end ===")
        return outcome.registered
      #else
        DebugConsole.emit("this platform has no near-field antenna to prime over")
        DebugConsole.emit("=== end ===")
        return false
      #endif
    }
  }

#endif
