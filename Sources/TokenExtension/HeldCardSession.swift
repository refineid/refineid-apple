// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// A card session opened while the token was minted and deliberately kept
/// open, so the signature that follows still has a live field to work in.
///
/// Only the system-driven contactless path needs this, and it was bought
/// with a measured failure: `ctkd` owns the built-in contactless slot and
/// ends it about two seconds after the mint, so a `beginSession` issued
/// when the signature finally arrives fails with `TKError -7` - there is
/// no field left to open. Holding the session taken at the mint keeps one
/// live field under the mint, the PACE run and the signature.
///
/// The release is driven by a slot-state observation, which is a
/// `@Sendable` closure, and `Token` is not `Sendable` - so the closure
/// cannot capture the token and captures this box instead.
/// `@unchecked Sendable` is sound because every access goes through the
/// lock: the observation fires on CryptoTokenKit's queue while a
/// signature runs on the session's.
///
/// Provenance: `Token.HeldSession` in the donor
/// `platform/apple/RefineIDTokenExtension/Token.swift`, whose held value
/// was that implementation's Rust-FFI relay.
internal final class HeldCardSession: @unchecked Sendable {
  /// Exclusive use of a prepared channel for one operation.
  ///
  /// The lock stays held for the lifetime of this value, so the secure
  /// messaging counter cannot be advanced by two token sessions at once.
  internal final class PreparedChannelLease {
    internal let channel: SecureMessagingChannel
    private let operationLock: NSLock

    internal init(channel: SecureMessagingChannel, operationLock: NSLock) {
      self.channel = channel
      self.operationLock = operationLock
    }

    deinit {
      operationLock.unlock()
    }
  }

  /// Where preparation of the retained channel has reached.
  private enum PreparationState {
    case idle
    case running
    case ready(SecureMessagingChannel)
    case failed(any Error)
  }

  /// Maximum time a signer waits for PACE in the system-owned NFC field.
  private static let preparationWaitSeconds: TimeInterval = 8

  /// Default duration before an unclaimed held field is dismissed to reveal user prompts.
  internal static let defaultActivityTimeoutSeconds: TimeInterval = 0.35

  /// Milliseconds per second for diagnostic timing formatting.
  private static let millisecondsPerSecond: Double = 1_000

  /// Coordinates the early PACE worker and the later signer.
  private let condition = NSCondition()

  /// Serialises all use of the secure channel's mutable sequence counter.
  private let operationLock = NSLock()

  /// The channel whose session is being held, or nil once released.
  private var channel: SmartCardChannel?

  /// Preparation state for `channel`.
  private var preparation = PreparationState.idle

  /// Whether the slot observation has ended this hold.
  private var ended = false

  /// Timer that releases the held session if no cryptographic operation
  /// claims it before the timeout.
  private var activityTimeoutWorkItem: DispatchWorkItem?

  /// The held channel, or nil when none is held.
  internal var current: SmartCardChannel? {
    condition.lock()
    defer { condition.unlock() }
    return channel
  }

  /// Whether a valid channel is currently retained and not ended.
  internal var isAvailable: Bool {
    condition.lock()
    defer { condition.unlock() }
    return channel != nil && !ended
  }

  /// Waits until a valid channel is retained and ready, or until the timeout expires.
  internal func waitForAvailable(timeout: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    if channel != nil, !ended {
      return true
    }
    let deadline = Date().addingTimeInterval(timeout)
    while channel == nil || ended, Date() < deadline {
      if !condition.wait(until: deadline) {
        break
      }
    }
    return channel != nil && !ended
  }

  /// Takes ownership of `channel`, whose session is already open.
  internal func retain(_ channel: SmartCardChannel) {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    self.channel = channel
    preparation = .idle
    ended = false
    condition.broadcast()
    condition.unlock()
    TokenLog.trace("held session: taken")
  }

  /// Schedules a timeout releasing the held session if no sign or auth operation arrives.
  ///
  /// In contactless Safari authentication, the browser often queries token certificates
  /// while presenting a modal certificate acceptance prompt behind SpringBoard's NFC sheet.
  /// Releasing the retained field after a brief delay dismisses the NFC sheet promptly so
  /// the user can interact with Safari's prompt without waiting for the full slot idle timeout.
  internal func scheduleActivityTimeout(seconds: TimeInterval) {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      condition.lock()
      guard channel != nil, !ended else {
        condition.unlock()
        return
      }
      condition.unlock()
      let milliseconds = Int(seconds * Self.millisecondsPerSecond)
      TokenLog.notice(
        "held session: activity timeout (\(milliseconds)ms) - releasing contactless field"
      )
      release()
    }
    activityTimeoutWorkItem = workItem
    condition.unlock()
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + seconds,
      execute: workItem
    )
  }

  /// Schedules the default activity timeout releasing the held session if unclaimed.
  internal func scheduleActivityTimeout() {
    scheduleActivityTimeout(seconds: Self.defaultActivityTimeoutSeconds)
  }

  /// Cancels any scheduled activity timeout when an active operation claims this session.
  internal func cancelActivityTimeout() {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    condition.unlock()
  }

  /// Starts PACE immediately on a worker, ahead of Safari's sign call.
  internal func startPACE(with accessNumber: CardAccessNumber) {
    condition.lock()
    guard channel != nil, case .idle = preparation else {
      condition.unlock()
      return
    }
    preparation = .running
    condition.unlock()

    TokenLog.trace("pace: early preparation started")
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      finishPACE(with: accessNumber)
    }
  }

  /// Leases the exact secure channel prepared for this field.
  ///
  /// A signer arriving while early PACE is in flight waits for it. The
  /// idle branch is only a defensive fallback; normal near-field mints
  /// call ``startPACE(with:)`` before returning the token.
  internal func preparedChannel(
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

    condition.lock()
    let deadline = Date().addingTimeInterval(Self.preparationWaitSeconds)
    while case .running = preparation {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw CardOperationError.sessionUnavailable
      }
    }
    let finalState = preparation
    condition.unlock()

    switch finalState {
    case .ready(let secure):
      operationLock.lock()
      TokenLog.trace("pace: prepared channel reused")
      return PreparedChannelLease(channel: secure, operationLock: operationLock)

    case .failed(let error):
      throw error

    case .idle, .running:
      preconditionFailure("PACE preparation did not reach a terminal state")
    }
  }

  /// Establishes and selects the application on the retained session.
  private func finishPACE(with accessNumber: CardAccessNumber) {
    condition.lock()
    let plain = channel
    condition.unlock()

    let started = ContinuousClock.now
    let result: Result<SecureMessagingChannel, any Error>
    operationLock.lock()
    do {
      guard let plain else {
        throw CardOperationError.sessionUnavailable
      }
      try? CardOperations(channel: plain).selectMainFile()
      let keys = try PaceEstablishment(channel: plain).establish(with: accessNumber)
      let secure = SecureMessagingChannel(wrapping: plain, sessionKeys: keys)
      try CardOperations(channel: secure).selectFineidApplication()
      result = .success(secure)
    } catch {
      result = .failure(error)
    }
    operationLock.unlock()

    condition.lock()
    if ended {
      preparation = .failed(CardOperationError.sessionUnavailable)
    } else {
      switch result {
      case .success(let secure):
        preparation = .ready(secure)

      case .failure(let error):
        preparation = .failed(error)
      }
    }
    condition.broadcast()
    condition.unlock()

    let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    switch result {
    case .success:
      TokenLog.trace("pace: early preparation ready ms=\(elapsed)")

    case .failure(let error):
      TokenLog.trace("pace: early preparation failed \(error) ms=\(elapsed)")
    }
  }

  /// Ends and forgets the held session; safe to call repeatedly.
  ///
  /// Call this only when the slot reports the card genuinely `.missing`.
  /// Releasing on any other state was measured tearing down a signature
  /// part way through a read - a card momentarily out of the field is
  /// still the same card.
  internal func release() {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    let outgoing = channel
    channel = nil
    ended = true
    if case .running = preparation {
      // The worker records the transport failure and wakes waiters.
    } else {
      preparation = .failed(CardOperationError.sessionUnavailable)
      condition.broadcast()
    }
    condition.unlock()
    // Whether there was one to give back is the interesting half: a
    // signature that found no held session is a signature that was about
    // to meet TKError -7.
    TokenLog.trace("held session: released held=\(outgoing != nil)")
    outgoing?.endSession()
  }
}
