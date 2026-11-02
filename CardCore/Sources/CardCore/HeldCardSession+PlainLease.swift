// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension HeldCardSession {
  /// Exclusive use of the held plain channel for one operation that opens
  /// its own PACE channel, such as an organization card's, whose password
  /// is the PIN the operation spends.
  ///
  /// The operation lock stays held for the lifetime of this value, as a
  /// ``PreparedChannelLease`` holds it.
  public final class PlainChannelLease {
    /// The held channel, refusing commands once the field has ended.
    public let channel: any CardChannel
    private let operationLock: NSLock

    internal init(channel: any CardChannel, operationLock: NSLock) {
      self.channel = channel
      self.operationLock = operationLock
    }

    deinit {
      operationLock.unlock()
    }
  }

  /// Leases the held channel as it is, with no PACE prepared on it.
  ///
  /// Throws ``CardOperationError/sessionUnavailable`` when no channel is
  /// held or the field has ended.
  public func plainChannel() throws -> PlainChannelLease {
    cancelActivityTimeout()
    condition.lock()
    guard let plain = channel, !ended else {
      condition.unlock()
      throw CardOperationError.sessionUnavailable
    }
    let leasedGeneration = generation
    condition.unlock()
    operationLock.lock()
    let guarded = HeldSessionChannel(
      channel: plain,
      isAvailable: { [self] in
        condition.lock()
        defer { condition.unlock() }
        return !ended && generation == leasedGeneration
      })
    guard guarded.isAvailable() else {
      operationLock.unlock()
      throw CardOperationError.sessionUnavailable
    }
    recordLifecycle("plain lease claimed generation=\(leasedGeneration)")
    return PlainChannelLease(channel: guarded, operationLock: operationLock)
  }
}
