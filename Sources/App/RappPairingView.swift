// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

internal struct RappPairingView: View {
  private enum Layout {
    static let sheetMinimumWidth: CGFloat = 440
    static let sheetMinimumHeight: CGFloat = 380
    static let codeCornerRadius: CGFloat = 12
    static let codeSpacing: CGFloat = 16
    static let maxContentWidth: CGFloat = 400
    static let containerSpacing: CGFloat = 24
    static let headerSpacing: CGFloat = 8
    static let topPadding: CGFloat = 32
    static let inputFontSize: CGFloat = 28
    static let displayFontSize: CGFloat = 38
    static let trackingSpacing: CGFloat = 3
    static let codeHorizontalPadding: CGFloat = 24
    static let codeVerticalPadding: CGFloat = 18
    static let strokeOpacity: Double = 0.3
    static let strokeLineWidth: CGFloat = 1.5
    static let connectingSpacing: CGFloat = 12
    static let resetDelaySeconds: UInt64 = 2_000_000_000
  }

  @Environment(\.dismiss)
  private var dismiss
  @StateObject private var model = RappPairingModel()
  @State private var enteredCode = ""
  @State private var copied = false

  /// Whether this device can only borrow a card, never serve one.
  ///
  /// The stream listener is the phone. iPad (no near field) and Mac
  /// therefore always offer; an iPhone with near field always accepts.
  private var borrowsOnly: Bool {
    #if os(iOS)
      return !SupportedCardTransports.offersNearField
    #else
      return true
    #endif
  }

  internal var body: some View {
    NavigationStack {
      ZStack {
        codeBackground.ignoresSafeArea()
        if borrowsOnly {
          borrowedCardCode
        } else {
          servingCardCodeEntry
        }
      }
      .navigationTitle(String(localized: "Remote Access"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Cancel")) {
            dismiss()
          }
        }
      }
    }
    .onAppear {
      model.refresh()
      if borrowsOnly {
        model.createOffer()
      } else {
        #if os(iOS)
          model.startCodeEntry()
        #endif
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: RappPairingModel.pairingsDidChangeNotification)
    ) { _ in
      model.refresh()
    }
    .onReceive(model.$phase) { phase in
      if case .paired = phase {
        dismiss()
      }
    }
    .onDisappear {
      model.cancel()
    }
    #if os(macOS)
      .frame(minWidth: Layout.sheetMinimumWidth, minHeight: Layout.sheetMinimumHeight)
    #endif
  }

  /// The surface the view is drawn on.
  private var codeBackground: Color {
    #if os(iOS)
      Color(uiColor: .systemGroupedBackground)
    #else
      Color(nsColor: .windowBackgroundColor)
    #endif
  }

  /// The code entry UI for the card holder.
  @ViewBuilder private var servingCardCodeEntry: some View {
    VStack(spacing: Layout.containerSpacing) {
      codeEntryHeader
      codeEntryForm
      Spacer()
    }
    .padding(.top, Layout.topPadding)
  }

  private var codeEntryHeader: some View {
    VStack(spacing: Layout.headerSpacing) {
      Text(String(localized: "Enter Pairing Code"))
        .font(.title2.bold())
    }
    .padding(.horizontal)
  }

  private var codeEntryForm: some View {
    VStack(spacing: Layout.codeSpacing) {
      codeTextField
      if case .connecting = model.phase {
        ProgressView()
          .controlSize(.regular)
      }
      if case .failed(let error) = model.phase {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: Layout.maxContentWidth)
    .padding(.horizontal)
  }

  private var codeTextField: some View {
    TextField("ABC1", text: $enteredCode)
      .font(.system(size: Layout.inputFontSize, weight: .semibold, design: .monospaced))
      .multilineTextAlignment(.center)
      .textCase(.uppercase)
      .autocorrectionDisabled(true)
      #if os(iOS)
        .textInputAutocapitalization(.characters)
        .keyboardType(.asciiCapable)
      #endif
      .padding()
      .background(
        RoundedRectangle(cornerRadius: Layout.codeCornerRadius)
          #if os(iOS)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
          #else
            .fill(Color(nsColor: .controlBackgroundColor))
          #endif
      )
      .accessibilityIdentifier("pairingCodeEntry")
      .onValueChange(of: enteredCode) { newValue in
        let normalized = RappPairingCode.normalize(newValue)
        if enteredCode != normalized {
          enteredCode = normalized
        }
        if RappPairingCode.isValid(normalized) {
          model.acceptPairingCode(normalized)
        } else if model.phase != .codeEntry {
          model.startCodeEntry()
        }
      }
  }

  /// The whole screen a borrowing device shows: the code, centred, as
  /// large and clear as possible.
  @ViewBuilder private var borrowedCardCode: some View {
    VStack(spacing: Layout.containerSpacing) {
      borrowedCodeHeader
      borrowedCodeBody
      Spacer()
    }
    .padding(.top, Layout.topPadding)
  }

  private var borrowedCodeHeader: some View {
    VStack(spacing: Layout.headerSpacing) {
      Text(String(localized: "Pairing Code"))
        .font(.title2.bold())
    }
    .padding(.horizontal)
  }

  @ViewBuilder private var borrowedCodeBody: some View {
    if case .offer(let code) = model.phase {
      VStack(spacing: Layout.codeSpacing) {
        codeCard(code)
        copyCodeButton(code)
      }
      #if DEBUG
        .onAppear { print("[pairing view] displaying code: \(code)") }
      #endif
    } else if case .connecting = model.phase {
      VStack(spacing: Layout.connectingSpacing) {
        ProgressView()
          .controlSize(.large)
        Text(String(localized: "Connecting..."))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    } else {
      ProgressView()
    }
  }

  private func codeCard(_ code: String) -> some View {
    Text(code)
      .font(.system(size: Layout.displayFontSize, weight: .bold, design: .monospaced))
      .tracking(Layout.trackingSpacing)
      .padding(.horizontal, Layout.codeHorizontalPadding)
      .padding(.vertical, Layout.codeVerticalPadding)
      .background(
        RoundedRectangle(cornerRadius: Layout.codeCornerRadius)
          #if os(iOS)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
          #else
            .fill(Color(nsColor: .controlBackgroundColor))
          #endif
          .overlay(
            RoundedRectangle(cornerRadius: Layout.codeCornerRadius)
              .stroke(
                Color.accentColor.opacity(Layout.strokeOpacity),
                lineWidth: Layout.strokeLineWidth
              )
          )
      )
      .accessibilityIdentifier("pairingCode")
      .accessibilityLabel(code)
  }

  private func copyCodeButton(_ code: String) -> some View {
    Button {
      copyToClipboard(RappPairingCode.normalize(code))
    } label: {
      Label(
        copied ? String(localized: "Code copied") : String(localized: "Copy Code"),
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
  }

  private func copyToClipboard(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #elseif os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
    copied = true
    Task {
      try? await Task.sleep(nanoseconds: Layout.resetDelaySeconds)
      copied = false
    }
  }
}
