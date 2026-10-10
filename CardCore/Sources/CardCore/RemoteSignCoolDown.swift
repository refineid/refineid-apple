// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// When a token answers a browser's signature request without asking the
/// paired phone.
///
/// A TLS client answering a certificate challenge repeats it as soon as
/// the previous answer fails. Without a card on the phone each answer
/// takes the phone's full card wait, so the phone is never idle and the
/// browser's connection never settles. After a request that ended without
/// a card or without the holder's approval, further requests are refused
/// for a while; the pause doubles with each consecutive such ending up to
/// a ceiling, and any signature or an explicit resume clears it.
///
/// The state lives in shared defaults, so the token extension that pauses
/// and the app that shows and clears the pause read the same record.
public struct RemoteSignCoolDown: Sendable {
  /// How one forwarded request ended, as far as pausing is concerned.
  public enum Ending: Sendable, Equatable {
    /// The phone returned a signature.
    case signed

    /// No card answered, the holder declined, or the request lapsed.
    case unattended

    /// Anything else; it neither pauses nor resets.
    case other
  }

  /// The pause after one unattended ending.
  public static let initialPause: TimeInterval = 15

  /// The longest pause.
  public static let ceiling: TimeInterval = 300

  /// The cool-down the app and its token extensions share.
  public static let shared = Self(defaultsSuite: "group.fi.refineid.RefineID")

  /// How much each consecutive unattended ending lengthens the pause.
  private static let growth: TimeInterval = 2

  private static let consecutiveKey = "rapp.sign.coolDown.consecutive"
  private static let untilKey = "rapp.sign.coolDown.until"

  private let defaultsSuite: String?

  private var defaults: UserDefaults {
    defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

  /// A cool-down recorded in the defaults suite `defaultsSuite`, or the
  /// standard defaults when it is `nil`.
  public init(defaultsSuite: String?) {
    self.defaultsSuite = defaultsSuite
  }

  /// The pause after `consecutive` unattended endings.
  public static func pause(after consecutive: Int) -> TimeInterval {
    var pause = initialPause
    for _ in 1..<max(consecutive, 1) where pause < ceiling {
      pause *= growth
    }
    return min(pause, ceiling)
  }

  /// When the current pause ends, or `nil` when requests reach the phone.
  public func pausedUntil(at now: Date) -> Date? {
    let until = defaults.double(forKey: Self.untilKey)
    guard until > 0 else { return nil }
    let end = Date(timeIntervalSince1970: until)
    return now < end ? end : nil
  }

  /// Whether a request arriving at `now` is refused without reaching the phone.
  public func refuses(at now: Date) -> Bool {
    pausedUntil(at: now) != nil
  }

  /// Records how a forwarded request ended at `now`.
  public func record(_ ending: Ending, at now: Date) {
    switch ending {
    case .signed:
      resume()

    case .unattended:
      let consecutive = defaults.integer(forKey: Self.consecutiveKey) + 1
      defaults.set(consecutive, forKey: Self.consecutiveKey)
      let end = now.addingTimeInterval(Self.pause(after: consecutive))
      defaults.set(end.timeIntervalSince1970, forKey: Self.untilKey)

    case .other:
      break
    }
  }

  /// Lets the next request reach the phone and starts the count over.
  public func resume() {
    defaults.removeObject(forKey: Self.consecutiveKey)
    defaults.removeObject(forKey: Self.untilKey)
  }
}
