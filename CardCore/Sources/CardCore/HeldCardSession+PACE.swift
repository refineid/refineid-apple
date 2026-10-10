// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if DEBUG && canImport(OSLog)
  import OSLog
#endif

extension HeldCardSession {
  // MARK: Functions

  /// Starts PACE immediately on a worker, ahead of Safari's sign call.
  public func startPACE(with accessNumber: CardAccessNumber) {
    condition.lock()
    guard let plain = channel, !ended, case .idle = preparation else {
      condition.unlock()
      return
    }
    preparation = .running
    let preparingGeneration = generation
    recordLifecycle("PACE started generation=\(preparingGeneration)")
    condition.unlock()

    #if DEBUG && canImport(OSLog)
      Self.logger.trace("pace: early preparation started")
    #endif
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      finishPACE(with: accessNumber, channel: plain, generation: preparingGeneration)
    }
  }

  /// Leases the exact secure channel prepared for this field.
  ///
  /// A signer arriving while early PACE is in flight waits for it. A
  /// discovery hold starts preparation here when signing claims its field.
  public func preparedChannel(
    accessNumber: CardAccessNumber
  ) throws -> PreparedChannelLease {
    cancelActivityTimeout()
    var prepareHere = false
    condition.lock()
    guard let plain = channel, !ended else {
      condition.unlock()
      throw CardOperationError.sessionUnavailable
    }
    let preparingGeneration = generation
    if case .idle = preparation {
      preparation = .running
      prepareHere = true
    }
    condition.unlock()

    if prepareHere {
      recordLifecycle("PACE started on sign generation=\(preparingGeneration)")
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        finishPACE(with: accessNumber, channel: plain, generation: preparingGeneration)
      }
    }

    let deadline = Date().addingTimeInterval(Self.preparationWaitSeconds)
    let finalState = try claimPreparedChannel(deadline: deadline, generation: preparingGeneration)

    switch finalState {
    case .ready(let secure):
      operationLock.lock()
      condition.lock()
      let valid = !ended && generation == preparingGeneration
      condition.unlock()
      guard valid else {
        operationLock.unlock()
        throw CardOperationError.sessionUnavailable
      }
      recordLifecycle("lease claimed generation=\(preparingGeneration)")
      #if DEBUG && canImport(OSLog)
        Self.logger.trace("pace: prepared channel reused")
      #endif
      return PreparedChannelLease(channel: secure, operationLock: operationLock) { [weak self] in
        self?.finishLease(generation: preparingGeneration)
      }

    case .failed(let error):
      throw error

    case .idle, .running, .leased:
      preconditionFailure("PACE preparation did not reach a terminal state")
    }
  }

  /// Waits until PACE preparation finishes and claims the lease on the channel.
  private func claimPreparedChannel(
    deadline: Date, generation expectedGeneration: UInt64
  ) throws -> PreparationState {
    condition.lock()
    recordLifecycle("waiting preparation generation=\(expectedGeneration)")
    while !ended, generation == expectedGeneration, case .running = preparation {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw CardOperationError.sessionUnavailable
      }
    }
    while !ended, generation == expectedGeneration, case .leased = preparation {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw CardOperationError.sessionUnavailable
      }
    }
    guard !ended, generation == expectedGeneration else {
      condition.unlock()
      throw CardOperationError.sessionUnavailable
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
    channel: any CardChannel,
    accessNumber: CardAccessNumber
  ) throws -> SecureMessagingChannel {
    try? CardOperations(channel: channel).selectMainFile()
    let keys = try PaceEstablishment(
      channel: channel,
      diagnostic: { [self] event in
        recordLifecycle(event)
      }
    ).establish(with: accessNumber)
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    try CardOperations(channel: secure).selectFineidApplication()
    return secure
  }

  /// Establishes and selects the application on the retained session.
  internal func finishPACE(
    with accessNumber: CardAccessNumber,
    channel plain: any HeldCardChannel,
    generation expectedGeneration: UInt64
  ) {

    let result: Result<SecureMessagingChannel, any Error>
    operationLock.lock()
    do {
      condition.lock()
      let valid = !ended && generation == expectedGeneration
      condition.unlock()
      guard valid else { throw CardOperationError.sessionUnavailable }
      let guarded = HeldSessionChannel(
        channel: plain,
        isAvailable: { [self] in
          condition.lock()
          defer { condition.unlock() }
          return !ended && generation == expectedGeneration
        })
      result = .success(try establishPACE(channel: guarded, accessNumber: accessNumber))
    } catch {
      result = .failure(error)
    }
    operationLock.unlock()

    var shouldReleaseAfterFailure = false
    condition.lock()
    guard !ended, generation == expectedGeneration else {
      recordLifecycle("PACE discarded generation=\(expectedGeneration)")
      condition.unlock()
      return
    }
    switch result {
    case .success(let secure):
      preparation = .ready(secure)
      recordLifecycle("PACE ready generation=\(expectedGeneration)")
      if activityTimeoutDeferred {
        activityTimeoutDeferred = false
        scheduleActivityTimeoutLocked(seconds: Self.defaultActivityTimeoutSeconds)
      }

    case .failure(let error):
      preparation = .failed(error)
      recordLifecycle("PACE failed generation=\(expectedGeneration)")
      if activityTimeoutDeferred {
        activityTimeoutDeferred = false
        shouldReleaseAfterFailure = true
      }
    }
    condition.broadcast()
    condition.unlock()

    if shouldReleaseAfterFailure {
      release(reason: .preparationFailed)
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
