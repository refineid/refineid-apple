// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An authenticated advisory progress notice on an active operation.
internal struct OperationProgressMessage: Equatable {
  internal let reference: OperationReference
  internal let event: ProgressEvent

  internal var wireBody: [String: WireValue] {
    var body = reference.wireBody
    body["event"] = .text(event.rawValue)
    return body
  }

  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    guard let eventValue = body.removeValue(forKey: "event"),
      case .text(let eventName) = eventValue
    else {
      throw MessageFieldError.invalidField("event")
    }
    return Self(
      reference: try OperationReference.from(wireBody: body),
      event: ProgressEvent(wireValue: eventName)
    )
  }
}
