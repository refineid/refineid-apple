// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The card access number, and what it unlocked.
  ///
  /// When Stamp is enabled in Settings, giving a CAN stamps the document
  /// with the certificate identity and, when present, the handwritten
  /// signature the card carries. If left empty, the document is stamped
  /// with the default verification advice. Nothing is remembered - the number
  /// unlocks reading the card, so storing it would be keeping a key to
  /// the holder's own card for no reason.
  internal struct StampRow: View {
    private static let spacing: CGFloat = 6

    /// The entry field's width, which grows with the text inside it.
    @ScaledMetric(relativeTo: .body)
    private var entryWidth: CGFloat = 130

    /// The signing state the number reads into.
    internal let signing: SignDocumentModel

    /// The number as typed.
    @Binding internal var accessNumber: String

    internal var body: some View {
      LabeledContent("Stamp with CAN (optional)") {
        SecureField("", text: $accessNumber)
          .frame(width: entryWidth)
          .multilineTextAlignment(.trailing)
          .onChange(of: accessNumber) { _, typed in
            accessNumber = LimitedDigits.cardAccessNumber(typed)
          }
          .accessibilityIdentifier("signAccessNumber")
      }
      if let note = signing.stampFailure {
        Text(note)
          .foregroundStyle(.orange)
          .font(.footnote)
      }
    }
  }

#endif
