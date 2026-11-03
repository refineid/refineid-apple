// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's first session message: the session-parameter echo, a
/// fresh nonce and its current display name (RAPP v26.11.2 §7.1 item 5,
/// §4.3 item 4).
internal struct SessionReady: Equatable {
  internal var parameters: SessionParameters

  internal var nonce: Data

  /// The custodian's current display name.
  internal var displayName: RappDisplayName

  internal static func from(body: [String: WireValue]) throws -> Self {
    var fields = body
    let decodedParameters = try SessionParameters.from(map: takeMessageMap(&fields, "parameters"))
    let decodedNonce = try takeMessageBytes(&fields, "nonce")
    let decodedName = try takeDisplayName(&fields)
    guard fields.isEmpty, decodedNonce.count == FlowLimit.readyNonce else {
      throw MessageFieldError.invalidField("nonce")
    }
    return Self(parameters: decodedParameters, nonce: decodedNonce, displayName: decodedName)
  }

  internal func body() throws -> [String: WireValue] {
    guard nonce.count == FlowLimit.readyNonce else {
      throw MessageFieldError.invalidField("nonce")
    }
    return [
      "parameters": .map(try parameters.asMap()), "nonce": .bytes(nonce),
      "display_name": .text(displayName.text),
    ]
  }
}
