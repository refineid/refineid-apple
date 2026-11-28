// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The common key artwork for every route into PIN management.
///
/// Tint is reinforced by a differently shaped system badge and a VoiceOver
/// value, so health is never communicated by color alone.
internal struct CredentialRetryHealthKey: View {
  /// The badge rides on the key glyph, small enough not to hide it.
  private enum Layout {
    static let badgeGlyphSize: CGFloat = 8
  }

  private static var uiAutomationDisablesMotion: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--ui-test-disable-motion")
    #else
      false
    #endif
  }

  internal let level: CredentialRetryHealth.Level?
  internal let systemName: String

  /// Whether the route this key opens can be taken right now.
  ///
  /// An unprobed key on an open route is green -- no known issue --
  /// while a closed route greys out like its row.
  internal let routeAvailable: Bool

  /// Whether EstEID 2025 enforces changing its initial PIN 2 before
  /// qualified signing is allowed.
  internal let pin2RequiresChange: Bool

  @Environment(\.accessibilityReduceMotion)
  private var reduceMotion
  @State private var animationTrigger = false

  internal var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Image(systemName: systemName)
        .font(.system(size: PersonRowLabel.iconPointSize))
        .symbolRenderingMode(.monochrome)
        .replacingSymbol()
        .foregroundStyle(keyStyle)
      overlayBadge
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Change or Reset PINs"))
    .accessibilityValue(
      Self.accessibilityValueText(
        level: displayedLevel,
        showsPin2ChangeWarning: showsPin2ChangeWarning
      )
    )
    .onAppear { animateIfNeeded(displayedLevel) }
    .onValueChange(of: displayedLevel) { newLevel in
      animateIfNeeded(newLevel)
    }
  }

  private var keyStyle: AnyShapeStyle {
    if showsPin2ChangeWarning {
      return AnyShapeStyle(Color.orange)
    }
    if let shown = displayedLevel {
      return AnyShapeStyle(shown.color)
    }
    return routeAvailable
      ? AnyShapeStyle(Color.green)
      : AnyShapeStyle(Color.secondary)
  }

  @ViewBuilder private var overlayBadge: some View {
    if showsPin2ChangeWarning {
      badge(symbol: CredentialRetryHealth.Level.warning.badge, color: .orange)
    } else if let shown = displayedLevel {
      statusBadge(shown)
    }
  }

  /// A closed route never wears a cached health level.
  ///
  /// The keys grey out with their row until the card is verified
  /// again, whatever the last report said.
  private var displayedLevel: CredentialRetryHealth.Level? {
    routeAvailable ? level : nil
  }

  private var showsPin2ChangeWarning: Bool {
    Self.showsPin2ChangeWarning(
      level: level,
      routeAvailable: routeAvailable,
      pin2RequiresChange: pin2RequiresChange
    )
  }

  internal init(
    level: CredentialRetryHealth.Level?,
    systemName: String,
    routeAvailable: Bool
  ) {
    self.init(
      level: level,
      systemName: systemName,
      routeAvailable: routeAvailable,
      pin2RequiresChange: false
    )
  }

  internal init(
    level: CredentialRetryHealth.Level?,
    systemName: String,
    routeAvailable: Bool,
    pin2RequiresChange: Bool
  ) {
    self.level = level
    self.systemName = systemName
    self.routeAvailable = routeAvailable
    self.pin2RequiresChange = pin2RequiresChange
  }

  /// Orange initial-PIN-2 attention shows on an open route whenever
  /// PIN 2 still needs changing and no credential is in critical red
  /// recovery (red takes precedence, matching macOS `PinCodesButton`).
  internal static func showsPin2ChangeWarning(
    level: CredentialRetryHealth.Level?,
    routeAvailable: Bool,
    pin2RequiresChange: Bool
  ) -> Bool {
    routeAvailable && pin2RequiresChange && level != .critical
  }

  internal static func accessibilityValueText(
    level: CredentialRetryHealth.Level?,
    showsPin2ChangeWarning: Bool
  ) -> String {
    if showsPin2ChangeWarning {
      let pin2Notice = String(localized: "Change PIN 2 so you can sign documents.")
      if let level, level == .warning {
        return "\(level.accessibilityValue). \(pin2Notice)"
      }
      return pin2Notice
    }
    return level?.accessibilityValue ?? ""
  }

  @ViewBuilder
  private func statusBadge(
    _ level: CredentialRetryHealth.Level
  ) -> some View {
    switch level {
    case .pristine:
      badge(symbol: level.badge, color: level.color)

    case .warning:
      badge(symbol: level.badge, color: level.color)
        .pulsingSymbol(value: animationTrigger)

    case .critical:
      badge(symbol: level.badge, color: level.color)
        .bouncingSymbol(value: animationTrigger)
    }
  }

  private func badge(symbol: String, color: Color) -> some View {
    Image(systemName: symbol)
      .accessibilityHidden(true)
      .font(.system(size: Layout.badgeGlyphSize, weight: .bold))
      .foregroundStyle(color)
      .background(.background, in: Circle())
  }

  /// Motion calls attention only to degraded states.
  ///
  /// Yielding one render pass lets an initially degraded badge exist
  /// before its effect begins. Yellow pulses once; red repeats until the
  /// state changes. There is no timing constant, and Reduce Motion
  /// suppresses both. UI automation also opts out: XCTest waits for
  /// animation quiescence before taps, while the red state intentionally
  /// never becomes quiescent for a holder.
  private func animateIfNeeded(_ level: CredentialRetryHealth.Level?) {
    guard
      !reduceMotion,
      !Self.uiAutomationDisablesMotion,
      level == .warning || level == .critical
    else { return }
    Task { @MainActor in
      await Task.yield()
      animationTrigger.toggle()
    }
  }
}
