// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// What one frame asks of the caller: frames to send, and a payload if the
/// frame carried one.
public struct SignRelayStep: Sendable, Equatable {
  /// Frames to hand the transport, in order.
  public let send: [Data]

  /// The peer's payload, once the session carries them.
  public let payload: Data?

  /// Names one step.
  public init(send: [Data] = [], payload: Data? = nil) {
    self.send = send
    self.payload = payload
  }
}
