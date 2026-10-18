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
/// a ceiling, and any signature or an explicit resume clears it. An
/// unattended ending long after the last pause ended starts the count
/// over.
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

  /// The longest pause: a holder that returns with its card waits at
  /// most this long for the next browser request to reach it.
  public static let ceiling: TimeInterval = 60

  /// The system-wide notification posted when a pause begins or ends.
  public static let changeNotificationName = "fi.refineid.remoteSignCoolDownChanged"

  /// The cool-down the app and its token extensions share.
  public static let shared = Self(defaultsSuite: "group.fi.refineid.RefineID")

  /// How much each consecutive unattended ending lengthens the pause.
  private static let growth: TimeInterval = 2

  private static let consecutiveKey = "rapp.sign.coolDown.consecutive"
  private static let untilKey = "rapp.sign.coolDown.endsAt"

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
    for _ in 1..<max(consecutive, 1) {
      guard pause < ceiling else { break }
      pause *= growth
    }
    return min(pause, ceiling)
  }

  /// Tells every process sharing the record that a pause began or ended.
  ///
  /// The token extension and the app are separate processes; a change one
  /// writes to shared defaults reaches the other only through this.
  private static func announceChange() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(changeNotificationName as CFString),
      nil,
      nil,
      true
    )
  }

  /// When the current pause ends, or `nil` when requests reach the phone.
  public func pausedUntil(at now: Date) -> Date? {
    let until = defaults.double(forKey: Self.untilKey)
    guard until > 0 else { return nil }
    let end = Date(timeIntervalSinceReferenceDate: until)
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
      // Requests already on their way when a pause began end inside it;
      // they are the same attempt, not further ones.
      guard !refuses(at: now) else { return }
      let lastEnd = defaults.double(forKey: Self.untilKey)
      let isLapsed = lastEnd > 0 && now.timeIntervalSinceReferenceDate - lastEnd > Self.ceiling
      let previous = isLapsed ? 0 : defaults.integer(forKey: Self.consecutiveKey)
      let consecutive = previous + 1
      defaults.set(consecutive, forKey: Self.consecutiveKey)
      let end = now.addingTimeInterval(Self.pause(after: consecutive))
      defaults.set(end.timeIntervalSinceReferenceDate, forKey: Self.untilKey)
      Self.announceChange()

    case .other:
      break
    }
  }

  /// Lets the next request reach the phone and starts the count over.
  public func resume() {
    defaults.removeObject(forKey: Self.consecutiveKey)
    defaults.removeObject(forKey: Self.untilKey)
    Self.announceChange()
  }
}
