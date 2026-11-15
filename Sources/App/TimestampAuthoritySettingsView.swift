// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import SwiftUI

  /// The Time Stamp pane: the one service signatures ask.
  ///
  /// The field edits a draft; only an address that passes a probe is
  /// stored, so closing the pane with an unproven draft reverts to
  /// the configured address. The badge after the field shows the
  /// draft's verdict: a check for verified, a cross for refused or
  /// silent, a question without a connection, an exclamation for
  /// anything subtler. Its tooltip and VoiceOver label carry the
  /// verdict and its time.
  internal struct TimestampAuthoritySettingsView: View {
    private static let badgeSize: CGFloat = 20
    private static let contentSpacing: CGFloat = 8
    private static let contentWidth: CGFloat = 420
    private static let rowSpacing: CGFloat = 6

    @StateObject private var model = TimestampSettingsModel()

    /// The draft resolves to another authority than the shipped one.
    private var isChanged: Bool {
      TimestampAuthorityStore.resolvedRequestAddress(model.draft)
        != .some(TimestampAuthorityStore.defaultAuthority)
    }

    /// The badge for the draft, when it has one to show.
    private var badgeSymbol: String? {
      guard !model.testing else {
        return nil
      }
      if !TimestampAuthorityStore.isUsable(model.draft) {
        let blank = model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return blank ? nil : TimestampClient.Failure.unclearBadgeSymbol
      }
      guard let verdict = model.verification else {
        return nil
      }
      if verdict.succeeded {
        return TimestampClient.Failure.verifiedBadgeSymbol
      }
      return verdict.badge ?? TimestampClient.Failure.unclearBadgeSymbol
    }

    /// What the tooltip and VoiceOver say about the draft.
    private var badgeDescription: String {
      if model.testing {
        String(localized: "Testing…")
      } else if !TimestampAuthorityStore.isUsable(model.draft) {
        if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          String(localized: "Not tested")
        } else {
          String(localized: "Not a usable address")
        }
      } else if let verdict = model.verification {
        verdictDescription(verdict)
      } else {
        String(localized: "Not tested")
      }
    }

    @ViewBuilder private var badgeView: some View {
      Group {
        if model.testing {
          ProgressView()
            .controlSize(.small)
        } else if let symbol = badgeSymbol {
          Image(systemName: symbol)
            .foregroundStyle(badgeColor(for: symbol))
            .accessibilityLabel(badgeDescription)
        } else {
          Color.clear
        }
      }
      .frame(width: Self.badgeSize, height: Self.badgeSize)
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier("timestampStatusBadge")
      .accessibilityLabel(badgeDescription)
      .help(badgeDescription)
    }

    internal var body: some View {
      VStack(alignment: .leading, spacing: Self.contentSpacing) {
        Text(String(localized: "Qualified timestamp server"))
        HStack(spacing: Self.rowSpacing) {
          TextField(
            String(localized: "Qualified timestamp server"),
            text: $model.draft
          )
          .accessibilityIdentifier("timestampAuthorityField")
          .onChange(of: model.draft) { _, _ in model.draftChanged() }
          badgeView
        }
        if isChanged {
          Button(String(localized: "Restore Defaults")) {
            model.restoreDefaults()
          }
          .accessibilityIdentifier("timestampRestoreButton")
        }
      }
      .frame(maxWidth: Self.contentWidth)
      .padding()
      .onAppear {
        model.revertToStored()
        model.draftChanged()
      }
    }

    /// The badge's color.
    private func badgeColor(for symbol: String) -> Color {
      if symbol == TimestampClient.Failure.verifiedBadgeSymbol {
        .green
      } else if symbol == TimestampClient.Failure.unansweredBadgeSymbol {
        .red
      } else {
        .orange
      }
    }

    /// The verdict and its time, with a next step when it failed.
    private func verdictDescription(
      _ verdict: TimestampAuthorityStore.Verification
    ) -> String {
      let when = verdict.date.formatted(date: .abbreviated, time: .shortened)
      if verdict.succeeded {
        return String(localized: "Verified \(when)")
      }
      let next = String(localized: "Check the address and test again.")
      if let reason = verdict.reason {
        return String(localized: "Failed \(when): \(reason)") + " " + next
      }
      return String(localized: "Failed \(when)") + " " + next
    }
  }

#endif
