// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Remembers when a signing operation was requested across an NFC field renewal.
///
/// In contactless Safari authentication, certificate selection and cryptographic
/// signing occur across distinct system NFC fields. Once the user approves the
/// certificate dialog in Safari, the signature is requested against a field that
/// has expired or a card that has been moved. Marking a pending sign state tells the
/// next minted token to retain its session for signing rather than treating the
/// field as a passive certificate-discovery hold.
internal final class PendingSigningState: @unchecked Sendable {
  // MARK: Static Properties

  internal static let shared = PendingSigningState()
  private static let validDurationSeconds: Int = 25
  private static let validDuration: Duration = .seconds(validDurationSeconds)

  // MARK: Properties

  private let lock = NSLock()
  private var pendingSignTimestamp: ContinuousClock.Instant?

  // MARK: Computed Properties

  /// Whether a signature request is actively pending.
  internal var isPendingSign: Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let timestamp = pendingSignTimestamp else { return false }
    if ContinuousClock.now - timestamp < Self.validDuration {
      return true
    }
    pendingSignTimestamp = nil
    return false
  }

  // MARK: Lifecycle

  private init() {
    // Singleton instance
  }

  // MARK: Functions

  /// Records that a signature has been requested by the system.
  internal func recordPendingSign() {
    lock.lock()
    defer { lock.unlock() }
    pendingSignTimestamp = ContinuousClock.now
  }

  /// Clears any pending sign state upon signature completion or cancellation.
  internal func clear() {
    lock.lock()
    defer { lock.unlock() }
    pendingSignTimestamp = nil
  }
}
