// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappConnectionCoordinator {
    /// Why the connection closed, attributed to the phase that closed it.
    public enum CloseReason: Sendable, Equatable {
      case handshake(RappSessionDriver.CloseReason)
      case operation(RappOperationDriver.CloseReason)
      case transportFailure
      case localRequest

      /// Whether the peer revoked the pairing (RAPP v26.10.21 §4.6 item 4).
      public var peerRevokedPairing: Bool {
        self == .handshake(.pairRevoked) || self == .operation(.pairRevoked)
      }

      /// Whether the custodian announced that it stopped serving (§4.5).
      public var serviceWithdrawn: Bool {
        self == .operation(.serviceWithdrawn) || self == .handshake(.peerClosed(.serviceWithdrawn))
      }
    }

    /// One semantic, authenticated event surfaced by the connection.
    public enum Event: Sendable, Equatable {
      case established
      case inspectPrerequisites(
        operationID: RappOperationIdentifier,
        operation: RappOperationDriver.Operation
      )
      case awaitUserApproval(
        operationID: RappOperationIdentifier,
        operation: RappOperationDriver.Operation
      )
      case executeSafeRead(
        operationID: RappOperationIdentifier,
        operation: RappOperationDriver.Operation
      )
      case executeCardCommand(
        operationID: RappOperationIdentifier,
        operation: RappOperationDriver.Operation
      )
      case completed(operationID: RappOperationIdentifier, result: RappOperationResult)
      case terminal(operationID: RappOperationIdentifier, reason: RappTerminalReason)
      case progress(operationID: RappOperationIdentifier, event: ProgressEvent)
      /// The custodian's word on which card it can serve now (RAPP v26.10.21
      /// §8.4).
      case cardStatus(RappCardStatus)
      /// The session's operation ended with the session (§8.1 item 3).
      case operationEnded(RappEndedOperation)
      case closed(CloseReason)

      internal init?(_ command: RappOperationDriver.Command) {
        switch command {
        case .inspectPrerequisites(let operationID, let operation):
          self = .inspectPrerequisites(operationID: operationID, operation: operation)

        case .awaitUserApproval(let operationID, let operation):
          self = .awaitUserApproval(operationID: operationID, operation: operation)

        case .executeSafeRead(let operationID, let operation):
          self = .executeSafeRead(operationID: operationID, operation: operation)

        case .executeCardCommand(let operationID, let operation):
          self = .executeCardCommand(operationID: operationID, operation: operation)

        case .completed(let operationID, let result):
          self = .completed(operationID: operationID, result: result)

        case .terminal(let operationID, let reason):
          self = .terminal(operationID: operationID, reason: reason)

        case .progress(let operationID, let event):
          self = .progress(operationID: operationID, event: event)

        case .cardStatus(let status):
          self = .cardStatus(status)

        case .operationEnded(let ended):
          self = .operationEnded(ended)

        case .send, .closed:
          return nil
        }
      }
    }
  }
#endif
