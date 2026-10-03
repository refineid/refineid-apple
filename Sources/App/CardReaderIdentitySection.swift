// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same Person row NFC uses once an identity exists. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here.
  internal struct CardReaderIdentitySection: View {
    /// Spacing between the person label and the holder name.
    private static let identityDetailsSpacing: CGFloat = 4

    internal let holders: [String]
    internal let onSelect: (String) -> Void

    internal var body: some View {
      Section {
        if holders.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
          ForEach(holders, id: \.self) { holder in
            holderRow(holder)
          }
        }
      }
    }

    @ViewBuilder
    private func holderRow(_ holder: String) -> some View {
      Button {
        onSelect(holder)
      } label: {
        HStack {
          Image(systemName: "person")
            .font(.system(size: PersonRowLabel.iconPointSize))
            .symbolRenderingMode(.monochrome)
            .frame(width: PersonRowLabel.iconWidth)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
          Text(String(localized: "Identity"))
          Spacer()
          Text(holder)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("readerCardHolder")
          Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
    }
  }
#endif
