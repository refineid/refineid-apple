// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// A status message with one consistent visual and accessibility hierarchy.
internal struct CredentialOutcomeText: View {
  private enum Layout {
    static let twoLineCount = 2
    static let spacing = 4.0
  }

  internal enum Tone {
    case failure
    case notice
    case success
  }

  internal let message: String
  internal let tone: Tone

  internal var body: some View {
    switch tone {
    case .failure:
      emphasized(color: .red)

    case .notice:
      emphasized(color: .orange)

    case .success:
      VStack {
        Text(message)
      }
      .foregroundStyle(.green)
      .bold()
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
      .accessibilityElement(children: .combine)
      // The combined element speaks the whole message: without the
      // label the eye alone reads whether the card obeyed (see below
      // for why the label sits on the container).
      .accessibilityLabel(message)
      .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func emphasized(color: Color) -> some View {
    let lines = message.split(
      separator: "\n",
      maxSplits: 1,
      omittingEmptySubsequences: false)

    VStack(spacing: Layout.spacing) {
      if lines.count == Layout.twoLineCount {
        Text(String(lines[0]))
          .fontWeight(.semibold)
        Text(String(lines[1]))
      } else {
        Text(message)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, alignment: .center)
    .foregroundStyle(color)
    .accessibilityElement(children: .combine)
    // The combined element speaks the whole message: without the
    // label the row shows its words to the eye alone. The label sits
    // on the combined container, never on a bare Text: a Text that
    // carries its own content as its label resolves the label through
    // itself and recurses the stack away.
    .accessibilityLabel(message)
    .textSelection(.enabled)
  }
}
