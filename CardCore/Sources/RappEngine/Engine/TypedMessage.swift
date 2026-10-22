// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One typed message on an established session.
///
/// The engines dispatch on this rather than on raw envelopes, so the wire
/// layer stays the only place that parses bytes.
internal enum TypedMessage: Equatable {
  /// The card the custodian holds, and whether a card reader is connected
  /// to it (§8.4).
  case cardStatus(RappCardStatus)
  case error(ProtocolErrorMessage)
  case operationProgress(OperationProgressMessage)
  case operationRequest(OperationRequest)
  /// A well-formed request naming something this endpoint cannot serve;
  /// inbound only, answered with a rejected result.
  case operationRequestRefused(OperationRequestRefusal)
  case operationResult(OperationResultMessage)
  /// A message outside the operation protocol: liveness, a close, or one
  /// that belongs to an earlier phase.
  case other(MessageType)

  /// The operation the message names, if it names one.
  internal var referencedOperationIdentifier: RappOperationIdentifier? {
    switch self {
    case .operationRequest(let request):
      request.operationIdentifier

    case .operationRequestRefused(let refusal):
      refusal.operationIdentifier

    case .operationProgress(let progress):
      progress.operationIdentifier

    case .operationResult(let result):
      result.operationIdentifier

    case .error(let error):
      error.operationIdentifier

    case .cardStatus, .other:
      nil
    }
  }

  /// The registered message type, for a message this endpoint sends.
  internal var messageType: MessageType? {
    switch self {
    case .cardStatus:
      .cardStatus

    case .error:
      .error

    case .operationProgress:
      .operationProgress

    case .operationRequest:
      .operationRequest

    case .operationResult:
      .operationResult

    case .other(let type):
      type

    case .operationRequestRefused:
      nil
    }
  }

  /// The exact body this message puts on the wire.
  ///
  /// A message outside the operation protocol has no body here, because its
  /// own layer owns that encoding; an inbound refusal has none either.
  internal func wireBody() -> [String: WireValue]? {
    // swiftlint:disable:previous discouraged_optional_collection
    switch self {
    case .cardStatus(let status):
      status.wireBody

    case .error(let error):
      error.wireBody

    case .operationProgress(let progress):
      progress.wireBody

    case .operationRequest(let request):
      request.wireBody()

    case .operationResult(let result):
      result.wireBody

    case .other, .operationRequestRefused:
      nil
    }
  }
}
