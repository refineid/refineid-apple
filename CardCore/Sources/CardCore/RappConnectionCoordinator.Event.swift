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
    }

    /// One semantic, authenticated event surfaced by the connection.
    public enum Event: Sendable, Equatable {
      case established
      case inspectPrerequisites(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case awaitUserApproval(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case executeSafeRead(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case executeCardCommand(
        operationID: Data,
        operation: RappOperationDriver.Operation
      )
      case completed(
        operationID: Data,
        result: RappOperationDriver.Result
      )
      case terminal(
        operationID: Data?,
        state: String?,
        reason: RappOperationDriver.TerminalReason?
      )
      case advisoryCancellation(operationID: Data?)
      case operationFinished(operationID: Data?)
      case peerBusy(operationID: Data?)
      case peerUnknownOperation(operationID: Data?)
      case progress(operationID: Data, event: ProgressEvent)
      case closed(CloseReason)

      internal init?(_ command: RappOperationDriver.Command) {
        if let event = Self.eventForProxy(command) {
          self = event
        } else if let event = Self.eventForRequester(command) {
          self = event
        } else {
          return nil
        }
      }

      private static func eventForProxy(_ command: RappOperationDriver.Command) -> Self? {
        switch command {
        case .inspectPrerequisites(let operationID, let operation):
          .inspectPrerequisites(operationID: operationID, operation: operation)

        case .awaitUserApproval(let operationID, let operation):
          .awaitUserApproval(operationID: operationID, operation: operation)

        case .executeSafeRead(let operationID, let operation):
          .executeSafeRead(operationID: operationID, operation: operation)

        case .executeCardCommand(let operationID, let operation):
          .executeCardCommand(operationID: operationID, operation: operation)

        case .completed, .terminal, .advisoryCancellation,
          .operationFinished, .peerBusy, .peerUnknownOperation, .progress,
          .send, .scheduleLiveness, .closed:
          nil
        }
      }

      private static func eventForRequester(_ command: RappOperationDriver.Command) -> Self? {
        switch command {
        case .completed(let operationID, let result):
          .completed(operationID: operationID, result: result)

        case .terminal(let operationID, let state, let reason):
          .terminal(operationID: operationID, state: state, reason: reason)

        case .advisoryCancellation(let operationID):
          .advisoryCancellation(operationID: operationID)

        case .operationFinished(let operationID):
          .operationFinished(operationID: operationID)

        case .peerBusy(let operationID):
          .peerBusy(operationID: operationID)

        case .peerUnknownOperation(let operationID):
          .peerUnknownOperation(operationID: operationID)

        case .progress(let operationID, let event):
          .progress(operationID: operationID, event: event)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .send, .scheduleLiveness, .closed:
          nil
        }
      }
    }
  }
#endif
