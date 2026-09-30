// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  internal struct RemotePairingPromptView: View {
    private enum Layout {
      static let retryDelayNanoseconds: UInt64 = 1_000_000_000
      /// The invitation wraps past this width instead of stretching
      /// the content-sized window to fit one long line.
      static let promptMaxWidth: CGFloat = 600
      static let bulletSpacing: CGFloat = 6
      static let bulletItemSpacing: CGFloat = 6
    }

    /// What the pairing prompt shows.
    ///
    /// A connected reader disables the phone path: opening the app
    /// on the phone is pointless while a reader sits ready, so the
    /// pairing code is not shown then - only the instruction to use
    /// the reader.
    internal enum Content: Equatable {
      case phoneCode(String)
      case readerOnly
      case connecting
      case preparing
    }

    @StateObject private var model = RappPairingModel()

    @ObservedObject private var cardPresence = CardPresence.shared

    internal var body: some View {
      Section {
        promptText
          .frame(maxWidth: Layout.promptMaxWidth, alignment: .leading)
      }
      .onAppear {
        ensureOffer()
      }
      .onReceive(model.$phase) { phase in
        switch phase {
        case .failed:
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: Layout.retryDelayNanoseconds)
            ensureOffer()
          }

        default:
          break
        }
      }
      .onChange(of: cardPresence.isReaderConnected) { _, connected in
        if connected {
          // A reader arriving ends the attempt this prompt owns;
          // a finished pairing is left alone.
          if !model.isFinished {
            model.cancel()
          }
        } else {
          ensureOffer()
        }
      }
    }

    @ViewBuilder private var promptText: some View {
      switch Self.content(
        phase: model.phase,
        readerConnected: cardPresence.isReaderConnected
      ) {
      case .phoneCode(let formattedCode):
        bullets([
          String(
            localized: "Open RefineID on phone (code \(formattedCode))."
          )
        ])

      case .readerOnly:
        bullets([
          String(
            localized: "Insert your identity card into the reader"
          )
        ])

      case .connecting:
        Text(String(localized: "Connecting..."))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("pairingPrompt")

      case .preparing:
        Text(String(localized: "Preparing pairing code..."))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("pairingPrompt")
      }
    }

    /// Resolves the prompt for a pairing phase and reader state.
    internal static func content(
      phase: RappPairingModel.Phase,
      readerConnected: Bool
    ) -> Content {
      if readerConnected {
        return .readerOnly
      }
      switch phase {
      case .offer(let code):
        return .phoneCode(RappPairingCode.formatted(code))

      case .connecting:
        return .connecting

      case .idle, .codeEntry, .paired, .failed:
        return .preparing
      }
    }

    /// Whether the prompt may hold a pairing offer.
    ///
    /// No offer while a reader is connected: the offer would
    /// advertise a phone path the prompt itself refuses to show.
    /// A finished pairing is never replaced by a fresh offer.
    internal static func wantsOffer(
      phase: RappPairingModel.Phase,
      readerConnected: Bool
    ) -> Bool {
      guard !readerConnected else { return false }
      switch phase {
      case .idle, .codeEntry, .failed:
        return true

      case .offer, .connecting, .paired:
        return false
      }
    }

    private func bullets(_ items: [String]) -> some View {
      VStack(alignment: .leading, spacing: Layout.bulletItemSpacing) {
        ForEach(items, id: \.self) { item in
          bulletItem(item)
        }
      }
      .textSelection(.enabled)
      .accessibilityIdentifier("pairingPrompt")
    }

    private func bulletItem(_ text: String) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: Layout.bulletSpacing) {
        Text("•")
          .accessibilityHidden(true)
        Text(text)
      }
      .accessibilityElement(children: .combine)
    }

    private func ensureOffer() {
      if Self.wantsOffer(
        phase: model.phase,
        readerConnected: cardPresence.isReaderConnected
      ) {
        model.createOffer()
      }
    }
  }

#endif
