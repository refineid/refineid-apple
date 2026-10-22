// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reads an authenticated envelope as a typed message.
///
/// Only an authenticated envelope reaches this point, so a body that does not
/// parse here is an authenticated peer sending something the protocol
/// forbids.
internal enum SessionMessageCodec {
  /// The typed message an authenticated envelope carries.
  internal static func message(from envelope: Envelope, nowMilliseconds: UInt64) throws
    -> TypedMessage
  {
    switch envelope.messageType {
    case .operationRequest:
      do {
        return .operationRequest(
          try OperationRequest.from(
            wireBody: envelope.body, localStartMilliseconds: nowMilliseconds))
      } catch let refusal as OperationRequestRefusal {
        return .operationRequestRefused(refusal)
      }

    case .operationProgress:
      return .operationProgress(try OperationProgressMessage.from(wireBody: envelope.body))

    case .operationResult:
      return .operationResult(try OperationResultMessage.from(wireBody: envelope.body))

    case .error:
      return .error(try ProtocolErrorMessage.from(wireBody: envelope.body))

    case .cardStatus:
      return .cardStatus(try RappCardStatus.from(wireBody: envelope.body))

    default:
      return .other(envelope.messageType)
    }
  }
}
