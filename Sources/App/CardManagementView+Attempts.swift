// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(macOS)

  /// How a retry counter is shown: the number against a full card, a
  /// colour band, and a marker so the band never rests on colour alone.
  ///
  /// The bands are this app's own rule made visible. A full counter is
  /// not shown at all; below full is orange, because something has
  /// already gone wrong once; one or two is red, the range it refuses
  /// to work in; and zero is blue, because blocked is not a warning but
  /// an instruction - the PUK undoes it.
  extension CardManagementView {
    // MARK: Nested Types

    /// One credential's reading as the bar lists it.
    internal struct AttemptsReading {
      internal let name: String
      internal let outcome: RetryProbeOutcome
      internal let pristineAllowance: UInt8
    }

    private enum AttemptsLayout {
      static let rowSymbolSpacing: CGFloat = 4
      static let attemptsSpacing: CGFloat = 14
      static let barHorizontalPadding: CGFloat = 16
      static let barVerticalPadding: CGFloat = 6
    }

    // MARK: Static Functions

    /// The credentials short of a full counter, in card order; empty
    /// while every counter is full.
    internal static func readingsBelowFull(
      _ report: CredentialProbeReport
    ) -> [AttemptsReading] {
      let allowance = report.pristineAllowance
      return [
        AttemptsReading(
          name: CredentialLabels.name(for: .pin1),
          outcome: report.pin1,
          pristineAllowance: allowance),
        AttemptsReading(
          name: CredentialLabels.name(for: .pin2),
          outcome: report.pin2,
          pristineAllowance: allowance),
        AttemptsReading(name: "PUK", outcome: report.puk, pristineAllowance: allowance),
      ]
      .filter { !isFull($0.outcome, pristineAllowance: $0.pristineAllowance) }
    }

    /// A counter at its full allowance, or a PIN verified this session,
    /// which the card has reset to full.
    private static func isFull(
      _ outcome: RetryProbeOutcome,
      pristineAllowance: UInt8
    ) -> Bool {
      switch outcome {
      case .remaining(let count):
        !count.isBlocked && count.attemptsRemaining >= pristineAllowance

      case .verified:
        true

      case .locked, .invalidated, .noInformation, .other:
        false
      }
    }

    /// The marker beside each count, so the band is never carried by
    /// colour alone.
    private static func attemptsSymbol(
      _ outcome: RetryProbeOutcome?,
      pristineAllowance: UInt8
    ) -> String {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          "arrow.counterclockwise.circle.fill"
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          "xmark.octagon.fill"
        } else if count.attemptsRemaining < pristineAllowance {
          "exclamationmark.triangle.fill"
        } else {
          "checkmark.circle.fill"
        }

      case .verified:
        "checkmark.circle.fill"

      case .locked:
        "arrow.counterclockwise.circle.fill"

      case .invalidated:
        "xmark.octagon.fill"

      case .noInformation, .other, .none:
        "questionmark.circle"
      }
    }

    /// What VoiceOver says for one reading.
    private static func attemptsSpoken(_ outcome: RetryProbeOutcome?) -> String {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          String(localized: "blocked - unblock with the PUK")
        } else if count.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed {
          String(localized: "\(count.attemptsRemaining) attempts remaining")
        } else {
          String(localized: "\(count.attemptsRemaining) attempts remaining - low")
        }

      case .verified:
        String(localized: "verified this session")

      case .locked:
        String(localized: "blocked - unblock with the PUK")

      case .invalidated:
        String(localized: "invalidated - contact the issuer")

      case .noInformation, .other:
        String(localized: "state unknown")

      case .none:
        String(localized: "no card present")
      }
    }

    /// One probe outcome as a short cell, counted against a full card.
    private static func attemptsText(
      _ outcome: RetryProbeOutcome?,
      pristineAllowance: UInt8
    ) -> String {
      switch outcome {
      case .remaining(let count):
        "\(count.attemptsRemaining)/\(pristineAllowance)"

      case .verified:
        String(localized: "verified")

      case .locked:
        String(localized: "blocked")

      case .invalidated:
        String(localized: "invalidated")

      case .noInformation, .other:
        String(localized: "unknown")

      case .none:
        String(localized: "no card")
      }
    }

    /// Full is green, short of full is orange, refused is red, and
    /// blocked is blue - blocked being the one state that is not a
    /// warning but an instruction: the PUK undoes it.
    private static func attemptsColor(
      _ outcome: RetryProbeOutcome?,
      pristineAllowance: UInt8
    ) -> Color {
      switch outcome {
      case .remaining(let count):
        if count.isBlocked {
          .blue
        } else if count.attemptsRemaining < RetryFloor.minimumAttemptsToProceed {
          .red
        } else if count.attemptsRemaining < pristineAllowance {
          .orange
        } else {
          .green
        }

      case .verified:
        .green

      case .locked:
        .blue

      case .invalidated:
        .red

      case .noInformation, .other, .none:
        .secondary
      }
    }

    // MARK: Functions

    /// The counters short of full, pinned along the foot of the window.
    @ViewBuilder
    internal func attemptsBar(_ readings: [AttemptsReading]) -> some View {
      HStack(spacing: AttemptsLayout.attemptsSpacing) {
        Text("Attempts left:")
          .foregroundStyle(.secondary)
        ForEach(readings, id: \.name) { reading in
          attemptsEntry(
            reading.name,
            reading.outcome,
            pristineAllowance: reading.pristineAllowance
          )
        }
        Spacer()
      }
      .font(.footnote)
      .padding(.horizontal, AttemptsLayout.barHorizontalPadding)
      .padding(.vertical, AttemptsLayout.barVerticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
    }

    /// One credential's reading, with a symbol so it never relies on
    /// colour alone.
    @ViewBuilder
    internal func attemptsEntry(
      _ name: String,
      _ outcome: RetryProbeOutcome?,
      pristineAllowance: UInt8
    ) -> some View {
      HStack(spacing: AttemptsLayout.rowSymbolSpacing) {
        Text("\(name) \(Self.attemptsText(outcome, pristineAllowance: pristineAllowance))")
          .monospacedDigit()
        Image(systemName: Self.attemptsSymbol(outcome, pristineAllowance: pristineAllowance))
      }
      .foregroundStyle(Self.attemptsColor(outcome, pristineAllowance: pristineAllowance))
      .accessibilityElement(children: .combine)
      .accessibilityLabel(name)
      .accessibilityValue(Self.attemptsSpoken(outcome))
    }
  }

#endif
