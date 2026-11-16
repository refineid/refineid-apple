// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if FEATURE_CONTACTLESS

  /// Remembers an unseal the card just refused, so the driver does not
  /// spend the reader on the same doomed handshake at every re-offer.
  ///
  /// A failed PACE tears the contactless field, the card re-arrives, and
  /// the system offers it again; nothing has changed, so the next
  /// handshake fails the same way -- for as long as the card rests on the
  /// antenna the reader blinks and serves nobody, and a dual reader's
  /// contact slot queues behind it. One failed attempt per number and
  /// card is enough. The number is remembered as the opaque fingerprint
  /// `CardCredentialStore` derives, never as digits, and the latch expires
  /// on its own so a transient radio fault does not demand a new number:
  /// entering one clears it immediately, waiting out the holdoff clears
  /// it too.
  ///
  /// `@unchecked Sendable` is sound because every access takes the lock.
  internal final class RefusedUnseal: @unchecked Sendable {
    internal static let shared = RefusedUnseal()

    /// Seconds a refusal blocks the identical retry.
    ///
    /// Long enough that a card resting on the antenna is not hammered,
    /// short enough that lifting the card, checking the number and trying
    /// again meets a fresh attempt.
    private static let retryHoldoffSeconds = 30

    /// The holdoff as the clock measures it.
    private static let retryHoldoff: Duration = .seconds(retryHoldoffSeconds)

    private let lock = NSLock()
    private var fingerprint: Data?
    private var answerToReset: Data?
    private var refusedAt: ContinuousClock.Instant?

    /// Whether this exact number was just refused for this card.
    internal func isRefused(fingerprint: Data, answerToReset: Data?) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard let refusedAt,
        fingerprint == self.fingerprint,
        answerToReset == self.answerToReset
      else {
        return false
      }
      return refusedAt.duration(to: ContinuousClock.now) < Self.retryHoldoff
    }

    /// Records a refusal the next offer must not repeat.
    internal func record(fingerprint: Data, answerToReset: Data?) {
      lock.lock()
      self.fingerprint = fingerprint
      self.answerToReset = answerToReset
      refusedAt = ContinuousClock.now
      lock.unlock()
    }

    /// Drops the latch; a successful unseal earns the next one a try.
    internal func clear() {
      lock.lock()
      fingerprint = nil
      answerToReset = nil
      refusedAt = nil
      lock.unlock()
    }
  }
#endif
