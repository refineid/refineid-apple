// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  internal struct RemotePairingPromptView: View {
    private enum Layout {
      /// The invitation wraps past this width instead of stretching
      /// the content-sized window to fit one long line.
      static let promptMaxWidth: CGFloat = 600
      static let bulletSpacing: CGFloat = 6
      static let bulletItemSpacing: CGFloat = 6
    }

    /// What the pairing prompt shows.
    ///
    /// A connected reader disables the phone path: the phone is pointless
    /// while a reader sits ready, so no code is asked for then - only the
    /// instruction to use the reader.
    internal enum Content: Equatable {
      case phoneCode
      case readerOnly
    }

    @StateObject private var model = RappPairingModel()

    @ObservedObject private var cardPresence = CardPresence.shared

    internal var body: some View {
      Section {
        promptText
          .frame(maxWidth: Layout.promptMaxWidth, alignment: .leading)
      }
      .onChange(of: cardPresence.isReaderConnected) { _, connected in
        // A reader arriving ends the attempt this prompt owns; a finished
        // pairing is left alone.
        if connected, !model.isFinished {
          model.cancel()
        }
      }
    }

    @ViewBuilder private var promptText: some View {
      switch Self.content(readerConnected: cardPresence.isReaderConnected) {
      case .phoneCode:
        LabeledContent(String(localized: "Code from phone")) {
          PairingCodeEntryField(model: model)
        }
        .accessibilityIdentifier("pairingPrompt")
        if case .failed(let message) = model.phase {
          Text(message)
            .foregroundStyle(.secondary)
        }

      case .readerOnly:
        bullets([
          String(
            localized: "Insert your identity card into the reader"
          )
        ])
      }
    }

    /// Resolves the prompt for the reader state.
    nonisolated internal static func content(readerConnected: Bool) -> Content {
      readerConnected ? .readerOnly : .phoneCode
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
  }

#endif
