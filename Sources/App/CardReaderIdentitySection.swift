// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same Person row NFC uses once an identity exists. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here.
  internal struct CardReaderIdentitySection: View {
    private static let minHolderScale: CGFloat = 0.85
    private static let holderLineLimit: Int = 2
    private static let rowSpacing: CGFloat = 4

    internal let holders: [String]
    internal let onSelect: ((String) -> Void)?

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
      } header: {
        Text(String(localized: "Identity"))
          .frame(maxWidth: .infinity, alignment: .leading)
          .listRowInsets(EdgeInsets())
      }
    }

    internal init(holders: [String]) {
      self.holders = holders
      self.onSelect = nil
    }

    internal init(holders: [String], onSelect: @escaping (String) -> Void) {
      self.holders = holders
      self.onSelect = onSelect
    }

    @ViewBuilder
    private func holderRow(_ holder: String) -> some View {
      Button {
        onSelect?(holder)
      } label: {
        HStack {
          Image(systemName: "person")
            .font(.system(size: PersonRowLabel.iconPointSize))
            .symbolRenderingMode(.monochrome)
            .frame(width: PersonRowLabel.iconWidth)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
          Text(holder)
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(Self.holderLineLimit)
            .minimumScaleFactor(Self.minHolderScale)
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier("readerCardHolder")
          Spacer(minLength: Self.rowSpacing)
          Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("identitySubmenuButton")
    }
  }
#endif
