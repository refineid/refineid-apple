// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// What the dispatcher asks of the card, and what it answers without one.
  extension RappPhoneProxyDispatcher {
    internal func executeSafeRead(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      switch operation.kind {
      case .inspectCard:
        await inspect(operationID: operationID, coordinator: coordinator)

      case .readIdentity:
        await readIdentity(operationID: operationID, coordinator: coordinator)

      case .readAuthenticationCertificate, .readSignatureCertificate,
        .readRootCertificate, .readIntermediateCertificate:
        await fulfillCertificateRead(
          operationID: operationID,
          kind: operation.kind,
          coordinator: coordinator)

      case .browserAuthenticate, .signDocument:
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

      case .readIntermediateCertificate:
        if let cert = TrustRootsCache.shared.intermediateCertificate
          ?? PrimeStore.storedIdentities().first?.issuerDER
        {
          TrustRootsCache.shared.register(cert)
          return cert
        }
        return nil

      case .readRootCertificate:
        return TrustRootsCache.shared.rootCertificate

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

      case .readIntermediateCertificate:
        let outcome = await RappCardExecutor.readCertificate(
          cardAccessNumber: accessNumber,
          slot: .issuing)
        if case .result(let der) = outcome {
          TrustRootsCache.shared.register(der)
        }
        return outcome

      case .readRootCertificate:
        let outcome = await RappCardExecutor.readCertificate(
          cardAccessNumber: accessNumber,
          slot: .root)
        if case .result(let der) = outcome {
          TrustRootsCache.shared.registerRoot(der)
        }
        return outcome

      default:
        return nil
      }
    }

    private func fulfillCertificateRead(
      operationID: Data,
      kind: RappOperationDriver.OperationKind,
      coordinator: RappConnectionCoordinator
    ) async {
      let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
      let cardSerial = Self.storedTokenSerial()

      if !isReader, let cachedDER = cachedCertificate(for: kind) {
        await completeCertificate(
          operationID: operationID,
          der: cachedDER,
          cardSerial: cardSerial,
          coordinator: coordinator)
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
      operationID: Data,
      der: Data,
      cardSerial: String?,
      coordinator: RappConnectionCoordinator
    ) async {
      do {
        try await coordinator.completeCertificate(
          operationID: operationID,
          der: der,
          cardSerial: cardSerial)
      } catch {
        await coordinator.close()
      }
    }

    internal func executeCardCommand(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard
        let keyProfile = operation.keyProfile,
        let algorithm = operation.algorithm
      else {
        #if DEBUG
          HolderTrace.say(
            "card command refused: profile \(operation.keyProfile != nil), "
              + "algorithm \(operation.algorithm != nil)"
          )
        #endif
        await invalid(operationID, coordinator: coordinator)
        return
      }
      let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
      let accessNumber = resolvedCardAccessNumber(isReader: isReader)
      #if DEBUG
        HolderTrace.say("card read starting: \(operation.kind), isReader: \(isReader)")
      #endif
      guard
        let outcome = await signingOutcome(
          operationID: operationID,
          operation: operation,
          accessNumber: accessNumber,
          keyProfile: keyProfile,
          algorithm: algorithm
        )
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
      await finishSignature(
        outcome,
        operationID: operationID,
        coordinator: coordinator
      )
    }

    /// What the card answered, or nothing when this operation is not one the
    /// card signs for.
    ///
    /// A document signature consumes the PIN2 held for the operation, so it
    /// is taken here and not before: an operation that never reaches the card
    /// leaves the PIN2 where it was.
    private func signingOutcome(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      accessNumber: String?,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm
    ) async -> RappCardExecutor.Outcome? {
      switch operation.kind {
      case .browserAuthenticate:
        let pin1 = pin1ByOperation.removeValue(forKey: operationID)
        return await RappCardExecutor.browserAuthentication(
          cardAccessNumber: accessNumber,
          pin1: pin1,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: operation.digest
        )

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
        .readSignatureCertificate, .readRootCertificate, .readIntermediateCertificate:
        return nil
      }
    }

    private func inspect(
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      let accessNumber = resolvedCardAccessNumber(isReader: false)
      switch await CardMaintenance.connectionSnapshot(
        cardAccessNumber: accessNumber
      ) {
      case .connected(let snapshot):
        guard let activation = snapshot.activationNeeds else {
          await invalid(operationID, coordinator: coordinator)
          return
        }
        do {
          try await coordinator.completeInspection(
            operationID: operationID,
            inspection: RappOperationDriver.Inspection(
              pin1Factory: activation.pin1,
              pin2Factory: activation.pin2,
              pin1Attempts: attempts(snapshot.report?.pin1),
              pin2Attempts: attempts(snapshot.report?.pin2),
              pukAttempts: attempts(snapshot.report?.puk),
              answerToReset: snapshot.answerToReset
            )
          )
        } catch {
          await coordinator.close()
        }

      case .wrongCardAccessNumber:
        CardCredentialStore.forgetAll()
        await requireExplicitReconnect()
        try? await coordinator.credentialRejected(operationID: operationID)

      case .failed:
        try? await coordinator.cardRemovedBeforeTransmit(operationID: operationID)
      }
    }

    private func readIdentity(
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      let accessNumber = resolvedCardAccessNumber(isReader: false)
      let outcome = await RappCardExecutor.readCertificate(
        cardAccessNumber: accessNumber,
        signatureCertificate: false
      )
      guard case .result(let der) = outcome,
        let facts = CertificateFacts(der: der),
        let name = DistinguishedName.personalName(inName: facts.subjectName)
          ?? DistinguishedName.commonName(inName: facts.subjectName)
      else {
        await finishRead(outcome, operationID: operationID, coordinator: coordinator)
        return
      }
      lastReadAuthCertDER = der
      guard
        let identity = RappOperationDriver.Identity(
          authenticationCertificate: der,
          holderName: name,
          cardID: DistinguishedName.identifier(inName: facts.subjectName) ?? "")
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
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
