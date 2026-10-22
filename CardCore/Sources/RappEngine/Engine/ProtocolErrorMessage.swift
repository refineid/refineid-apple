// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An `error` message (RAPP v26.10.21 §7.1, §10.3): a registered name and,
/// when it concerns one, the operation.
internal struct ProtocolErrorMessage: Equatable {
  internal let error: ResultError
  internal let operationIdentifier: RappOperationIdentifier?

  /// The human-readable `message` the body carries.
  internal var message: String {
    switch error {
    case .busy:
      "Another operation of this session is live."

    case .duplicateOperation:
      "The operation identifier was already used on this session."

    case .invalidLifetime:
      "The operation lifetime is zero."

    case .operationExpired:
      "The operation deadline passed."

    case .unauthorized:
      "The profile is not granted to this pairing."

    case .unsupportedParameter:
      "A parameter is not supported."

    case .userCancelled:
      "The holder declined."

    case .retryFloor:
      "The card's remaining attempts are reserved for its issuer's software."

    case .cardError:
      "The card did not answer."

    case .operationFailed:
      "The operation could not be carried out."
    }
  }

  /// The exact `error` wire body, omitting an absent operation identifier.
  internal var wireBody: [String: WireValue] {
    var body: [String: WireValue] = [
      "error_name": .text(error.rawValue),
      "message": .text(message),
    ]
    if let operationIdentifier {
      body["operation_id"] = .bytes(operationIdentifier.bytes)
    }
    return body
  }

  /// A request that arrived while another operation of the session is live
  /// (§8.1 item 1).
  internal static func busy(_ operationIdentifier: RappOperationIdentifier) -> Self {
    Self(error: .busy, operationIdentifier: operationIdentifier)
  }

  /// A request reusing an identifier the session has seen (§8.1 item 1).
  internal static func duplicate(_ operationIdentifier: RappOperationIdentifier) -> Self {
    Self(error: .duplicateOperation, operationIdentifier: operationIdentifier)
  }

  /// A received `error` body.
  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    guard let name = ResultError(rawValue: try takeOperationText(&body, "error_name")) else {
      throw CardOperationError.invalidField(field: "error_name")
    }
    _ = try takeOperationText(&body, "message")
    var identifier: RappOperationIdentifier?
    if body["operation_id"] != nil {
      identifier = try takeOperationIdentifier(&body, "operation_id")
    }
    guard body.isEmpty else { throw CardOperationError.unexpectedField }
    return Self(error: name, operationIdentifier: identifier)
  }
}
