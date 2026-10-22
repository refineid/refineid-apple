// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// What the dispatcher asks of the card, and what it answers without one.
  extension RappPhoneProxyDispatcher {
    internal func executeSafeRead(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      switch operation.kind {
      case .inspectCard:
        await inspect(operationID: operationID, coordinator: coordinator)

      case .readIdentity:
        await readIdentity(operationID: operationID, coordinator: coordinator)

      case .readAuthenticationCertificate, .readSignatureCertificate:
        await fulfillCertificateRead(
          operationID: operationID,
          kind: operation.kind,
          coordinator: coordinator)

      case .browserAuthenticate, .signDocument, .batchSignDocuments:
        await invalid(operationID, coordinator: coordinator)
      }
    }

    private func cachedCertificate(
      for kind: RappOperationDriver.OperationKind
    ) -> Data? {
      switch kind {
      case .readAuthenticationCertificate:
        return lastReadAuthCertDER ?? PrimeStore.storedIdentities().first?.certDER

      case .readSignatureCertificate:
        return PrimeStore.storedIdentities().first?.signatureCertDER

      default:
        return nil
      }
    }

    private func executeCardCertificateRead(
      accessNumber: String?,
      isReader: Bool,
      kind: RappOperationDriver.OperationKind
    ) async -> RappCardExecutor.Outcome? {
      switch kind {
      case .readAuthenticationCertificate:
        let outcome = await RappCardExecutor.readCertificate(
          cardAccessNumber: accessNumber,
          signatureCertificate: false)
        if case .result(let der) = outcome {
          lastReadAuthCertDER = der
        }
        return outcome

      case .readSignatureCertificate:
        let outcome = await RappCardExecutor.readCertificate(
          cardAccessNumber: accessNumber,
          signatureCertificate: true)
        if case .result(let der) = outcome, !isReader {
          PrimeStore.updateSignatureCertificate(der)
        }
        return outcome

      default:
        return nil
      }
    }

    private func fulfillCertificateRead(
      operationID: RappOperationIdentifier,
      kind: RappOperationDriver.OperationKind,
      coordinator: RappConnectionCoordinator
    ) async {
      let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }

      if !isReader, let cachedDER = cachedCertificate(for: kind) {
        await completeCertificate(
          operationID: operationID, der: cachedDER, coordinator: coordinator)
        return
      }

      let accessNumber = resolvedCardAccessNumber(isReader: isReader)
      guard
        let outcome = await executeCardCertificateRead(
          accessNumber: accessNumber,
          isReader: isReader,
          kind: kind)
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }

      #if DEBUG
        HolderTrace.say("fulfillCertificateRead outcome: \(outcome)")
      #endif
      await finishRead(outcome, operationID: operationID, coordinator: coordinator)
    }

    private func completeCertificate(
      operationID: RappOperationIdentifier,
      der: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      do {
        try await coordinator.completeCertificate(operationID: operationID, der: der)
      } catch {
        await coordinator.close()
      }
    }

    /// Runs the one approved card command; a PIN the card refused is asked
    /// for again on the phone while the retry floor allows (RAPP v26.10.22
    /// §10.2), and the requester learns only the outcome.
    internal func executeCardCommand(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      OperationPhaseTrace.begin()
      let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
      let accessNumber = resolvedCardAccessNumber(isReader: isReader)
      if operation.kind == .batchSignDocuments {
        await executeBatch(
          operationID: operationID, operation: operation, accessNumber: accessNumber,
          coordinator: coordinator)
        return
      }
      #if DEBUG
        HolderTrace.say("card read starting: \(operation.kind), isReader: \(isReader)")
      #endif
      while true {
        guard
          let outcome = await signingOutcome(
            operationID: operationID, operation: operation, accessNumber: accessNumber)
        else {
          #if DEBUG
            HolderTrace.say("signingOutcome returned nil")
          #endif
          await invalid(operationID, coordinator: coordinator)
          return
        }
        #if DEBUG
          HolderTrace.say("card read outcome: \(outcome)")
        #endif
        switch await askAgainAfterRefusedPin(
          outcome, operationID: operationID, operation: operation, coordinator: coordinator)
        {
        case .askedAgain:
          continue

        case .declined:
          return

        case .outcomeStands:
          await finishSignature(outcome, operationID: operationID, coordinator: coordinator)
          return
        }
      }
    }

    /// What the card answered, or nothing when this operation is not one the
    /// card signs for.
    ///
    /// A document signature consumes the PIN2 held for the operation, so it
    /// is taken here and not before: an operation that never reaches the card
    /// leaves the PIN2 where it was.
    private func signingOutcome(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      accessNumber: String?
    ) async -> RappCardExecutor.Outcome? {
      guard let keyProfile = operation.keyProfile, let algorithm = operation.algorithm else {
        return nil
      }
      switch operation.kind {
      case .browserAuthenticate:
        guard let pin1 = pin1ByOperation.removeValue(forKey: operationID) else { return nil }
        let outcome = await RappCardExecutor.browserAuthentication(
          cardAccessNumber: accessNumber,
          pin1: pin1,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )
        await settleHeldPin1(pin1, after: outcome)
        return outcome

      case .signDocument:
        guard let pin2 = pin2ByOperation.removeValue(forKey: operationID) else {
          return nil
        }
        return await RappCardExecutor.signDocument(
          cardAccessNumber: accessNumber,
          pin2: pin2,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )

      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate, .batchSignDocuments:
        return nil
      }
    }

    /// Holds a typed PIN 1 once the card accepted it, or when no card came
    /// to take it, and forgets a held one the counter no longer confirms
    /// (RAPP v26.10.22 §11 item 2).
    ///
    /// A PIN typed for a card that never arrived reached no card, so the
    /// retry that follows uses it instead of asking again; the counter is
    /// read before it is sent, and a card that refuses it ends it like any
    /// held PIN. A refusal is forgotten where it is answered; a transport
    /// failure keeps what is held, since the counter is read again before
    /// its next use.
    private func settleHeldPin1(
      _ pin1: RappCardExecutor.SigningPin,
      after outcome: RappCardExecutor.Outcome
    ) async {
      switch (pin1, outcome) {
      case (.enteredPin1(let digits), .result),
        (.enteredPin1(let digits), .refusedBeforeCredentialTransmit(.cardUnavailable)):
        await MainActor.run {
          guard let card = PhonePersistentTokenRelay.shared.servedCardFingerprint else { return }
          HeldPin1.shared.hold(digits, card: card)
        }

      case (.heldPin1, .refusedBeforeCredentialTransmit(.heldPin1Unconfirmed)):
        await MainActor.run { HeldPin1.shared.clear() }

      default:
        break
      }
    }

    private func inspect(
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      let accessNumber = resolvedCardAccessNumber(isReader: false)
      switch await CardMaintenance.connectionSnapshot(
        cardAccessNumber: accessNumber
      ) {
      case .connected(let snapshot):
        do {
          try await coordinator.completeInspection(
            operationID: operationID, answerToReset: snapshot.answerToReset)
        } catch {
          await coordinator.close()
        }

      case .wrongCardAccessNumber:
        CardCredentialStore.forgetCardAccessNumber()
        try? await coordinator.operationFailed(operationID: operationID)

      case .failed:
        try? await coordinator.cardError(operationID: operationID)
      }
    }

    /// The identity is read off the authentication certificate, which the
    /// phone already holds once the card has been read; only a phone that
    /// has never seen the card asks for it.
    private func readIdentity(
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      if let der = lastReadAuthCertDER ?? PrimeStore.storedIdentities().first?.certDER {
        await completeIdentity(der, operationID: operationID, coordinator: coordinator)
        return
      }
      let accessNumber = resolvedCardAccessNumber(isReader: false)
      let outcome = await RappCardExecutor.readCertificate(
        cardAccessNumber: accessNumber,
        signatureCertificate: false
      )
      guard case .result(let der) = outcome else {
        await finishRead(outcome, operationID: operationID, coordinator: coordinator)
        return
      }
      await completeIdentity(der, operationID: operationID, coordinator: coordinator)
    }

    private func completeIdentity(
      _ der: Data,
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let facts = CertificateFacts(der: der),
        let name = DistinguishedName.holderLine(inName: facts.subjectName),
        let identity = RappOperationDriver.Identity(
          authenticationCertificate: der,
          holderName: name,
          cardID: DistinguishedName.identifier(inName: facts.subjectName) ?? "")
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      lastReadAuthCertDER = der
      do {
        try await coordinator.completeIdentity(operationID: operationID, identity: identity)
      } catch {
        await coordinator.close()
      }
    }

    private func resolvedCardAccessNumber(isReader: Bool) -> String? {
      guard !isReader else { return nil }
      return CardCredentialStore.displayedCardAccessNumber()
        ?? PrimeStore.storedIdentities().first?.can
    }
  }
#endif
