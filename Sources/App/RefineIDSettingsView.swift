// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  internal struct RefineIDSettingsView: View {
    private enum Pane: Hashable {
      #if FEATURE_PDF_STAMP
        case pdfStamp
      #endif
      case pinCodes
      case remote
      case storedData
      case timeStamp
    }

    private static let paneWidth: CGFloat = 680
    private static let paneHeight: CGFloat = 300

    @ObservedObject private var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared

    @State private var pane = Pane.remote

    /// Whether a reader card is present and the PIN pane should be shown.
    private var readerCardIsPresent: Bool {
      demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
    }

    internal var body: some View {
      TabView(selection: $pane) {
        featureSettingsTabs
        mainSettingsTabs
      }
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
      .onChange(of: readerCardIsPresent) { _, present in
        if !present, pane == .pinCodes {
          pane = .remote
        }
      }
    }

    @ViewBuilder private var featureSettingsTabs: some View {
      #if FEATURE_PDF_STAMP
        DocumentStampSettingsView()
          .tabItem {
            Label(String(localized: "PDF Stamp"), systemImage: "signature")
          }
          .tag(Pane.pdfStamp)
      #endif
    }

    @ViewBuilder private var mainSettingsTabs: some View {
      if readerCardIsPresent {
        CardManagementView(
          readerCardIsPresent: false,
          activationRequired: false,
          cardAccessNumber: nil,
          activationScheme: nil,
          activationNeeds: nil,
          onActivationSucceeded: {
            // optional hook; default is a no-op
          }
        )
        .tabItem {
          Label(String(localized: "PIN Codes"), systemImage: "key")
        }
        .tag(Pane.pinCodes)
      }
      RemotePairingSettingsView()
        .tabItem {
          Label(String(localized: "Remote"), systemImage: "key.radiowaves.forward")
        }
        .tag(Pane.remote)
      StoredDataSettingsView()
        .tabItem {
          Label(String(localized: "Stored Data"), systemImage: "key.fill")
        }
        .tag(Pane.storedData)
      TimestampAuthoritiesSettingsView()
        .tabItem {
          Label(String(localized: "Time Stamp"), systemImage: "clock.badge.checkmark")
        }
        .tag(Pane.timeStamp)
    }
  }

#endif
