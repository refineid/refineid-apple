// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit

/// Creates signing sessions and retains a time-limited contactless card field.
extension Token {
  // The @objc requirement is throwing; keep `throws` for the bridge.
  // swiftlint:disable:next unneeded_throws_rethrows
  internal func createSession(_: TKToken) throws -> TKTokenSession {
    // Which interface this card is on is the useful half: it says which
    // sign path is about to run. `TKToken` publishes no instance
    // identifier to name it with.
    TokenLog.info(
      "createSession: session requested, token=\(tokenID) interface=\(interface)")
    return TokenSession(token: self)
  }

  /// Takes a card session now and keeps it, so the signature that
  /// follows still has a live field.
  ///
  /// A signing-field contactless mint calls this and nothing else does;
  /// the one-time registration field deliberately stays passive. On the
  /// system-driven signing path the slot that minted this token has ended
  /// by the time the signature is asked for, and a fresh `beginSession`
  /// then fails with `TKError -7`; this one session carries the mint, the
  /// PACE run and the signature.
  ///
  /// Best effort by design: a token that could not hold a session is
  /// still perfectly usable wherever the card stays present, so a
  /// failure here is swallowed rather than failing the mint.
  internal func holdSession(on smartCard: TKSmartCard, isPendingSign: Bool) {
    guard heldSession.current == nil else { return }
    let channel = SmartCardChannel(smartCard, waits: .nearField)
    do {
      try channel.beginSession()
    } catch {
      TokenLog.info("Token.holdSession: no session retained (\(error))")
      return
    }
    heldSession.retain(channel)
    if let accessNumber = sealedAccessNumber {
      heldSession.startPACE(with: accessNumber)
    }
    if !isPendingSign {
      heldSession.scheduleActivityTimeout()
    }
  }

  /// Releases the held session and the cached PIN1 when the card is gone.
  ///
  /// For contactless slots, any non-validCard state indicates that the NFC field
  /// has ended or the card has been moved away from the antenna. Releasing immediately
  /// ensures subsequent operations do not hang against a dead field.
  internal func observeSlotState(of smartCard: TKSmartCard) {
    slotStateObservation = smartCard.slot.observe(\.state, options: [.new]) {
      [held = heldSession, pin1 = acceptedPin1, id = tokenID] observed, change in
      let state = change.newValue ?? observed.state
      TokenLog.trace("slotState: token=\(id) state=\(state)")
      guard state != .validCard else { return }
      held.release()
      pin1.clearAll()
    }
  }
}
