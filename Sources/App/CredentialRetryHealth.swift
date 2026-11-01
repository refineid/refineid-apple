// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Session-only presentation of one complete, side-effect-free retry probe.
///
/// No counter is persisted. Card management publishes reports it already
/// needed; reader insertion may also start one narrow, cancellable counter
/// probe. There is no polling, and identity presentation never waits for it.
@MainActor
internal final class CredentialRetryHealth: ObservableObject {
  private enum RetryThreshold {
    static let lowAttempts: UInt8 = 2
    static let zeroAttempts: UInt8 = 0
  }

  // MARK: Nested Types

  internal enum Level: Equatable {
    case pristine
    case warning
    case critical

    // MARK: Computed Properties

    internal var color: Color {
      switch self {
      case .pristine:
        .green

      case .warning:
        .yellow

      case .critical:
        .red
      }
    }

    internal var badge: String {
      switch self {
      case .pristine:
        "checkmark.circle.fill"

      case .warning:
        "exclamationmark.triangle.fill"

      case .critical:
        "xmark.octagon.fill"
      }
    }

    internal var accessibilityValue: String {
      switch self {
      case .pristine:
        String(localized: "All credential attempts are available")

      case .warning:
        String(localized: "A credential has fewer than five attempts remaining")

      case .critical:
        String(localized: "A credential is blocked or has at most two attempts remaining")
      }
    }
  }

  /// The only useful destination while the key is critical.
  ///
  /// Both PINs blocked take one form that resets them with one PUK
  /// entry; otherwise PIN 1 wins when both PINs need recovery. A low PUK
  /// removes every operation because both reset commands spend that
  /// counter.
  internal enum Recovery: Equatable {
    case resetPin1
    case resetPin2
    case resetBothPins
    case useOtherSoftware
    case unrecoverable
  }

  // MARK: Static Properties

  internal static let shared = CredentialRetryHealth()

  // MARK: Properties

  @Published internal private(set) var level: Level?
  @Published internal private(set) var recovery: Recovery?

  /// The accepted report behind the level, so the management screen
  /// can name the exact counters the color came from.
  @Published internal private(set) var report: CredentialProbeReport?

  private var readerRefresh: Task<Void, Never>?
  private var refreshGeneration = 0

  // MARK: Lifecycle

  private init() {
    // singleton
  }

  // MARK: Static Functions

  private static func attempts(_ outcome: RetryProbeOutcome) -> UInt8? {
    switch outcome {
    case .remaining(let count):
      count.attemptsRemaining

    case .locked:
      0

    case .invalidated, .noInformation, .other, .verified:
      nil
    }
  }

  /// The destination for one accepted set of counters, or nil while no
  /// counter is at or below the low-attempt ceiling.
  internal static func recovery(pin1: UInt8, pin2: UInt8, puk: UInt8) -> Recovery? {
    if puk == RetryThreshold.zeroAttempts {
      return .unrecoverable
    }
    if puk <= RetryThreshold.lowAttempts {
      return .useOtherSoftware
    }
    if pin1 == RetryThreshold.zeroAttempts, pin2 == RetryThreshold.zeroAttempts {
      return .resetBothPins
    }
    if pin1 <= RetryThreshold.lowAttempts {
      return .resetPin1
    }
    if pin2 <= RetryThreshold.lowAttempts {
      return .resetPin2
    }
    return nil
  }

  // MARK: Functions

  /// Starts one non-blocking retry probe for the newly inserted reader card.
  ///
  /// A replacement or removal invalidates the generation, so a late answer can
  /// never color the key for a card that is no longer present.
  internal func refreshFromReader() {
    cancelReaderRefresh()
    level = nil
    report = nil
    let generation = refreshGeneration
    readerRefresh = Task { [weak self] in
      let freshReport = await CardMaintenance.credentialReport(
        transport: .reader,
        cardAccessNumber: nil
      )
      guard
        !Task.isCancelled,
        let self,
        refreshGeneration == generation
      else { return }
      readerRefresh = nil
      apply(freshReport)
    }
  }

  /// Accepts only a complete and plausible report.
  ///
  /// A locked result is the card's semantic zero; every other non-counter
  /// outcome makes the status unavailable rather than inviting a guess.
  internal func update(_ report: CredentialProbeReport?) {
    cancelReaderRefresh()
    apply(report)
  }

  internal func clear() {
    cancelReaderRefresh()
    recovery = nil
    level = nil
    report = nil
  }

  private func apply(_ report: CredentialProbeReport?) {
    guard let report,
      let pin1 = Self.attempts(report.pin1),
      let pin2 = Self.attempts(report.pin2),
      let puk = Self.attempts(report.puk)
    else {
      recovery = nil
      level = nil
      self.report = nil
      return
    }

    let attempts = [pin1, pin2, puk]
    guard attempts.allSatisfy({ $0 <= RetryCount.pristineAllowance }) else {
      recovery = nil
      level = nil
      self.report = nil
      return
    }
    self.report = report
    recovery = Self.recovery(pin1: pin1, pin2: pin2, puk: puk)
    if attempts.contains(where: { $0 <= RetryThreshold.lowAttempts }) {
      level = .critical
    } else if attempts.allSatisfy({ $0 == RetryCount.pristineAllowance }) {
      level = .pristine
    } else {
      level = .warning
    }
  }

  private func cancelReaderRefresh() {
    refreshGeneration &+= 1
    readerRefresh?.cancel()
    readerRefresh = nil
  }
}
