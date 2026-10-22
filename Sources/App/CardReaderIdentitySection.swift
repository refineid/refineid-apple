// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same Person row NFC uses once an identity exists. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here. The
  /// section appears once the holder's name is read, never as a wait.
  internal struct CardReaderIdentitySection: View {
    internal let holders: [String]

    internal var body: some View {
      if !holders.isEmpty {
        Section {
          ForEach(holders, id: \.self) { holder in
            NavigationLink(value: CardCredentialsView.Route.identity(.reader(holder: holder))) {
              MenuRow(holder, systemImage: "person", tint: .accentColor)
                .titleIdentifier("readerCardHolder")
            }
            .accessibilityIdentifier("identitySubmenuButton")
          }
        } header: {
          CompactSectionHeader(title: String(localized: "Identity"))
        }
      }
    }
  }
#endif
