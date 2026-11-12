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
  /// PIN management is not a route: it classifies the card before it
  /// opens, so the flow state carries its destination, and signing
  /// from an identity travels that way too. Signing from setup is a
  /// plain route instead: a flow-state destination re-presents itself
  /// after the system back button, which would cover whatever opens
  /// next.
  internal enum Route: Hashable {
    case verifyDocuments
    case remoteAccess
    case authenticate
    case signDocuments
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
