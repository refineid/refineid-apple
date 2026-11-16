// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// Per-origin sliding-window rate limiter and post-refusal cooldown
/// guarding the SCS PIN prompt against prompt-fatigue loops.
public final class ScsPromptRateLimiter: Sendable {
  /// Whether a new PIN prompt may be shown for an origin at `now`.
  public enum Decision: Equatable, Sendable {
    /// The prompt may proceed and has been counted against the window.
    case allow

    /// The prompt is suppressed with a policy reason.
    case throttled(String)
  }

  private struct Bucket {
    var timestamps: [Date]
    var cooldownUntil: Date?
    var lastTouched: Date
  }

  private static let missingOriginKey = "(no-origin)"

  private let windowSeconds: Double
  private let maximumPerWindow: Int
  private let refusalCooldownSeconds: Double
  private let buckets = OSAllocatedUnfairLock<[String: Bucket]>(initialState: [:])

  /// Creates a rate limiter with explicit window and cooldown bounds.
  public init(
    windowSeconds: Double,
    maximumPerWindow: Int,
    refusalCooldownSeconds: Double
  ) {
    self.windowSeconds = windowSeconds
    self.maximumPerWindow = maximumPerWindow
    self.refusalCooldownSeconds = refusalCooldownSeconds
  }

  /// Creates a rate limiter using the standard SCS prompt policy.
  public convenience init() {
    self.init(
      windowSeconds: ScsValues.promptWindowSeconds,
      maximumPerWindow: ScsValues.promptMaximumPerWindow,
      refusalCooldownSeconds: ScsValues.promptRefusalCooldownSeconds
    )
  }

  /// Evaluates `origin` at `now` and records the prompt when allowed.
  public func checkAndRecordPrompt(origin: String?, at now: Date) -> Decision {
    let key = origin ?? Self.missingOriginKey
    return buckets.withLock { state in
      prune(state: &state, now: now)
      var bucket = state[key] ?? Bucket(timestamps: [], cooldownUntil: nil, lastTouched: now)
      if let cooldownUntil = bucket.cooldownUntil, now < cooldownUntil {
        return .throttled("signature prompt is cooling down after a cancelled or refused PIN")
      }
      let cutoff = now.addingTimeInterval(-windowSeconds)
      bucket.timestamps.removeAll { timestamp in timestamp <= cutoff }
      guard bucket.timestamps.count < maximumPerWindow else {
        return .throttled("too many signature prompts from this origin; wait before retrying")
      }
      bucket.timestamps.append(now)
      bucket.cooldownUntil = nil
      bucket.lastTouched = now
      state[key] = bucket
      return .allow
    }
  }

  /// Imposes the post-refusal cooldown on `origin` after a cancelled or
  /// rejected PIN entry.
  public func recordRefusal(origin: String?, at now: Date) {
    let key = origin ?? Self.missingOriginKey
    let until = now.addingTimeInterval(refusalCooldownSeconds)
    buckets.withLock { state in
      prune(state: &state, now: now)
      var bucket = state[key] ?? Bucket(timestamps: [], cooldownUntil: nil, lastTouched: now)
      bucket.cooldownUntil = until
      bucket.lastTouched = now
      state[key] = bucket
    }
  }

  /// Clears all recorded prompt history and cooldowns.
  public func reset() {
    buckets.withLock { state in
      state.removeAll()
    }
  }

  private func prune(state: inout [String: Bucket], now: Date) {
    let cutoff = now.addingTimeInterval(-windowSeconds)
    for (key, var bucket) in state {
      bucket.timestamps.removeAll { timestamp in timestamp <= cutoff }
      let cooledDown = bucket.cooldownUntil.map { now >= $0 } ?? true
      if bucket.timestamps.isEmpty, cooledDown {
        state.removeValue(forKey: key)
      } else {
        state[key] = bucket
      }
    }
    while state.count >= ScsValues.promptMaxTrackedOrigins,
      let oldest = state.min(by: { $0.value.lastTouched < $1.value.lastTouched })?.key
    {
      state.removeValue(forKey: oldest)
    }
  }
}
