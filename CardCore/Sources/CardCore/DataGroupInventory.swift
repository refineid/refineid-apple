// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which data groups a travel-document application actually carries,
/// as EF.COM lists them.
///
/// The card's own inventory, and the only safe thing to ask before
/// reading a data group: a READ BINARY against one the card never
/// provisioned desynchronises the secure-messaging counter, after
/// which every later command in the session fails for a reason that
/// has nothing to do with the command.
public struct DataGroupInventory: Equatable, Sendable {
  /// The tag each listed data group is named by.
  private let markers: [UInt8]

  /// Whether the card carries the holder's handwritten signature.
  public var carriesDisplayedSignature: Bool {
    markers.contains(FineidValues.dataGroupSevenMarker)
  }

  /// How many data groups the card announced, for diagnostics.
  public var count: Int {
    markers.count
  }

  /// Reads the list EF.COM published, which is a run of one-byte
  /// tags and is empty when the card listed nothing.
  internal init(listing: Data) {
    self.markers = Array(listing)
  }
}
