// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

extension CardCredentialsView {
  /// What the screen shows: exactly one of these.
  internal enum ScreenMode: Equatable {
    /// A card is against the phone; nothing else shows until it leaves.
    case holding
    /// Cards in an attached reader named their holders.
    case readerIdentity
    /// No antenna: a card is reached only through a paired phone.
    case remoteOnly
    /// The phone registered this holder.
    case identity(holder: String)
    /// The fields that set a card up.
    case setup
  }

  /// Where a row leads when nothing has to happen first.
  ///
  /// Sign and PIN management are not routes: both classify the card
  /// before they open, so the flow state carries their destination.
  internal enum Route: Hashable {
    case verifyDocuments
    case remoteAccess
    case identity(IdentityOrigin)
  }

  /// Whose identity a submenu shows, carried by the row that opened it.
  internal enum IdentityOrigin: Hashable {
    /// The identity this phone registered.
    case phone(holder: String)
    /// A card in an attached reader.
    case reader(holder: String)
  }

  /// The one thing the screen is showing.
  internal var mode: ScreenMode {
    if isHolding {
      .holding
    } else if hasReaderIdentity {
      .readerIdentity
    } else if !offersNearField {
      .remoteOnly
    } else if let identityHolder {
      .identity(holder: identityHolder)
    } else {
      .setup
    }
  }
}
