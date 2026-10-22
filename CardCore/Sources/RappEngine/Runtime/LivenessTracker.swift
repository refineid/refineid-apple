// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One session's liveness (RAPP v26.10.21 §8.3): a ping after 5 seconds of
/// silence, and again every 5 seconds while the silence lasts; the session
/// is over after 30 seconds without any message from the peer.
///
/// The tracker owns no clock. Every decision is a pure function of an
/// injected monotonic timestamp, so a schedule is reproducible in a test.
internal struct LivenessTracker {
  /// Silence after which a ping is sent.
  internal static let pingAfterSilenceMilliseconds: UInt64 = 5_000

  /// Silence that ends the session.
  internal static let sessionSilenceLimitMilliseconds: UInt64 = 30_000

  private var lastHeardMilliseconds: UInt64
  private var lastPingMilliseconds: UInt64?
  private var outstanding: PingChallenge?
  private var closed = false

  internal init(nowMilliseconds: UInt64) {
    lastHeardMilliseconds = nowMilliseconds
  }

  /// Any message from the peer ends the silence.
  internal mutating func heard(nowMilliseconds: UInt64) {
    lastHeardMilliseconds = nowMilliseconds
    lastPingMilliseconds = nil
  }

  /// Advances the timer.
  ///
  /// The challenge is consumed only when a ping is due.
  internal mutating func poll(
    nowMilliseconds: UInt64, nextChallenge: PingChallenge
  ) -> LivenessDecision {
    guard !closed else { return .alreadyClosed }
    let silence =
      nowMilliseconds > lastHeardMilliseconds
      ? nowMilliseconds - lastHeardMilliseconds : 0
    guard silence < Self.sessionSilenceLimitMilliseconds else {
      closed = true
      return .closeSession
    }
    let sincePing =
      lastPingMilliseconds.map { ping in
        nowMilliseconds > ping ? nowMilliseconds - ping : 0
      } ?? silence
    guard silence >= Self.pingAfterSilenceMilliseconds,
      sincePing >= Self.pingAfterSilenceMilliseconds
    else { return .noAction }
    lastPingMilliseconds = nowMilliseconds
    outstanding = nextChallenge
    return .sendPing(nextChallenge)
  }

  /// Accepts only the exact challenge outstanding.
  internal mutating func receivePong(
    nowMilliseconds: UInt64, challenge: PingChallenge
  ) -> PongDisposition {
    guard outstanding == challenge else { return .ignoredUnmatched }
    outstanding = nil
    heard(nowMilliseconds: nowMilliseconds)
    return .accepted
  }

  /// Closes this tracker permanently.
  internal mutating func close() {
    closed = true
  }
}
