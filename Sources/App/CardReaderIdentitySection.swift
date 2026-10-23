// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same person row NFC uses once an identity exists, without the
  /// removal button: the name comes from the card in the reader. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here. The
  /// section appears once the holder's name is read, never as a wait.
  internal struct CardReaderIdentitySection: View {
    internal let holders: [String]

    internal var body: some View {
      if !holders.isEmpty {
        Section {
          ForEach(holders, id: \.self) { holder in
            MenuRow(holder, systemImage: "person", tint: .accentColor)
              .titleIdentifier("readerCardHolder")
          }
        } header: {
          CompactSectionHeader(title: String(localized: "Identity"))
        }
      }
    }
  }
#endif
