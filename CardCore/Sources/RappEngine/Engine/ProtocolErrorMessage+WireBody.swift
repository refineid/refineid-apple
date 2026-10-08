// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ProtocolErrorMessage {
  /// The exact `error` wire body, omitting an absent operation identifier.
  internal var wireBody: [String: WireValue] {
    var body: [String: WireValue] = [
      "error_code": .unsigned(code),
      "error_name": .text(name),
      "message": .text(message),
    ]
    if let operationIdentifier {
      body["operation_id"] = .bytes(operationIdentifier)
    }
    return body
  }
}
