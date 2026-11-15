// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && (FEATURE_SCS || FEATURE_TIMESTAMP_CONFIG || FEATURE_PDF_STAMP)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  internal struct RefineIDSettingsView: View {
    private enum Pane: Hashable {
      #if FEATURE_TIMESTAMP_CONFIG
        case timeStamp
      #endif
      #if FEATURE_PDF_STAMP
        case stamp
      #endif
      #if FEATURE_SCS
        case webSigning
      #endif
    }

    private static let paneWidth: CGFloat = 480
    private static let paneHeight: CGFloat = 200

    #if FEATURE_TIMESTAMP_CONFIG
      @State private var pane = Pane.timeStamp
    #elseif FEATURE_PDF_STAMP
      @State private var pane = Pane.stamp
    #elseif FEATURE_SCS
      @State private var pane = Pane.webSigning
    #endif

    internal var body: some View {
      TabView(selection: $pane) {
        #if FEATURE_TIMESTAMP_CONFIG
          TimestampAuthoritySettingsView()
            .tabItem {
              Label(String(localized: "Time Stamp"), systemImage: "clock.badge.checkmark")
            }
            .tag(Pane.timeStamp)
        #endif
        #if FEATURE_PDF_STAMP
          StampSettingsView()
            .tabItem {
              Label(String(localized: "Stamp"), systemImage: "signature")
            }
            .tag(Pane.stamp)
        #endif
        #if FEATURE_SCS
          ScsSettingsView()
            .tabItem {
              Label(String(localized: "Signing Service"), systemImage: "network")
            }
            .tag(Pane.webSigning)
        #endif
      }
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
    }
  }

#endif
