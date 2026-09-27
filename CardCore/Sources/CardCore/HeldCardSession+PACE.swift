// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(OSLog)
  import OSLog
#endif

extension HeldCardSession {
  // MARK: Functions

  /// Starts PACE immediately on a worker, ahead of Safari's sign call.
  public func startPACE(with accessNumber: CardAccessNumber) {
    condition.lock()
    guard channel != nil, case .idle = preparation else {
      condition.unlock()
      return
    }
    preparation = .running
    condition.unlock()

    #if canImport(OSLog)
      Self.logger.trace("pace: early preparation started")
    #endif
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      finishPACE(with: accessNumber)
    }
  }

  /// Leases the exact secure channel prepared for this field.
  ///
  /// A signer arriving while early PACE is in flight waits for it. The
  /// idle branch is only a defensive fallback; normal near-field mints
  /// call ``startPACE(with:)`` before returning the token.
  public func preparedChannel(
    accessNumber: CardAccessNumber
  ) throws -> PreparedChannelLease {
    cancelActivityTimeout()
    var prepareHere = false
    condition.lock()
    guard channel != nil, !ended else {
      condition.unlock()
      throw CardOperationError.sessionUnavailable
    }
    if case .idle = preparation {
      preparation = .running
      prepareHere = true
    }
    condition.unlock()

    if prepareHere {
      finishPACE(with: accessNumber)
    }

    let deadline = Date().addingTimeInterval(Self.preparationWaitSeconds)
    let finalState = try claimPreparedChannel(deadline: deadline)

    switch finalState {
    case .ready(let secure):
      operationLock.lock()
      #if canImport(OSLog)
        Self.logger.trace("pace: prepared channel reused")
      #endif
      return PreparedChannelLease(channel: secure, operationLock: operationLock) { [weak self] in
        self?.finishLease()
      }

    case .failed(let error):
      throw error

    case .idle, .running, .leased:
      preconditionFailure("PACE preparation did not reach a terminal state")
    }
  }

  /// Waits until PACE preparation finishes and claims the lease on the channel.
  private func claimPreparedChannel(
    deadline: Date
  ) throws -> PreparationState {
    condition.lock()
    while case .running = preparation {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw CardOperationError.sessionUnavailable
      }
    }
    while case .leased = preparation {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw CardOperationError.sessionUnavailable
      }
    }
    let finalState = preparation
    if case .ready(let secure) = finalState {
      preparation = .leased(secure)
    }
    condition.unlock()
    return finalState
  }

  /// Establishes keys and selects the FINEID application over the secure channel.
  private func establishPACE(
    channel: any HeldCardChannel,
    accessNumber: CardAccessNumber
  ) throws -> SecureMessagingChannel {
    try? CardOperations(channel: channel).selectMainFile()
    let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    try CardOperations(channel: secure).selectFineidApplication()
    return secure
  }

  /// Establishes and selects the application on the retained session.
  internal func finishPACE(with accessNumber: CardAccessNumber) {
    condition.lock()
    let plain = channel
    condition.unlock()

    let started = ContinuousClock.now
    let result: Result<SecureMessagingChannel, any Error>
    operationLock.lock()
    do {
      guard let plain else { throw CardOperationError.sessionUnavailable }
      result = .success(try establishPACE(channel: plain, accessNumber: accessNumber))
    } catch {
      result = .failure(error)
    }
    operationLock.unlock()

    var shouldReleaseAfterFailure = false
    condition.lock()
    if ended {
      preparation = .failed(CardOperationError.sessionUnavailable)
    } else {
      switch result {
      case .success(let secure):
        preparation = .ready(secure)
        if activityTimeoutDeferred {
          activityTimeoutDeferred = false
          scheduleActivityTimeoutLocked(seconds: Self.defaultActivityTimeoutSeconds)
        }

      case .failure(let error):
        preparation = .failed(error)
        if activityTimeoutDeferred {
          activityTimeoutDeferred = false
          shouldReleaseAfterFailure = true
        }
      }
    }
    condition.broadcast()
    condition.unlock()

    #if canImport(OSLog)
      let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
      switch result {
      case .success:
        Self.logger.trace("pace: early preparation ready ms=\(elapsed)")
      case .failure(let error):
        Self.logger.trace("pace: early preparation failed \(error) ms=\(elapsed)")
      }
    #endif

    if shouldReleaseAfterFailure {
      release()
    }
  }

  /// Waits until PACE preparation finishes, returning whether it succeeded.
  @discardableResult
  internal func waitForPreparation(timeout: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(timeout)
    while case .running = preparation, Date() < deadline {
      if !condition.wait(until: deadline) {
        break
      }
    }
    if case .ready = preparation {
      return true
    }
    return false
  }
}
