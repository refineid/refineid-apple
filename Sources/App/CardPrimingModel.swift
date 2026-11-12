// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import SwiftUI

  /// What the Safari setup action needs, and the one thing it can do.
  ///
  /// The entered credential stays in the running operation across NFC fields.
  /// Apple's NFC sheet reports progress; only a sanitized failure is published.
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

    /// The credential kind selected for the last setup attempt.
    @Published internal private(set) var cardKind: ContactlessCardKind?

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

    /// Primes the card on the antenna from what the setup entry holds.
    ///
    /// The selected kind binds the entry to CAN or PIN 1. A personal
    /// card's setup sends no PIN: PIN 1 is asked for when it first signs
    /// (RAPP v26.11.8 §11 item 2).
    internal func prime(entry: CardPriming.SetupEntry) async {
      guard !isRunning else { return }
      cardKind = entry.kind
      if DemoMode.shared.isActive {
        guard let proven = entry.personalAccessNumber() else {
          failVirtualRegistration(.transportFailure(.connectionLost))
          #if DEBUG
            DevErrorLog.report("demonstration setup refused: card mode unsupported", source: .app)
          #endif
          return
        }
        await primeVirtualCard(cardAccessNumber: proven.digits)
        return
      }
      refresh()
      guard allowsNearField else { return }
      isRunning = true
      lastRunResult = .notRun
      failure = nil
      refusal = nil
      credentialReport = nil
      // The meter on the system NFC sheet carries progress; the holder
      // is looking at the card, not at this screen.
      let outcome = await CardSetupReadLoop.run(
        attempt: {
          let outcome = await CardPriming.prime(entry: entry, isRecovery: self.isRecoveryModeNext)
          if outcome.refusal == .secureChannelTimedOut {
            self.consecutiveSecureChannelStalls += 1
          } else {
            self.consecutiveSecureChannelStalls = 0
          }
          return outcome
        },
        shouldRetry: { outcome in
          entry.kind == .personal && outcome.retryable && !outcome.cancelled
        },
        pause: { try await Task.sleep(for: CardSetupReadLoop.retryInterval) })
      finishPrime(outcome)
      refresh()
      isRunning = false
    }

    /// Publishes only the final result of the operation across all its fields.
    private func finishPrime(_ outcome: CardPriming.Outcome?) {
      guard let outcome else {
        lastRunResult = .notRun
        return
      }
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
        activation: DemoMode.shared.activation,
        needs: DemoMode.shared.activationNeeds,
        pinLengths: DemoMode.pinLengths)
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
