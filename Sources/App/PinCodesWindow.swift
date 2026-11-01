// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The PIN codes window: the card management form for the card in this
  /// Mac's reader.
  ///
  /// Only the key beside the local card's line opens it: it has no Window
  /// menu item, never opens at launch, and is not restored at the next one.
  /// It belongs to that card and closes when the card leaves the reader,
  /// or when the card turns out to await activation: the main window is
  /// where a card is activated.
  internal struct PinCodesWindow: Scene {
    /// The form, while a card is in the reader.
    internal struct Content: View {
      @ObservedObject private var cardPresence = CardPresence.shared
      @ObservedObject private var demoMode = DemoMode.shared
      private let activation = ActivationWatch.shared
      @Environment(\.dismissWindow)
      private var dismissWindow

      /// Whether a card is in this Mac's reader, or in a demonstration's
      /// virtual one.
      private var readerCardIsPresent: Bool {
        demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
      }

      internal var body: some View {
        CardManagementView(
          readerCardIsPresent: false,
          activationRequired: false,
          cardAccessNumber: nil
        )
        .onChange(of: readerCardIsPresent, initial: true) { _, present in
          if !present {
            dismissWindow(id: PinCodesWindow.windowID)
          }
        }
        .onChange(of: activation.awaitsActivation, initial: true) { _, awaits in
          if awaits {
            dismissWindow(id: PinCodesWindow.windowID)
          }
        }
      }
    }

    /// The window's scene identifier, which AppKit also carries as the
    /// window's identifier.
    internal static let windowID = "pin-codes"

    internal var body: some Scene {
      Window("PIN Codes", id: Self.windowID) {
        Content()
          .writingToolsBehavior(.disabled)
          .windowFullScreenBehavior(.disabled)
      }
      .windowResizability(.contentSize)
      .defaultLaunchBehavior(.suppressed)
      .restorationBehavior(.disabled)
      .commandsRemoved()
    }
  }

#endif
