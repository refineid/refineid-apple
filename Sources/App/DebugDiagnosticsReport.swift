// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation

  /// Everything the diagnostics screen shows, as text on stdout, plus the
  /// two things it cannot show.
  ///
  /// The screen is the wrong instrument over a cable: it needs a tap to
  /// reach and a photograph to record. ``DiagnosticsSnapshot`` is the same
  /// reading with a text form already on it, so this prints that rather
  /// than assembling a second, drifting copy of it -- the screen and the
  /// cable must never be able to disagree about what this device holds.
  ///
  /// Two blocks are added around it. Versions, because a measurement taken
  /// against a stale install is the most expensive kind of wrong answer.
  /// And the live reader and card, because the snapshot deliberately
  /// touches no card -- it is drawn while a holder is looking at it --
  /// whereas a cable-driven run has nobody to disturb and every reason to
  /// ask what is actually in the slot.
  ///
  /// Deliberately not localized, for the same reason the snapshot is not: a
  /// diagnostic that changes wording with the device language cannot be
  /// diffed against yesterday's capture.
  ///
  /// DEBUG only.
  internal enum DebugDiagnosticsReport {
    /// Carries the card reading back out of the bridging task.
    ///
    /// The semaphore below is the barrier: the value is written once before
    /// the signal and read once after the wait, so there is no moment when
    /// both sides touch it. Same shape as ``TokenPublishProbe``'s box, for
    /// the same reason -- a snapshot is not `Sendable` and the capture is
    /// `async`.
    private final class Capture: @unchecked Sendable {
      var snapshot: CardStatusSnapshot?
    }

    /// Radix an unexpected status word is printed in.
    private static let hexRadix: Int = 16

    /// Line break the snapshot's text form uses.
    private static let newline: String = "\n"

    /// The whole report, one line per fact.
    internal static func lines() -> [String] {
      var report = ["=== RefineID diagnostics ==="]
      report += Self.versionLines()
      report += DiagnosticsSnapshot.collect().text.components(separatedBy: Self.newline)
      report += Self.cardLines(Self.capturedSnapshot())
      report.append("=== end ===")
      return report
    }

    /// What is actually bundled, so a stale install is visible at once.
    private static func versionLines() -> [String] {
      let versions = BundledVersions.read(from: .main)
      return [
        "== Versions ==",
        "app: " + (versions.applicationWithSource ?? "unreadable"),
        "driver: " + (versions.driver ?? "not embedded"),
        "",
      ]
    }

    /// What the reader and the card in it report right now.
    private static func cardLines(_ snapshot: CardStatusSnapshot?) -> [String] {
      var lines = ["", "== Card and reader =="]
      guard let snapshot else {
        lines.append("capture produced no reading")
        return lines
      }
      lines.append("reader: " + (snapshot.readerName ?? "none attached"))
      switch snapshot.card {
      case .failed(let failure):
        lines.append("card: failed - " + Self.label(for: failure))

      case .noCard:
        lines.append("card: no card in the reader")

      case .sealed:
        lines.append("card: identity card, contactless interface (sealed until PACE)")

      case .supported(let report, let name):
        lines.append("card: supported" + (name.map { " - " + $0 } ?? ""))
        lines.append("pin1: " + Self.label(for: report.pin1))
        lines.append("pin2: " + Self.label(for: report.pin2))
        lines.append("puk: " + Self.label(for: report.puk))
        #if os(macOS)
          lines.append(contentsOf: Self.allowanceLines())
        #endif

      case .unsupported:
        lines.append("card: present but not a FINEID card")
      }
      lines.append("token published for this card: " + Self.yesNo(snapshot.safariIdentityPresent))
      return lines
    }

    #if os(macOS)
      /// What the card says about how often each credential may still
      /// be used - the numbers beside the retry counter in the same
      /// container, which decide whether a PUK survives being used.
      private static func allowanceLines() -> [String] {
        let readings = CardAllowanceProbe.read()
        guard !readings.isEmpty else {
          return ["allowances: not readable"]
        }
        return readings.map { entry in
          "allowances \(entry.name): "
            + "usages=\(Self.describe(entry.allowances.usages)) "
            + "unblockings=\(Self.describe(entry.allowances.unblockings))"
        }
      }

      /// One allowance in words.
      private static func describe(_ allowance: CredentialAllowance) -> String {
        switch allowance {
        case .remaining(let count):
          String(count)

        case .unlimited:
          "unlimited"
        }
      }
    #endif

    /// Runs the asynchronous card capture from a synchronous caller.
    ///
    /// The diagnostics mode runs in the app initializer, before any window
    /// or run loop the capture could be awaited from, so the main thread
    /// waits here. The capture does its blocking card work on a global
    /// queue, so this cannot deadlock against itself.
    private static func capturedSnapshot() -> CardStatusSnapshot? {
      let capture = Capture()
      let semaphore = DispatchSemaphore(value: 0)
      Task {
        capture.snapshot = await CardStatusSnapshot.capture()
        semaphore.signal()
      }
      semaphore.wait()
      return capture.snapshot
    }

    private static func label(for failure: CardStatusSnapshot.CaptureFailure) -> String {
      switch failure {
      case .cardUnreadable:
        "card answered but not readably"

      case .serviceUnavailable:
        "no smart-card service on this device"

      case .sessionUnavailable:
        "exclusive session refused"
      }
    }

    private static func label(for outcome: RetryProbeOutcome) -> String {
      switch outcome {
      case .invalidated:
        "invalidated"

      case .locked:
        "locked"

      case .noInformation:
        "no information"

      case .other(let statusWord):
        "unexpected sw " + String(statusWord, radix: Self.hexRadix, uppercase: true)

      case .remaining(let count):
        "\(count.attemptsRemaining) attempts remaining"

      case .verified:
        "verified in this session"
      }
    }

    private static func yesNo(_ value: Bool) -> String {
      value ? "yes" : "no"
    }
  }

#endif
