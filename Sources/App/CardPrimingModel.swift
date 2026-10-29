// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import SwiftUI

  /// What the Safari setup action needs, and the one thing it can do.
  ///
  /// The model holds no secret. It reads the card access number through
  /// ``CardCredentialStore``, which never hands the digits back. Apple's
  /// NFC sheet reports the live operation; after it closes, the setup form
  /// retains only a sanitized failure sentence.
  @MainActor
  internal final class CardPrimingModel: ObservableObject {
    /// Result retained only for device automation.
    internal enum RunResult: Equatable {
      case notRun
      case succeeded
      case failed
    }

    /// Threshold of consecutive phase 2 stalls required to trigger recovery mode.
    private static let recoveryStallThreshold: Int = 2

    /// What the device currently holds, so the screen can say whether
    /// priming is even possible.
    @Published internal private(set) var contents = CardCredentialStore.contents()

    /// Whether this device offers the phone's own antenna.
    ///
    /// Reader selection is automatic: an available transport is always
    /// usable and there is no holder preference that can disable it.
    @Published internal private(set) var allowsNearField = SupportedCardTransports.offersNearField

    /// True while a hold is in progress.
    @Published internal private(set) var isRunning = false

    /// The last run's testable result, deliberately not rendered in the setup form.
    ///
    /// Apple's NFC sheet reports it to the holder.
    @Published internal private(set) var lastRunResult = RunResult.notRun

    /// A short, sanitized failure retained after Apple's NFC sheet closes.
    @Published internal private(set) var failure: String?

    /// What the card refused, when the refusal names a route to take.
    ///
    /// Read by the setup screen straight after a run, so a single hold can
    /// send the holder to activation or back to the access number without
    /// asking for the card again.
    @Published internal private(set) var refusal: CardSetupRefusal?

    /// The credential counters the last hold read.
    @Published internal private(set) var credentialReport: CredentialProbeReport?

    /// Number of consecutive times priming stalled at phase 2 (secureChannel / PACE).
    @Published internal private(set) var consecutiveSecureChannelStalls: Int = 0

    /// Whether the next priming attempt will run in recovery mode with an extended budget and countdown.
    ///
    /// Stalling twice in a row at phase 2 (2/5) is the clear signature of a card
    /// enforcing an anti-tamper penalty delay (FIA_AFL.1/PACE).
    internal var isRecoveryModeNext: Bool {
      consecutiveSecureChannelStalls >= Self.recoveryStallThreshold
    }

    /// Refreshes what is stored, without touching any secret.
    internal func refresh() {
      contents = CardCredentialStore.contents()
      allowsNearField = SupportedCardTransports.offersNearField
    }

    /// Primes the card for later system-driven logins with the access
    /// number alone; PIN 1 is asked for when the card first signs (RAPP
    /// v26.10.29 §11 item 2).
    ///
    /// The access number is supplied rather than read from storage, because
    /// a first setup has not stored one yet: this hold is what proves it.
    internal func prime(cardAccessNumber: String) async {
      guard !isRunning else { return }
      if DemoMode.shared.isActive {
        await primeVirtualCard(cardAccessNumber: cardAccessNumber)
        return
      }
      refresh()
      guard allowsNearField else { return }
      isRunning = true
      lastRunResult = .notRun
      failure = nil
      refusal = nil
      credentialReport = nil
      let isRecovery = isRecoveryModeNext
      // The meter on the system NFC sheet carries progress; the holder
      // is looking at the card, not at this screen.
      let outcome = await CardPriming.prime(
        cardAccessNumber: cardAccessNumber,
        isRecovery: isRecovery)
      // The sound is started and answered inside the panel's lifetime,
      // in `CardPriming`; nothing here makes a noise after it closed. A
      // hold the holder cancelled never got as far as a sound at all.
      refusal = outcome.refusal
      credentialReport = outcome.credentialReport
      if outcome.cancelled {
        lastRunResult = .notRun
        failure = nil
      } else if outcome.stored, outcome.registered {
        consecutiveSecureChannelStalls = 0
        lastRunResult = .succeeded
        failure = nil
      } else {
        lastRunResult = .failed
        if outcome.refusal == .secureChannelTimedOut {
          consecutiveSecureChannelStalls += 1
        } else {
          consecutiveSecureChannelStalls = 0
        }
        if isRecoveryModeNext {
          failure = String(
            localized: """
              Card security delay detected. Try again and hold the card \
              firmly against the phone while the countdown finishes.
              """)
        } else {
          failure = outcome.summary
        }
      }
      refresh()
      isRunning = false
    }

    /// Simulates only card/device effects; callers still use
    /// ``prime(cardAccessNumber:)``.
    ///
    /// A hold proves the access number over PACE before anything else,
    /// so the virtual run connects with the entered digits first and
    /// only registers once the card has accepted them.
    private func primeVirtualCard(cardAccessNumber: String) async {
      isRunning = true
      lastRunResult = .notRun
      failure = nil
      refusal = nil
      defer { isRunning = false }
      guard await connectVirtualCard(cardAccessNumber: cardAccessNumber) else { return }
      guard routeVirtualActivation() else { return }
      await registerVirtualCard()
    }

    /// Proves the entered digits against the virtual card.
    ///
    /// Mirrors the PACE step of a hold. False when the run ends here.
    private func connectVirtualCard(cardAccessNumber: String) async -> Bool {
      switch await DemoMode.shared.connectionSnapshot(cardAccessNumber: cardAccessNumber) {
      case .connected:
        return true

      case .wrongCardAccessNumber:
        lastRunResult = .failed
        refusal = .wrongCardAccessNumber
        failure = String(localized: "The Card Access Number (CAN) is incorrect.")
        return false

      case .failed:
        lastRunResult = .failed
        failure = String(localized: "The identity card could not be read. Try again.")
        return false
      }
    }

    /// Routes a factory card to activation.
    ///
    /// Sends no attempt on credentials the card was never given.
    /// False when the run ends here.
    private func routeVirtualActivation() -> Bool {
      guard DemoMode.shared.activationNeeds.any else { return true }
      lastRunResult = .failed
      refusal = .activationRequired(
        scheme: DemoMode.shared.activationScheme,
        needs: DemoMode.shared.activationNeeds)
      failure = String(localized: "Activate this card first, then try setup again.")
      return false
    }

    private func registerVirtualCard() async {
      switch await DemoMode.shared.register() {
      case .success:
        lastRunResult = .succeeded

      case let result:
        failVirtualRegistration(result)
      }
    }

    private func failVirtualRegistration(_ result: VirtualIDCard.RegistrationResult) {
      lastRunResult = .failed
      switch result {
      case .success:
        return

      case .certificateUnavailable:
        failure = String(localized: "The card certificate could not be read.")

      case .tokenPublicationFailed:
        failure = String(localized: "Safari setup did not finish. Try again.")

      case .transportFailure:
        failure = String(localized: "The identity card could not be read. Try again.")
      }
    }
  }

#endif
