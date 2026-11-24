// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if DEBUG && canImport(OSLog)
  import OSLog
#endif

extension HeldCardSession {
  // MARK: Nested Types

  private struct PreparationStart {
    let channel: any HeldCardChannel
    let generation: UInt64
    let shouldStartHere: Bool
  }

  // MARK: Functions

  /// Starts PACE immediately on a worker, ahead of Safari's sign call.
  public func startPACE(with accessNumber: CardAccessNumber) {
    startPACE(with: accessNumber, prefersEstonian2018: false)
  }

  /// Starts PACE immediately on a worker, selecting EstEID 2018 IAS-ECC root
  /// first when `prefersEstonian2018` is true.
  public func startPACE(
    with accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool
  ) {
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
      finishPACE(
        with: accessNumber,
        prefersEstonian2018: prefersEstonian2018,
        channel: plain,
        generation: preparingGeneration
      )
    }
  }

  /// Leases the exact secure channel prepared for this field.
  ///
  /// A signer arriving while early PACE is in flight waits for it. A
  /// discovery hold starts preparation here when signing claims its field.
  public func preparedChannel(
    accessNumber: CardAccessNumber
  ) throws -> PreparedChannelLease {
    try preparedChannel(accessNumber: accessNumber, prefersEstonian2018: false)
  }

  /// Leases the exact secure channel prepared for this field, preferring
  /// EstEID 2018 IAS-ECC root when `prefersEstonian2018` is true.
  public func preparedChannel(
    accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool
  ) throws -> PreparedChannelLease {
    cancelActivityTimeout()
    let start = try beginPreparationIfIdle()
    if start.shouldStartHere {
      recordLifecycle("PACE started on sign generation=\(start.generation)")
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        finishPACE(
          with: accessNumber,
          prefersEstonian2018: prefersEstonian2018,
          channel: start.channel,
          generation: start.generation
        )
      }
    }
    let deadline = Date().addingTimeInterval(preparationWait)
    let finalState = try claimPreparedChannel(deadline: deadline, generation: start.generation)
    return try finishClaimingLease(finalState, generation: start.generation)
  }

  private func beginPreparationIfIdle() throws -> PreparationStart {
    condition.lock()
    defer { condition.unlock() }
    guard let plain = channel, !ended else {
      throw CardOperationError.sessionUnavailable
    }
    let preparingGeneration = generation
    if case .idle = preparation {
      preparation = .running
      return PreparationStart(
        channel: plain,
        generation: preparingGeneration,
        shouldStartHere: true
      )
    }
    return PreparationStart(
      channel: plain,
      generation: preparingGeneration,
      shouldStartHere: false
    )
  }

  private func finishClaimingLease(
    _ finalState: PreparationState,
    generation preparingGeneration: UInt64
  ) throws -> PreparedChannelLease {
    switch finalState {
    case .ready(let secure, let numbering):
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
      return PreparedChannelLease(
        channel: secure,
        cardNumbering: numbering,
        operationLock: operationLock
      ) { [weak self] in
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
    if case .ready(let secure, let numbering) = finalState {
      preparation = .leased(secure, numbering)
    }
    condition.unlock()
    return finalState
  }

  /// Establishes keys and selects the card's eID application over the secure channel.
  private func establishPACE(
    channel: any CardChannel,
    accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool
  ) throws -> (SecureMessagingChannel, CredentialReferenceSet?) {
    let (_, operations) = try CardOperations.openCanSecureChannel(
      over: channel,
      accessNumber: accessNumber,
      prefersEstonian2018: prefersEstonian2018,
      diagnostic: { [self] event in
        recordLifecycle(event)
      }
    )
    guard let secure = operations.channel as? SecureMessagingChannel else {
      throw CardOperationError.sessionUnavailable
    }
    return (secure, operations.resolvedNumbering)
  }

  /// Establishes and selects the application on the retained session.
  internal func finishPACE(
    with accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool,
    channel plain: any HeldCardChannel,
    generation expectedGeneration: UInt64
  ) {
    let result = runLockedPaceEstablishment(
      with: accessNumber,
      prefersEstonian2018: prefersEstonian2018,
      channel: plain,
      generation: expectedGeneration
    )
    var shouldReleaseAfterFailure = false
    condition.lock()
    guard !ended, generation == expectedGeneration else {
      recordLifecycle("PACE discarded generation=\(expectedGeneration)")
      condition.unlock()
      return
    }
    switch result {
    case .success(let (secure, numbering)):
      preparation = .ready(secure, numbering)
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

  private func runLockedPaceEstablishment(
    with accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool,
    channel plain: any HeldCardChannel,
    generation expectedGeneration: UInt64
  ) -> Result<(SecureMessagingChannel, CredentialReferenceSet?), any Error> {
    operationLock.lock()
    defer { operationLock.unlock() }
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
      return .success(
        try establishPACE(
          channel: guarded,
          accessNumber: accessNumber,
          prefersEstonian2018: prefersEstonian2018
        )
      )
    } catch {
      return .failure(error)
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
