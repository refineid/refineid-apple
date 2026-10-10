// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Protocol-level errors (RAPP v26.10.9 §10.4).
///
/// The engine sends three: `unknown_operation` answers a stale reference,
/// `duplicate_operation` refuses an operation identifier reused with
/// different content, and `operation_failed` refuses a request while another
/// is in flight. Any other received name is handled as `operation_failed`.
internal enum ProtocolErrorMessage: Equatable {
  case duplicateOperation(operationIdentifier: Data)
  case operationFailed(operationIdentifier: Data?)
  case unknownOperation(operationIdentifier: Data?)

  internal var name: String {
    switch self {
    case .unknownOperation:
      EngineErrorName.unknownOperation

    case .duplicateOperation:
      EngineErrorName.duplicateOperation

    case .operationFailed:
      EngineErrorName.operationFailed
    }
  }

  internal var code: UInt64 {
    switch self {
    case .unknownOperation:
      EngineErrorName.unknownOperationCode

    case .duplicateOperation:
      EngineErrorName.duplicateOperationCode

    case .operationFailed:
      EngineErrorName.operationFailedCode
    }
  }

  /// The human-readable message the body carries.
  internal var message: String {
    switch self {
    case .unknownOperation:
      "The operation is unknown or already terminal."

    case .duplicateOperation:
      "The operation identifier is already in use with different content."

    case .operationFailed:
      "The operation could not be admitted."
    }
  }

  internal var operationIdentifier: Data? {
    switch self {
    case .unknownOperation(let operationIdentifier), .operationFailed(let operationIdentifier):
      operationIdentifier

    case .duplicateOperation(let operationIdentifier):
      operationIdentifier
    }
  }

  /// The error a received body names, by name first (section 10.4).
  internal static func from(wireBody: [String: WireValue]) -> Self {
    var identifier: Data?
    if case .bytes(let bytes)? = wireBody["operation_id"] {
      identifier = bytes
    }
    guard case .text(let name)? = wireBody["error_name"] else {
      return .operationFailed(operationIdentifier: identifier)
    }
    switch name {
    case EngineErrorName.unknownOperation:
      return .unknownOperation(operationIdentifier: identifier)

    case EngineErrorName.duplicateOperation:
      guard let identifier else {
        return .operationFailed(operationIdentifier: nil)
      }
      return .duplicateOperation(operationIdentifier: identifier)

    default:
      return .operationFailed(operationIdentifier: identifier)
    }
  }
}
