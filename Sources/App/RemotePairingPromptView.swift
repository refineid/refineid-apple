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
    /// The phone code is always offered: a reader and a paired phone
    /// coexist, and the holder chooses. A connected reader adds the
    /// instruction to use it.
    internal enum Content: Equatable {
      case phoneCode
      case phoneCodeBesideReader
    }

    @StateObject private var model = RappPairingModel()

    @ObservedObject private var cardPresence = CardPresence.shared

    internal var body: some View {
      Section {
        promptText
          .frame(maxWidth: Layout.promptMaxWidth, alignment: .leading)
      }
    }

    @ViewBuilder private var promptText: some View {
      if Self.content(readerConnected: cardPresence.isReaderConnected) == .phoneCodeBesideReader {
        bullets([
          String(
            localized: "Insert your identity card into the reader"
          )
        ])
      }
      LabeledContent(String(localized: "Code from phone")) {
        PairingCodeEntryField(model: model)
      }
      .accessibilityIdentifier("pairingPrompt")
      if case .failed(let message) = model.phase {
        Text(message)
          .foregroundStyle(.secondary)
      }
    }

    /// Resolves the prompt for the reader state.
    nonisolated internal static func content(readerConnected: Bool) -> Content {
      readerConnected ? .phoneCodeBesideReader : .phoneCode
    }

    private func bullets(_ items: [String]) -> some View {
      VStack(alignment: .leading, spacing: Layout.bulletItemSpacing) {
        ForEach(items, id: \.self) { item in
          bulletItem(item)
        }
      }
      .textSelection(.enabled)
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
