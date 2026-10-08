// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Translates between sealed session frames and typed messages.
///
/// Only an authenticated envelope reaches this point, so a body that does not
/// parse here is an authenticated peer sending something the protocol forbids.
internal enum SessionMessageCodec {
  /// The typed message an authenticated envelope carries.
  internal static func message(
    from envelope: Envelope,
    pairIdentifier: Data,
    sessionIdentifier: Data,
    nowMilliseconds: UInt64
  ) throws -> TypedMessage {
    switch envelope.messageType {
    case .operationRequest:
      do {
        return .operationRequest(
          try OperationRequest.from(
            wireBody: envelope.body,
            pairIdentifier: pairIdentifier,
            sessionIdentifier: sessionIdentifier,
            localStartMilliseconds: nowMilliseconds))
      } catch let refusal as OperationRequestRefusal {
        return .operationRequestRefused(refusal)
      }

    case .operationProgress:
      return .operationProgress(try OperationProgressMessage.from(wireBody: envelope.body))

    case .operationResult:
      return .operationResult(
        try OperationResultMessage.decode(try WireValue.map(envelope.body).encoded()))

    case .operationResultAck:
      return .operationResultAck(try OperationReference.from(wireBody: envelope.body))

    case .operationStatus:
      return .operationStatus(try StatusReport.from(wireBody: envelope.body))

    case .operationStatusRequest:
      var body = envelope.body
      return .operationStatusRequest(operationIdentifier: try takeBytes(&body, "operation_id"))

    case .error:
      return .error(ProtocolErrorMessage.from(wireBody: envelope.body))

    default:
      return .other(envelope.messageType)
    }
  }

  /// The sealed frame a typed message becomes.
  internal static func frame(
    for message: TypedMessage,
    session: inout EstablishedSession
  ) throws -> Data {
    guard let messageType = message.messageType, let body = message.wireBody() else {
      throw EngineError.invalidLocalValue
    }
    return try session.seal(messageType, body: body)
  }
}
