// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation
  import Security

  /// The card I/O of a first prime: PACE and the reads, inside the one
  /// field's exclusive card session.
  extension CardPriming {
    /// What the one field reads off a card this device has never primed.
    internal struct Payload: Sendable {
      /// Public CTK identity name derived from the printed card serial.
      internal let instance: CardInstanceIdentifier

      /// Authentication certificate DER.
      internal let certificate: Data

      /// Issuing certificate DER when this build or the card supplied it.
      internal let issuer: Data?

      /// Full PKCS#15 serial retained for exact reconstruction.
      internal let tokenSerial: String

      /// Proof that the live card did not report a factory activation state.
      internal let activationCheck: PrimedIdentity.ActivationCheck

      /// The credential counters read in this same hold.
      ///
      /// Read here because the recovery route decided right after this
      /// hold is what consumes them; nothing stores them as a lasting
      /// claim about the card.
      internal let credentialReport: CredentialProbeReport?

      /// Signature certificate DER, when present on the card.
      internal let signatureCertificate: Data?
    }

    /// Reads everything the later signature must not have to read.
    ///
    /// Runs on the card queue, inside the card's exclusive session.
    internal static func read(
      from sheet: PrimingSheetReporter,
      accessNumber: CardAccessNumber,
      isRecovery: Bool,
      progress: Progress,
      step: StepReport
    ) throws -> Payload {
      let waitBudget: SmartCardChannel.ResponseWait = isRecovery ? .nearFieldRecovery : .nearField
      return try sheet.session.withCardSession(waits: waitBudget) { channel in
        progress(String(localized: "Opening a connection to the card."))
        let keys: PaceSessionKeys
        do {
          keys = try Self.establishPace(
            channel: channel,
            accessNumber: accessNumber,
            sheet: sheet,
            isRecovery: isRecovery)
        } catch {
          step(.secureChannel, .failed)
          throw error
        }
        step(.secureChannel, .done)
        return try Self.readSecuredPayload(
          channel: channel,
          keys: keys,
          progress: progress,
          step: step)
      }
    }

    /// Runs PACE against the card, managing recovery feedback and error translation.
    private static func establishPace(
      channel: SmartCardChannel,
      accessNumber: CardAccessNumber,
      sheet: PrimingSheetReporter,
      isRecovery: Bool
    ) throws -> PaceSessionKeys {
      // PACE runs from the main file. The card was discovered by
      // selecting the eMRTD application, and MSE:Set AT from an applet
      // context is answered 6985, so the main file is made current on
      // the plain channel before the first PACE command.
      //
      // Best effort on purpose: card generations differ in which SELECT
      // variant they acknowledge, and one that refuses both may still be
      // at the main file. PACE itself is the authoritative check --
      // its first command is the one that has to be accepted -- so a
      // refused reposition is not turned into a failure here.
      try? CardOperations(channel: channel).selectMainFile()
      if isRecovery {
        sheet.startRecovery()
      }
      defer {
        sheet.stopRecovery()
      }
      do {
        return try PaceEstablishment(channel: channel).establish(with: accessNumber)
      } catch SmartCardChannel.TransportError.responseTimedOut {
        throw Failure.secureChannelTimedOut
      } catch PaceEstablishment.Failure.authenticationTokenMismatch,
        PaceEstablishment.Failure.cardRejected(.authenticationFailed)
      {
        // PACE is the access number's proof: the session keys derive
        // from it, so a card that will not agree is a card these
        // digits do not describe. A FINEID card may answer with 6300.
        throw Failure.wrongCardAccessNumber
      }
    }

    /// Reads identity certificates and counters behind the established secure channel.
    private static func readSecuredPayload(
      channel: SmartCardChannel,
      keys: PaceSessionKeys,
      progress: Progress,
      step: StepReport
    ) throws -> Payload {
      step(.certificate, .running)
      progress(String(localized: "Connection opened."))
      let operations = CardOperations(
        channel: SecureMessagingChannel(wrapping: channel, sessionKeys: keys))
      progress(String(localized: "Reading the certificate from the card."))
      do {
        let payload = try Self.readIdentity(operations: operations)
        step(.certificate, .done)
        progress(String(localized: "Card identity read."))
        return payload
      } catch {
        step(.certificate, .failed)
        throw error
      }
    }

    /// The reads behind the secure channel, validated into a payload.
    ///
    /// PIN1 is not sent. The certificate is public and the secure channel
    /// is the only thing it needs, so setup asks the card for nothing it
    /// will not use. The counters are read because the route chosen
    /// immediately after this hold depends on them.
    private static func readIdentity(
      operations: CardOperations
    ) throws -> Payload {
      let certificate = try operations.readCertificate(.authentication)
      let activationCheck = try Self.activationCheck(
        certificate: certificate,
        operations: operations
      )
      let credentialReport = try? operations.probeCredentials()
      let serial = try operations.readTokenSerial()
      guard let instance = CardInstanceIdentifier(tokenSerial: serial) else {
        throw Failure.unidentifiedCard
      }
      guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
        throw Failure.certificateUnreadable
      }
      var issuer = TrustRootsCache.shared.der(matching: certificate)
      if issuer == nil {
        if let cardIssuer = try? operations.readCertificate(.issuing) {
          TrustRootsCache.shared.register(cardIssuer)
          issuer = cardIssuer
        }
      }
      if TrustRootsCache.shared.rootCertificate == nil,
        let cardRoot = try? operations.readCertificate(.root)
      {
        TrustRootsCache.shared.registerRoot(cardRoot)
      }
      let signatureCertificate =
        (try? operations.readCertificate(.qualifiedSignature))
        ?? (try? operations.readCertificate(.secondQualifiedSignature))
      return Payload(
        instance: instance,
        certificate: certificate,
        issuer: issuer,
        tokenSerial: serial.value,
        activationCheck: activationCheck,
        credentialReport: credentialReport,
        signatureCertificate: signatureCertificate)
    }

    /// Accepts only a card with no known factory activation state.
    ///
    /// Unknown schemes retain their existing issuer-managed path. The reads
    /// used for known citizen cards do not change credential counters.
    private static func activationCheck(
      certificate: Data,
      operations: CardOperations
    ) throws -> PrimedIdentity.ActivationCheck {
      guard
        let scheme = ActivationScheme.classify(
          authenticationCertificateDER: certificate)
      else {
        return .passed
      }
      let needs = operations.activationNeeds(scheme: scheme)
      guard !needs.any else {
        throw Failure.activationRequired(scheme: scheme, needs: needs)
      }
      return .passed
    }

    /// Runs one blocking card exchange off the cooperative pool.
    internal static func onCardQueue<Value: Sendable>(
      _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
      try await withCheckedThrowingContinuation { continuation in
        Self.cardQueue.async {
          continuation.resume(with: Result { try body() })
        }
      }
    }
  }

#endif
