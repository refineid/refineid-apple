// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the card holder's pairing listener does with each stream event
/// until a requester has sent the pairing routing preamble.
///
/// RAPP v26.10.29 §2.2.1: a first frame that is not the expected preamble is
/// Class 1 invalid input, and the custodian closes that connection without
/// changing stored state. The offer stays open, so a connection rejected or
/// lost before the preamble is never reported to the ceremony as its end.
/// Once a requester has arrived, every event belongs to the ceremony.
public struct StreamPairingAdmission: Sendable {
  // MARK: Nested Types

  /// The listener owner's next step for one event.
  public enum Action: Equatable, Sendable {
    /// Drop the event; the ceremony does not see it.
    case ignore
    /// The requester sent the preamble: report its arrival.
    case arrive
    /// Close this connection and keep listening.
    case reject
    /// Hand the event to the ceremony.
    case forward
  }

  // MARK: Properties

  private let preamble: Data
  private var hasArrived = false
  private var isRejecting = false

  // MARK: Lifecycle

  /// Admits the requester whose first frame is `preamble`.
  public init(preamble: Data) {
    self.preamble = preamble
  }

  // MARK: Functions

  /// Classifies one listener event.
  public mutating func admit(_ event: StreamRelayEvent) -> Action {
    if hasArrived {
      if case .connected = event { return .ignore }
      return .forward
    }
    switch event {
    case .connected:
      return .ignore

    case .frame(let payload):
      if isRejecting { return .ignore }
      if payload == preamble {
        hasArrived = true
        return .arrive
      }
      isRejecting = true
      return .reject

    case .closed(let reason):
      switch reason {
      case .disconnected, .malformedFrame:
        isRejecting = false
        return .ignore

      default:
        return .forward
      }
    }
  }
}
