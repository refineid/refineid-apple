// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import Foundation

  /// Keeps the running step states and repaints the NFC sheet from them.
  ///
  /// Every step change and every sentence go through here, so the sheet
  /// always shows the whole meter rather than whichever half was written
  /// most recently. The card work runs on its own queue and the steps
  /// are reported from there, so the states live behind a lock.
  ///
  /// `@unchecked Sendable` is the audit: the dictionary is touched only
  /// under the lock, and the session it draws into is itself safe to
  /// update from any thread.
  internal final class PrimingSheetReporter: @unchecked Sendable {
    /// Default estimated duration of an anti-tamper penalty delay in seconds.
    internal static let defaultRecoverySeconds: Int = 45

    /// The hold this meter is drawn on, so a caller needing the card
    /// does not have to be handed the session separately.
    internal let session: NearFieldCardSession

    private let lock = NSLock()
    private var states: [CardPrimingStep: CardPrimingStep.State] = [:]
    private var recoveryTimer: DispatchSourceTimer?

    internal init(session: NearFieldCardSession) {
      self.session = session
    }

    /// Records a step's state and repaints the meter.
    internal func report(_ step: CardPrimingStep, _ state: CardPrimingStep.State) {
      lock.lock()
      states[step] = state
      if step == .secureChannel, state == .done || state == .failed {
        recoveryTimer?.cancel()
        recoveryTimer = nil
      }
      let snapshot = states
      lock.unlock()
      session.update(message: PrimingSheetMessage.meter(states: snapshot))
    }

    /// Starts a live countdown on the sheet using the default estimated recovery time.
    internal func startRecovery() {
      startRecovery(estimatedSeconds: Self.defaultRecoverySeconds)
    }

    /// Starts a live countdown on the sheet to keep the holder's attention
    /// while waiting out a card anti-tamper penalty delay (FIA_AFL.1/PACE).
    internal func startRecovery(estimatedSeconds: Int) {
      lock.lock()
      recoveryTimer?.cancel()
      recoveryTimer = nil
      var remaining = estimatedSeconds
      let timer = DispatchSource.makeTimerSource(
        queue: DispatchQueue(label: "fi.refineid.priming.recovery")
      )
      timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
      timer.setEventHandler { [weak self] in
        guard let self else { return }
        lock.lock()
        remaining -= 1
        let currentRemaining = remaining
        let snapshot = states
        lock.unlock()
        if currentRemaining >= 0 {
          session.update(
            message: PrimingSheetMessage.recoveryMeter(
              states: snapshot,
              remainingSeconds: currentRemaining))
        }
      }
      recoveryTimer = timer
      let snapshot = states
      lock.unlock()
      session.update(
        message: PrimingSheetMessage.recoveryMeter(
          states: snapshot,
          remainingSeconds: remaining))
      timer.resume()
    }

    /// Stops the recovery countdown timer.
    internal func stopRecovery() {
      lock.lock()
      recoveryTimer?.cancel()
      recoveryTimer = nil
      lock.unlock()
    }

    /// Replaces the whole message with why the hold stopped.
    ///
    /// The meter goes when this is called, and deliberately: the panel
    /// truncates anything past its line, so a meter and a reason
    /// together cost the reason. A hold that is about to dismiss has one
    /// thing left to say and it is not how far it got.
    internal func fail(_ sentence: String) {
      stopRecovery()
      session.update(message: sentence)
    }

    deinit {
      recoveryTimer?.cancel()
    }
  }

#endif
