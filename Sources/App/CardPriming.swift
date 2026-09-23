// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// The setup flow that teaches this iPhone the card, so later signing
  /// fields spend their time only on PACE, PIN1, and the signature.
  ///
  /// Priming uses ONE system NFC field: the app opens the CryptoTokenKit
  /// slot, and inside that single hold runs PACE, reads the public
  /// authentication metadata, stores it, and registers the resulting
  /// token. `ctkd` asks the token extension for a token the moment the
  /// card enters the slot -- while PACE is still running -- so the
  /// extension bridges the gap with a bounded wait for the prime this
  /// flow is about to write (`TokenDriver.awaitPrime`). A card this
  /// device has already primed skips the card I/O entirely and goes
  /// straight to registration, which is the fastest hold there is.
  ///
  /// Three rules shape this flow, each bought with a measured on-device
  /// failure:
  ///
  /// 1. On the system-driven path `ctkd` owns the slot and ends it about
  ///    two seconds after the mint. The token extension therefore takes
  ///    its card session during `createToken` and KEEPS it for the
  ///    signature; a fresh `beginSession` in the sign fails with TKError
  ///    -7. During THIS flow a registration mark, written before the
  ///    slot opens, tells the extension to publish metadata without
  ///    taking a session, so the app keeps the card to itself.
  /// 2. That held session is released only when the slot state is
  ///    genuinely `.missing` (``NearFieldCardSession/isMissing``).
  ///    Releasing on any other non-`validCard` state tore a signature
  ///    down part way through a read.
  /// 3. The signature reads NOTHING it could already know. Everything
  ///    read here is public and unchanging, so it is read once, here,
  ///    where the holder is deliberately holding the card still and the
  ///    field is the app's own rather than a rationed signing field.
  ///
  /// `registerSmartCard` is called while the card is LIVE in the slot.
  /// Registering after the card has left finds nothing to register.
  ///
  /// Provenance: `SafariIdentityPrime.primeAndRegisterWithOneSystemNFC`
  /// and `registerVisibleTokens` in the donor
  /// `platform/apple/RefineID/Local/SafariIdentityPrime+OneSystemNFC.swift`
  /// and `SafariIdentityPrime+LiveRegistration.swift`.
  internal enum CardPriming {
    /// Where a running prime reports what it is doing.
    ///
    /// Called from the card queue as well as the caller's context, so it
    /// must be safe to invoke from anywhere.
    internal typealias Progress = @Sendable (String) -> Void

    /// Reports which setup step a run has reached, and how it went.
    ///
    /// Separate from the text progress because the two answer different
    /// questions: the text says what is happening, the steps say how far
    /// the hold got and where it broke.
    internal typealias StepReport = @Sendable (CardPrimingStep, CardPrimingStep.State) -> Void

    /// What one priming run achieved.
    internal struct Outcome: Sendable {
      /// Whether the primed identity reached the prime store.
      internal let stored: Bool

      /// Whether the live card was registered for system logins.
      internal let registered: Bool

      /// One sentence for the holder, whatever happened.
      internal let summary: String

      /// Whether the holder closed the sheet themselves.
      ///
      /// Distinct from failure on purpose: someone who cancels knows
      /// what they did and should not be told off for it with an error
      /// tone.
      internal var cancelled: Bool = false

      /// What the card said, when it said something the caller can route on.
      internal var refusal: CardSetupRefusal?

      /// The credential counters this hold read, for the health display and
      /// the recovery route.
      internal var credentialReport: CredentialProbeReport?
    }

    /// Shown under Apple's own "Ready to Scan" title whenever the system
    /// later asks for this card.
    ///
    /// The title already says an action is wanted, so this only names the
    /// card.
    internal static let registrationPrompt = String(
      localized: "Present your identity card")

    /// How many times registration is attempted while the card is live.
    ///
    /// The attempts are immediate and back to back: they separate a
    /// transient miss, where one succeeds, from a deterministic
    /// precondition failure, where they all fail the same way. Waiting
    /// between them would only spend the hold.
    internal static let registrationAttemptLimit: Int = 3

    /// How many times the token watcher is asked whether `ctkd` has
    /// published the token for this card yet.
    internal static let tokenPollLimit: Int = 20

    /// Wait between two looks at the token watcher.
    internal static let tokenPollInterval: Duration = .milliseconds(100)

    /// The queue every blocking card exchange runs on.
    ///
    /// `SmartCardChannel` drives each APDU with a semaphore, so the wait
    /// must never land on the cooperative pool or the main thread.
    internal static let cardQueue = DispatchQueue(label: "fi.refineid.priming.card")

    /// What the system sheet says while the holder is finding the spot.
    ///
    /// One line, and only the part the holder cannot work out: where to
    /// put the card. Apple's own title above it already says a scan is
    /// wanted, and the meter and sound below say the hold is running, so
    /// a sentence telling them to keep holding is a third voice saying
    /// what two already said.
    ///
    /// Virtual card setup presents the same line, so a
    /// demonstration is told what a card read is told.
    internal static var holdMessage: String {
      String(localized: "Hold the card on the top back of the phone.")
    }

    /// Primes the card the holder is about to present.
    ///
    /// Never throws: a prime is a thing a person is doing, and every way
    /// it can fail is something they need to read rather than something a
    /// caller needs to catch.
    ///
    /// One hold does the whole setup: PACE proves the offered access
    /// number, the public certificate is read behind it, and the identity
    /// is stored and registered. Nothing is written to this device until
    /// that hold has succeeded.
    ///
    /// PIN1 is never sent to the card here. The certificate is public and
    /// needs only the secure channel, and whether the card accepts a PIN
    /// is true of the card at the instant it signs rather than of this
    /// setup -- so it is checked there, where the counter is read in the
    /// same session that consumes it.
    internal static func prime(
      cardAccessNumber: String,
      pin1: String?,
      progress: @escaping Progress,
      step: @escaping StepReport
    ) async -> Outcome {
      guard let accessNumber = CardAccessNumber(digits: cardAccessNumber) else {
        step(.found, .failed)
        return Self.failure(Failure.cardAccessNumberMissing)
      }
      if let pin1 {
        // Shape is the one thing about a PIN that is knowable without a
        // card, so it is the one thing checked before the slot opens.
        guard Pin1(digits: pin1) != nil else {
          step(.found, .failed)
          return Self.failure(Failure.pin1Malformed)
        }
      } else {
        guard OnDemandPinExperiment.isEnabled else {
          step(.found, .failed)
          return Self.failure(Failure.pin1Malformed)
        }
      }
      // Marked BEFORE the slot opens: `ctkd` asks the extension for a
      // token the moment the card arrives, and a mark written after that
      // would lose the race. The mark makes the extension publish
      // without taking a card session, leaving the card to this flow.
      guard PrimeStore.markRegistrationField() else {
        step(.found, .failed)
        return Self.failure(Failure.primeNotStored)
      }
      defer { PrimeStore.clearRegistrationField() }

      step(.found, .running)
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(message: Self.holdMessage)
      } catch {
        step(.found, .failed)
        return Self.failure(error)
      }
      defer { session.end() }
      // The meter lives on the sheet from here on: the card is against
      // the phone and Apple's panel is over the app, so this is the only
      // surface the holder can actually see.
      let sheet = PrimingSheetReporter(session: session)
      let report: StepReport = { reached, state in
        step(reached, state)
        sheet.report(reached, state)
      }
      report(.found, .done)
      progress(String(localized: "Card found. Keep holding."))

      // The sound belongs to the panel, and only to the panel. It starts
      // here because the card is now live in a slot the holder is being
      // shown, and it is answered below while that panel is still up: a
      // tone that outlives the sheet is a tone about nothing.
      await CardPrimingFeedback.startWorking()
      let outcome = await Self.hold(
        sheet: sheet,
        accessNumber: ProvenAccessNumber(value: accessNumber, digits: cardAccessNumber),
        progress: progress,
        step: report)
      await CardPrimingFeedback.report(succeeded: outcome.stored && outcome.registered)
      return outcome
    }

    /// Everything done with the card live and the panel up.
    ///
    /// Split from `prime` so the sound has exactly one place to start
    /// and one place to be answered, both inside the panel's lifetime.
    private static func hold(
      sheet: PrimingSheetReporter,
      accessNumber: ProvenAccessNumber,
      progress: @escaping Progress,
      step: @escaping StepReport
    ) async -> Outcome {
      guard
        let lookup = PrimeLookupIdentifier(answerToReset: sheet.session.answerToReset)
      else {
        step(.secureChannel, .failed)
        sheet.fail(Self.sheetMessage(for: Failure.unidentifiedCard))
        return Self.failure(Failure.unidentifiedCard)
      }

      return await Self.readStoreRegister(
        sheet: sheet,
        lookup: lookup,
        accessNumber: accessNumber,
        progress: progress,
        step: step)
    }

    /// An Outcome that achieved nothing, explained.
    private static func failure(_ error: any Error) -> Outcome {
      Outcome(
        stored: false,
        registered: false,
        summary: Self.summary(for: error),
        cancelled: (error as? NearFieldCardSession.Failure) == .dismissed,
        refusal: Self.refusal(for: error))
    }

    /// The routable part of a failure, when the card named one.
    private static func refusal(for error: any Error) -> CardSetupRefusal? {
      switch error as? Failure {
      case .wrongCardAccessNumber:
        .wrongCardAccessNumber

      case .activationRequired(let scheme, let needs):
        .activationRequired(scheme: scheme, needs: needs)

      default:
        nil
      }
    }

    /// Reads the card in this same field, stores the prime, registers.
    private static func readStoreRegister(
      sheet: PrimingSheetReporter,
      lookup: PrimeLookupIdentifier,
      accessNumber: ProvenAccessNumber,
      progress: @escaping Progress,
      step: @escaping StepReport
    ) async -> Outcome {
      step(.secureChannel, .running)
      let payload: Payload
      do {
        payload = try await Self.onCardQueue {
          try Self.read(
            from: sheet,
            accessNumber: accessNumber.value,
            progress: progress,
            step: step)
        }
      } catch {
        // The sheet is the only thing a holder can see while holding, so
        // it carries the detail rather than a shrug. Nothing here names
        // a PIN, CAN or the holder.
        sheet.fail(Self.sheetMessage(for: error))
        return Self.failure(error)
      }

      // The read above opened the secure channel with this number, so it
      // is proven, and the record built below is stored under it.
      guard CardCredentialStore.save(cardAccessNumber: accessNumber.digits) == errSecSuccess
      else {
        step(.stored, .failed)
        sheet.fail(String(localized: "Could not save card details"))
        return Self.failure(Failure.primeNotStored)
      }

      // The exact record is what the extension's mint -- already waiting
      // in this field -- publishes from, and what every later signing
      // field reads. The registration mark written before the slot
      // opened keeps that waiting mint from taking the card session
      // away from this flow.
      step(.stored, .running)
      guard
        let identity = CardCredentialStore.primedIdentity(
          certificate: payload.certificate,
          issuer: payload.issuer,
          tokenSerial: payload.tokenSerial,
          activationCheck: payload.activationCheck,
          signatureCertificate: payload.signatureCertificate),
        PrimeStore.store(identity, forLookup: lookup)
      else {
        step(.stored, .failed)
        sheet.fail(String(localized: "Could not save card details"))
        return Self.failure(Failure.primeNotStored)
      }
      step(.stored, .done)
      progress(String(localized: "Card details stored on this iPhone."))

      return await Self.finish(
        payload: payload,
        sheet: sheet,
        progress: progress,
        step: step)
    }

    /// Registers the live card and reports how the hold ended.
    ///
    /// Split from `prime` only so each stays readable; it must still run
    /// with the card in the slot, which is why it takes the live session
    /// rather than being called after the hold.
    private static func finish(
      payload: Payload,
      sheet: PrimingSheetReporter,
      progress: @escaping Progress,
      step: StepReport
    ) async -> Outcome {
      step(.registered, .running)
      let registered = await Self.register(
        instance: payload.instance,
        session: sheet.session,
        progress: progress)
      step(.registered, registered ? .done : .failed)
      if !registered {
        sheet.fail(String(localized: "Safari setup did not finish"))
      }
      return Outcome(
        stored: true,
        registered: registered,
        summary: registered
          ? String(localized: "The system is ready")
          : String(
            localized: """
              The card details were stored, but Safari setup did not \
              finish. Try priming the card again.
              """),
        credentialReport: payload.credentialReport)
    }
  }

#endif
