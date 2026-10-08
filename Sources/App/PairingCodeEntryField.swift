// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Where the requester types the code its phone shows.
///
/// The field groups the code `XX XX XX` as the phone does, and a complete
/// code starts pairing at once.
internal struct PairingCodeEntryField: View {
  private enum Layout {
    static let inputSpacing: CGFloat = 8
    static let caretWidth: CGFloat = 2
    static let caretVerticalInset: CGFloat = 2
    static let spinnerSlotSide: CGFloat = 20
  }

  /// Placeholder groups, shaped like a code.
  private static let prompts = ["7K", "X4", "M9"]

  @ObservedObject internal var model: RappPairingModel
  @State private var digits = ""
  @FocusState private var isFocused: Bool

  internal var body: some View {
    HStack(spacing: Layout.inputSpacing) {
      codeDisplay
        .overlay {
          TextField("", text: binding)
            .textFieldStyle(.plain)
            #if os(iOS)
              .keyboardType(.asciiCapable)
              .textInputAutocapitalization(.characters)
            #endif
            .autocorrectionDisabled()
            .focused($isFocused)
            .foregroundStyle(.clear)
            .tint(.clear)
            .accessibilityLabel(Text(String(localized: "Pairing code")))
            .accessibilityIdentifier("pairingCodeEntry")
        }
      ZStack {
        if case .connecting = model.phase {
          ProgressView()
            .controlSize(.small)
        }
      }
      .frame(width: Layout.spinnerSlotSide, height: Layout.spinnerSlotSide)
    }
    .onAppear { isFocused = true }
    .onValueChange(of: model.phase) { phase in
      if case .failed = phase {
        digits = ""
        isFocused = true
      }
    }
  }

  private var binding: Binding<String> {
    Binding(get: { digits }, set: { apply($0) })
  }

  private var codeDisplay: some View {
    let groupSize = RappPairingCode.groupSize
    return HStack(spacing: 0) {
      ForEach(Self.prompts.indices, id: \.self) { index in
        if index > 0 {
          Text(verbatim: " ")
        }
        group(
          digits: String(digits.dropFirst(index * groupSize).prefix(groupSize)),
          prompt: Self.prompts[index],
          showsCaret: isFocused && digits.count / groupSize == index
            && digits.count < RappPairingCode.codeLength)
      }
    }
    .font(.body.monospacedDigit().weight(.semibold))
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityHidden(true)
  }

  private func group(digits: String, prompt: String, showsCaret: Bool) -> some View {
    Text(verbatim: String(repeating: "0", count: RappPairingCode.groupSize))
      .hidden()
      .overlay(alignment: .leading) {
        ZStack(alignment: .leading) {
          if digits.isEmpty {
            Text(verbatim: prompt)
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 0) {
            Text(verbatim: digits)
              .foregroundStyle(.primary)
            if showsCaret {
              Rectangle()
                .fill(Color.accentColor)
                .frame(width: Layout.caretWidth)
                .padding(.vertical, Layout.caretVerticalInset)
            }
            Spacer(minLength: 0)
          }
        }
      }
  }

  private func apply(_ typed: String) {
    let normalized = String(
      RappPairingCode.normalize(typed).prefix(RappPairingCode.codeLength))
    digits = normalized
    if RappPairingCode.isValid(normalized) {
      isFocused = false
      model.acceptPairingCode(normalized)
    } else if model.phase != .codeEntry {
      model.startCodeEntry()
    }
  }
}
