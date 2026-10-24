// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Keeps one operation's ``NearFieldMeter`` and redraws the NFC sheet
/// from it on every change.
///
/// Every step change goes through here, so the sheet always shows the
/// whole meter rather than whichever half was written most recently. The
/// card work runs on its own queue and reports from there, so the meter
/// lives behind a lock.
///
/// `@unchecked Sendable` is the audit: the meter and the timer are touched
/// only under the lock, and `draw` is itself safe to call from any thread.
internal final class NearFieldSheet: @unchecked Sendable {
  /// Estimated length of a card's anti-tamper delay, in seconds.
  internal static let defaultRecoverySeconds: Int = 45

  /// Between two redraws of the recovery countdown.
  private static let recoveryTick: DispatchTimeInterval = .seconds(1)

  /// Replaces the message on the sheet.
  private let draw: @Sendable (String) -> Void

  private let lock = NSLock()
  private var meter: NearFieldMeter
  private var recoveryTimer: DispatchSourceTimer?
  private var recoverySecondsLeft = 0

  /// The meter drawn now.
  internal var current: NearFieldMeter {
    lock.withLock { meter }
  }

  /// A sheet for `operation` that draws through `draw`; nothing is drawn
  /// until the first change.
  internal init(
    _ operation: NearFieldOperation,
    draw: @escaping @Sendable (String) -> Void
  ) {
    meter = NearFieldMeter(operation)
    self.draw = draw
  }

  /// What the sheet says while the holder looks for the spot: the meter
  /// of `operation` with no step reached.
  internal static func opening(_ operation: NearFieldOperation) -> String {
    NearFieldMeter(operation).text
  }

  /// `step` runs now and every step before it is done.
  internal func reach(_ step: NearFieldStep) {
    change { $0.reach(step) }
  }

  /// The step running now is done and the next one runs.
  internal func advance() {
    change { $0.advance() }
  }

  /// Every step is done.
  internal func finish() {
    change { $0.finish() }
  }

  /// The operation broke at `step`, or at the step running now when
  /// `step` is nil.
  internal func fail(at step: NearFieldStep?) {
    stopRecovery()
    change { $0.fail(at: step) }
  }

  /// The operation broke at `step`, or at the step running now when
  /// `step` is nil, and `sentence` says why.
  ///
  /// The meter with its broken step is drawn first; the sentence then
  /// replaces it, because the panel truncates anything past its line and
  /// a meter and a reason together cost the reason.
  internal func fail(at step: NearFieldStep?, saying sentence: String) {
    fail(at: step)
    draw(sentence)
  }

  /// Counts down the estimated length of a card's anti-tamper delay
  /// (FIA_AFL.1/PACE) beside the meter, so the holder keeps the card
  /// still while the card waits it out.
  internal func startRecovery() {
    let estimatedSeconds = Self.defaultRecoverySeconds
    let timer = DispatchSource.makeTimerSource(
      queue: DispatchQueue(label: "fi.refineid.nearfield.recovery"))
    let drawn: String = lock.withLock {
      recoveryTimer?.cancel()
      recoveryTimer = timer
      recoverySecondsLeft = estimatedSeconds
      return meter.recoveryText(remainingSeconds: estimatedSeconds)
    }
    timer.schedule(deadline: .now() + Self.recoveryTick, repeating: Self.recoveryTick)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let text: String? = lock.withLock {
        recoverySecondsLeft -= 1
        return recoverySecondsLeft >= 0
          ? meter.recoveryText(remainingSeconds: recoverySecondsLeft) : nil
      }
      if let text {
        draw(text)
      }
    }
    draw(drawn)
    timer.resume()
  }

  /// Stops the recovery countdown.
  internal func stopRecovery() {
    lock.withLock {
      recoveryTimer?.cancel()
      recoveryTimer = nil
    }
  }

  private func change(_ body: (inout NearFieldMeter) -> Void) {
    let drawn: String = lock.withLock {
      body(&meter)
      return meter.text
    }
    draw(drawn)
  }

  deinit {
    recoveryTimer?.cancel()
  }
}
