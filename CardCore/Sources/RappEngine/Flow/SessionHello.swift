// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The requester's first message once it verified `session.ready`, carrying
/// its current display name (RAPP v26.11.8 §7.1 item 6, §4.3 item 4).
internal struct SessionHello: Equatable {
  /// The requester's current display name.
  internal var displayName: RappDisplayName

  internal static func from(body: [String: WireValue]) throws -> Self {
    var fields = body
    let decodedName = try takeDisplayName(&fields)
    guard fields.isEmpty else { throw MessageFieldError.invalidField("body") }
    return Self(displayName: decodedName)
  }

  internal func body() -> [String: WireValue] {
    ["display_name": .text(displayName.text)]
  }
}
