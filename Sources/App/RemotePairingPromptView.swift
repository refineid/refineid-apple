// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  internal struct RemotePairingPromptView: View {
    private enum Layout {
      /// The invitation wraps past this width instead of stretching
      /// the content-sized window to fit one long line.
      static let promptMaxWidth: CGFloat = 600
    }

    @StateObject private var model = RappPairingModel()
    @State private var codeEntry = ""
    @State private var refused = false

    internal var body: some View {
      Group {
        promptText
          .frame(maxWidth: Layout.promptMaxWidth, alignment: .leading)
      }
      .announcesOutcome(failure)
      .onValueChange(of: failure) { message in
        refused = message != nil
      }
      .onDisappear {
        // Turning remote use off ends a code being tried: its browse
        // stops with it.
        #if REFINEID_REMOTE_CARD
          if !RemoteUseSwitch.shared.isOn {
            model.resetAttempt()
          }
        #endif
      }
    }

    @ViewBuilder private var promptText: some View {
      Text(
        String(
          localized: "Open RefineID remote access on your phone and enter the pairing code:"
        )
      )
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        CodeBoxesField(
          label: String(localized: "Pairing code"),
          identifier: "pairingCodeField",
          caption: nil,
          length: RappPairingCode.codeLength,
          groupSize: RappPairingCode.groupSize,
          text: $codeEntry,
          refused: $refused,
          filter: Self.limitedCode,
          onComplete: { code in model.acceptPairingCode(code) },
          onSubmit: { model.acceptPairingCode(codeEntry) }
        )
        .disabled(model.phase == .connecting)
        .onValueChange(of: codeEntry) { typed in
          if case .failed = model.phase, !typed.isEmpty {
            model.startCodeEntry()
          }
        }
        if model.phase == .connecting {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(Text(String(localized: "Connecting to the phone")))
        }
      }
      if let failure {
        Text(failure)
          .foregroundStyle(.red)
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
    /// lowercase letter becomes the capital the phone shows, and anything
    /// outside the alphabet, the excluded letters among it, is dropped.
    /// Each character is canonicalized alone, because one stray character
    /// empties the canonical form of the whole string.
    nonisolated internal static func limitedCode(_ typed: String) -> String {
      String(
        typed.map { RappPairingCode.normalize(String($0)) }
          .joined()
          .prefix(RappPairingCode.codeLength))
    }
  }

#endif
