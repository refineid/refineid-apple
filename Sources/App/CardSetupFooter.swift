// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// What sits under the setup screen, when anything does.
///
/// A demonstration says so for as long as it runs, in the place a
/// development build offers its diagnostics. A shipped build doing the
/// job it was installed for has neither, and this is empty: the setup
/// screen ends at its last product control.
internal struct CardSetupFooter: View {
  private static let basePadding: CGFloat = 12
  private static let padding = basePadding
  private static let verticalPadding = basePadding
  private static let demoBackgroundRedComponent: Double = 0.68
  private static let demoBackgroundGreenComponent: Double = 0.04
  private static let demoBackgroundBlueComponent: Double = 0.04

  #if DEBUG
    /// Read from the bundle at run time: the stamp scripts renumber
    /// every install, and a hardcoded copy would trail them.
    private static let diagnosticsTitle: String = {
      let info = Bundle.main.infoDictionary
      let version = info?["CFBundleShortVersionString"] as? String ?? ""
      let build = info?["CFBundleVersion"] as? String ?? ""
      return String(localized: "Diagnostics") + " - \(version) (\(build))"
    }()
  #endif

  /// Whether this run is demonstrating the flow without a card.
  internal let isDemonstration: Bool

  internal var body: some View {
    if isDemonstration {
      demonstration
    } else {
      development
    }
  }

  /// The standing notice that nothing on the screen came off a card.
  ///
  /// A warning bar and not a caption: it names the mode in capitals, on
  /// red, across the whole width and into the home indicator, because
  /// the one thing a person must never do with this screen is believe
  /// it. No symbol beside it -- the bar is the signal, and a small
  /// picture next to shouted text only makes the text smaller.
  ///
  /// White on a dark red rather than green on red. Red and green are the
  /// pair most colour-blind readers cannot separate, while the darker red
  /// keeps the standing warning above the text contrast floor in every
  /// appearance without relying on colour as its only signal.
  @ViewBuilder private var demonstration: some View {
    #if os(iOS) || os(macOS)
      if !ProcessInfo.processInfo.arguments.contains("--hide-diagnostics") {
        #if os(iOS)
          Text("DEMO MODE")
            .font(.headline)
            .foregroundStyle(.white)
            .accessibilityIdentifier("demoModeNotice")
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity)
            .background(
              Color(
                red: Self.demoBackgroundRedComponent,
                green: Self.demoBackgroundGreenComponent,
                blue: Self.demoBackgroundBlueComponent
              ),
              ignoresSafeAreaEdges: .bottom)
        #else
          Text("DEMO MODE")
            .font(.headline)
            .foregroundStyle(.white)
            .accessibilityIdentifier("demoModeNotice")
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity)
            .background(
              Color(
                red: Self.demoBackgroundRedComponent,
                green: Self.demoBackgroundGreenComponent,
                blue: Self.demoBackgroundBlueComponent
              ))
        #endif
      }
    #endif
  }

  /// The route into diagnostics, in development builds only, named
  /// with the exact build it belongs to.
  @ViewBuilder private var development: some View {
    VStack(spacing: 0) {
      #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--hide-diagnostics") {
          NavigationLink {
            DiagnosticsView()
          } label: {
            Label(Self.diagnosticsTitle, systemImage: "stethoscope")
          }
          .accessibilityIdentifier("diagnosticsButton")
          .padding(.vertical, Self.padding)
          .frame(maxWidth: .infinity)
          .background(.bar)
        }
      #endif
      #if os(iOS) && (DEBUG || TESTFLIGHT)
        NavigationLink {
          CardTimingView()
        } label: {
          Label(String(localized: "Card Timing"), systemImage: "stopwatch")
        }
        .accessibilityIdentifier("cardTimingButton")
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity)
        .background(.bar)
      #endif
    }
  }
}
