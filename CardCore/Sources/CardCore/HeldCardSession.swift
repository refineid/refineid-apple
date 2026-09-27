// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(OSLog)
  import OSLog
#endif

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
public final class HeldCardSession: @unchecked Sendable {
  // MARK: Nested Types

  /// Exclusive use of a prepared channel for one operation.
  ///
  /// The lock stays held for the lifetime of this value, so the secure
  /// messaging counter cannot be advanced by two token sessions at once.
  public final class PreparedChannelLease {
    /// The established secure channel ready for card operations.
    public let channel: SecureMessagingChannel
    private let operationLock: NSLock
    private let onRelease: (@Sendable () -> Void)?

    /// Creates a lease holding exclusive access to the secure channel.
    internal init(
      channel: SecureMessagingChannel,
      operationLock: NSLock,
      onRelease: (@Sendable () -> Void)?
    ) {
      self.channel = channel
      self.operationLock = operationLock
      self.onRelease = onRelease
    }

    deinit {
      operationLock.unlock()
      onRelease?()
    }
  }

  /// Where preparation of the retained channel has reached.
  internal enum PreparationState {
    case idle
    case running
    case ready(SecureMessagingChannel)
    case leased(SecureMessagingChannel)
    case failed(any Error)
  }

  // MARK: Static Properties

  #if canImport(OSLog)
    internal static let logger = Logger(
      subsystem: "fi.refineid.ReFineID",
      category: "held-session"
    )
  #endif

  /// Maximum time a signer waits for PACE in the system-owned NFC field.
  internal static let preparationWaitSeconds: TimeInterval = 8

  /// Default duration before an unclaimed held field is dismissed to reveal user prompts.
  public static let defaultActivityTimeoutSeconds: TimeInterval = 0.35

  /// Milliseconds per second for diagnostic timing formatting.
  private static let millisecondsPerSecond: Double = 1_000

  // MARK: Properties

  /// Coordinates the early PACE worker and the later signer.
  internal let condition = NSCondition()

  /// Serialises all use of the secure channel's mutable sequence counter.
  internal let operationLock = NSLock()

  /// The channel whose session is being held, or nil once released.
  internal var channel: (any HeldCardChannel)?

  /// Preparation state for `channel`.
  internal var preparation = PreparationState.idle

  /// Whether the slot observation has ended this hold.
  internal var ended = false

  /// Whether the activity timeout expired while PACE was running, deferring release.
  internal var activityTimeoutDeferred = false

  /// Timer that releases the held session if no cryptographic operation
  /// claims it before the timeout.
  private var activityTimeoutWorkItem: DispatchWorkItem?

  // MARK: Computed Properties

  /// The held channel, or nil when none is held.
  public var current: (any HeldCardChannel)? {
    condition.lock()
    defer { condition.unlock() }
    return channel
  }

  /// Whether a valid channel is currently retained and not ended.
  public var isAvailable: Bool {
    condition.lock()
    defer { condition.unlock() }
    return channel != nil && !ended
  }

  // MARK: Lifecycle

  /// Creates an unconfigured held session with no retained card channel.
  public init() {
    // Unconfigured session.
  }

  // MARK: Functions

  /// Waits until a valid channel is retained and ready, or returns immediately if ended/unavailable.
  public func waitForAvailable(timeout: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    if ended {
      return false
    }
    if channel != nil {
      return true
    }
    let deadline = Date().addingTimeInterval(timeout)
    while channel == nil, !ended, Date() < deadline {
      if !condition.wait(until: deadline) {
        break
      }
    }
    return channel != nil && !ended
  }

  /// Takes ownership of `channel`, whose session is already open.
  public func retain(_ channel: any HeldCardChannel) {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    activityTimeoutDeferred = false
    self.channel = channel
    preparation = .idle
    ended = false
    condition.broadcast()
    condition.unlock()
    #if canImport(OSLog)
      Self.logger.trace("held session: taken")
    #endif
  }

  /// Schedules a timeout releasing the held session if no sign or auth operation arrives.
  ///
  /// In contactless Safari authentication, the browser often queries token certificates
  /// while presenting a modal certificate acceptance prompt behind SpringBoard's NFC sheet.
  /// Releasing the retained field after a brief delay dismisses the NFC sheet promptly so
  /// the user can interact with Safari's prompt without waiting for the full slot idle timeout.
  public func scheduleActivityTimeout(seconds: TimeInterval) {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutDeferred = false
    scheduleActivityTimeoutLocked(seconds: seconds)
    condition.unlock()
  }

  /// Schedules the default activity timeout releasing the held session if unclaimed.
  public func scheduleActivityTimeout() {
    scheduleActivityTimeout(seconds: Self.defaultActivityTimeoutSeconds)
  }

  /// Cancels any scheduled activity timeout when an active operation claims this session.
  public func cancelActivityTimeout() {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    activityTimeoutDeferred = false
    condition.unlock()
  }

  /// Ends and forgets the held session; safe to call repeatedly.
  ///
  /// Call this only when the slot reports the card genuinely `.missing`.
  /// Releasing on any other state was measured tearing down a signature
  /// part way through a read - a card momentarily out of the field is
  /// still the same card.
  public func release() {
    condition.lock()
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    activityTimeoutDeferred = false
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

    if let outgoing {
      #if canImport(OSLog)
        Self.logger.trace("held session: released held=true")
      #endif
      operationLock.lock()
      outgoing.endSession()
      operationLock.unlock()
    } else {
      #if canImport(OSLog)
        Self.logger.trace("held session: released held=false")
      #endif
    }
  }

  #if DEBUG
    /// Simulates the firing of the scheduled activity timeout for deterministic unit tests.
    public func fireActivityTimeoutForTesting(
      seconds: TimeInterval = defaultActivityTimeoutSeconds
    ) {
      handleActivityTimeout(seconds: seconds)
    }
  #endif

  internal func scheduleActivityTimeoutLocked(seconds: TimeInterval) {
    activityTimeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.handleActivityTimeout(seconds: seconds)
    }
    activityTimeoutWorkItem = workItem
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + seconds,
      execute: workItem
    )
  }

  /// Evaluates an activity timeout, releasing an unused or unclaimed channel
  /// while deferring release if PACE is actively running.
  internal func handleActivityTimeout(seconds: TimeInterval) {
    condition.lock()
    guard channel != nil, !ended else {
      condition.unlock()
      return
    }

    switch preparation {
    case .idle:
      // An unused discovery field: no PACE was started, no operation claimed it.
      condition.unlock()
      #if canImport(OSLog)
        let milliseconds = Int(seconds * Self.millisecondsPerSecond)
        Self.logger.notice(
          "held session: unused discovery timeout (\(milliseconds)ms) - releasing contactless field"
        )
      #endif
      release()

    case .running:
      // Timer fired during PACE: do NOT close the card session mid-PACE.
      activityTimeoutDeferred = true
      condition.unlock()
      #if canImport(OSLog)
        Self.logger.trace("held session: activity timeout during PACE - deferring release")
      #endif

    case .ready:
      // An unclaimed, prepared field: release promptly to allow prompts to appear.
      condition.unlock()
      #if canImport(OSLog)
        let milliseconds = Int(seconds * Self.millisecondsPerSecond)
        Self.logger.notice(
          "held session: unclaimed prepared field timeout (\(milliseconds)ms) - releasing contactless field"
        )
      #endif
      release()

    case .leased:
      condition.unlock()
      #if canImport(OSLog)
        Self.logger.trace("held session: activity timeout during active lease - ignoring")
      #endif

    case .failed:
      condition.unlock()
      release()
    }
  }

  /// Restores preparation to ready when a lease ends.
  internal func finishLease() {
    condition.lock()
    if case .leased(let secure) = preparation {
      preparation = .ready(secure)
      condition.broadcast()
    }
    condition.unlock()
  }
}
