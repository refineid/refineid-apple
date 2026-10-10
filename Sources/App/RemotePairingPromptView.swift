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
    @State private var codeEntry = ""

    @ObservedObject private var cardPresence = CardPresence.shared

    internal var body: some View {
      Section {
        promptText
          .frame(maxWidth: Layout.promptMaxWidth, alignment: .leading)
      }
      .announcesOutcome(failure)
    }

    @ViewBuilder private var promptText: some View {
      if Self.content(readerConnected: cardPresence.isReaderConnected) == .phoneCodeBesideReader {
        bullets([
          String(
            localized: "Insert your identity card into the reader"
          )
        ])
      }
      TextField(String(localized: "Code from phone"), text: $codeEntry)
        .font(.body)
        .autocorrectionDisabled()
        .disabled(model.phase == .connecting)
        .accessibilityLabel(Text(String(localized: "Code from phone")))
        .accessibilityIdentifier("pairingCodeField")
        .onValueChange(of: codeEntry) { typed in
          let limited = Self.limitedCode(typed)
          if limited != typed {
            codeEntry = limited
          }
          if case .failed = model.phase, !limited.isEmpty {
            model.startCodeEntry()
          }
        }
        .onSubmit { model.acceptPairingCode(codeEntry) }
      if model.phase == .connecting {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(Text(String(localized: "Connecting to the phone")))
      }
      if let failure {
        Text(failure)
          .foregroundStyle(.secondary)
      }
    }

    private var failure: String? {
      if case .failed(let message) = model.phase {
        return message
      }
      return nil
    }

    /// Keeps what was typed to the characters a pairing code can hold.
    ///
    /// Typed input is canonicalized the way the code is compared, so a
    /// lowercase or look-alike letter becomes the one the phone shows,
    /// and anything outside the alphabet is dropped. Each character is
    /// canonicalized alone, because one stray character empties the
    /// canonical form of the whole string.
    nonisolated internal static func limitedCode(_ typed: String) -> String {
      String(
        typed.map { RappPairingCode.normalize(String($0)) }
          .joined()
          .prefix(RappPairingCode.codeLength))
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
