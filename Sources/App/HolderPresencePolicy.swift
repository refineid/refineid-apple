// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// When the requester reads the holder's certificate and when it starts
/// the countdown that withdraws the borrowed identity.
///
/// Presence comes only from the browser. A read that succeeds says the
/// phone answered once, not that it is still here.
internal enum HolderPresencePolicy {
  /// Whether launch reads the certificate before the holder is seen.
  ///
  /// With a browser, the holder's arrival starts the read.
  internal static func readsAtStart(browsesForPresence: Bool) -> Bool {
    !browsesForPresence
  }

  /// Whether a successful read starts the withdrawal countdown: it does
  /// while the browser has not reported the holder, so an identity is
  /// never kept for a phone the browser never saw.
  internal static func armsLossHoldAfterRead(holderSeen: Bool) -> Bool {
    !holderSeen
  }

  /// Whether the browser losing the holder starts the countdown: it does
  /// when the holder was seen or an identity is held.
  internal static func armsLossHoldOnLoss(holderSeen: Bool, identityHeld: Bool) -> Bool {
    holderSeen || identityHeld
  }
}
