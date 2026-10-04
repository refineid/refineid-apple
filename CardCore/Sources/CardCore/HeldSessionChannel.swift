// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Rejects new commands once the powered field that owns the channel has ended.
internal struct HeldSessionChannel: CardChannel {
  internal let channel: any HeldCardChannel
  internal let isAvailable: @Sendable () -> Bool

  internal var readChunkLength: ReadChunkLength { channel.readChunkLength }

  internal func transmit(_ payload: Data) throws -> Data {
    guard isAvailable() else { throw CardOperationError.sessionUnavailable }
    let response = try channel.transmit(payload)
    guard isAvailable() else { throw CardOperationError.sessionUnavailable }
    return response
  }
}
