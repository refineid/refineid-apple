// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if DEBUG && canImport(OSLog)
  import OSLog
#endif

/// A card session opened while the token was minted and deliberately kept
/// open, so the signature that follows still has a live field to work in.
///
/// A powered field owns its PACE state. Slot loss immediately invalidates that
/// state; transport cleanup waits separately for outstanding channel use.
/// A replacement hold establishes its own secure channel before signing.
///
/// The release is driven by a slot-state observation, which is a
/// `@Sendable` closure, and `Token` is not `Sendable` - so the closure
/// cannot capture the token and captures this box instead.
/// Mutable state is protected by the condition and transport operations by
/// the operation lock. The observation and signer can run on different queues.
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

  #if DEBUG && canImport(OSLog)
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

  internal var generation: UInt64 = 0
  private let diagnostic: (@Sendable (String) -> Void)?
  /// Ephemeral identifier joining lifecycle events to the owning token and transport.
  public let diagnosticIdentifier = UUID().uuidString
  private let diagnosticStart = ContinuousClock.now

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
  ///
  /// Diagnostics run synchronously and must not call back into the session.
  @preconcurrency
  public init(diagnostic: (@Sendable (String) -> Void)? = nil) {
    self.diagnostic = diagnostic
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
    generation += 1
    preparation = .idle
    ended = false
    condition.broadcast()
    recordLifecycle("retained generation=\(generation)")
    condition.unlock()
    #if DEBUG && canImport(OSLog)
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

  /// Invalidates the hold immediately and serializes transport cleanup with card operations.
  public func release(reason: ReleaseReason = .explicit) {
    invalidate(reason: reason)
  }

  private func invalidate(reason: ReleaseReason, unclaimedGeneration: UInt64? = nil) {
    condition.lock()
    if let unclaimedGeneration {
      guard generation == unclaimedGeneration, !ended else {
        condition.unlock()
        return
      }
      switch preparation {
      case .idle, .ready, .failed:
        break
      case .running, .leased:
        condition.unlock()
        return
      }
    }
    activityTimeoutWorkItem?.cancel()
    activityTimeoutWorkItem = nil
    activityTimeoutDeferred = false
    let outgoing = channel
    channel = nil
    ended = true
    preparation = .failed(CardOperationError.sessionUnavailable)
    condition.broadcast()
    if outgoing != nil {
      recordLifecycle("invalidated reason=\(reason.rawValue) generation=\(generation)")
    }
    condition.unlock()

    guard let outgoing else { return }
    if operationLock.try() {
      outgoing.endSession()
      operationLock.unlock()
      recordLifecycle("transport ended")
    } else {
      recordLifecycle("transport cleanup deferred")
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        operationLock.lock()
        outgoing.endSession()
        operationLock.unlock()
        recordLifecycle("transport ended after outstanding operation")
      }
    }
  }

  internal func recordLifecycle(_ event: String) {
    let elapsed = TraceTiming.milliseconds(diagnosticStart.duration(to: ContinuousClock.now))
    diagnostic?("held: id=\(diagnosticIdentifier) ageMs=\(elapsed) \(event)")
  }

  #if DEBUG
    /// Simulates the firing of the scheduled activity timeout for deterministic unit tests.
    public func fireActivityTimeoutForTesting(
      seconds: TimeInterval = defaultActivityTimeoutSeconds
    ) {
      handleActivityTimeout(seconds: seconds, generation: nil)
    }
  #endif

  internal func scheduleActivityTimeoutLocked(seconds: TimeInterval) {
    activityTimeoutWorkItem?.cancel()
    let scheduledGeneration = generation
    let workItem = DispatchWorkItem { [weak self] in
      self?.handleActivityTimeout(seconds: seconds, generation: scheduledGeneration)
    }
    activityTimeoutWorkItem = workItem
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + seconds,
      execute: workItem
    )
  }

  /// Evaluates an activity timeout, releasing an unused or unclaimed channel
  /// while deferring release if PACE is actively running.
  internal func handleActivityTimeout(
    seconds: TimeInterval, generation expectedGeneration: UInt64?
  ) {
    condition.lock()
    guard channel != nil, !ended, expectedGeneration == nil || expectedGeneration == generation
    else {
      condition.unlock()
      return
    }
    let timedGeneration = generation

    switch preparation {
    case .idle:
      // An unused discovery field: no PACE was started, no operation claimed it.
      condition.unlock()
      #if DEBUG && canImport(OSLog)
        let milliseconds = Int(seconds * Self.millisecondsPerSecond)
        Self.logger.notice(
          "held session: unused discovery timeout (\(milliseconds)ms) - releasing contactless field"
        )
      #endif
      invalidate(reason: .activityTimeout, unclaimedGeneration: timedGeneration)

    case .running:
      // Timer fired during PACE: do NOT close the card session mid-PACE.
      activityTimeoutDeferred = true
      condition.unlock()
      #if DEBUG && canImport(OSLog)
        Self.logger.trace("held session: activity timeout during PACE - deferring release")
      #endif

    case .ready:
      // An unclaimed, prepared field: release promptly to allow prompts to appear.
      condition.unlock()
      #if DEBUG && canImport(OSLog)
        let milliseconds = Int(seconds * Self.millisecondsPerSecond)
        Self.logger.notice(
          "held session: unclaimed prepared field timeout (\(milliseconds)ms) - releasing contactless field"
        )
      #endif
      invalidate(reason: .activityTimeout, unclaimedGeneration: timedGeneration)

    case .leased:
      condition.unlock()
      #if DEBUG && canImport(OSLog)
        Self.logger.trace("held session: activity timeout during active lease - ignoring")
      #endif

    case .failed:
      condition.unlock()
      invalidate(reason: .activityTimeout, unclaimedGeneration: timedGeneration)
    }
  }

  /// Restores preparation to ready when a lease ends.
  internal func finishLease(generation leasedGeneration: UInt64) {
    condition.lock()
    if generation == leasedGeneration, !ended, case .leased(let secure) = preparation {
      preparation = .ready(secure)
      condition.broadcast()
    }
    condition.unlock()
  }
}
