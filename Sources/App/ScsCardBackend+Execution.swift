// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import Foundation
  import Security

  extension ScsCardBackend {
    private struct PreparedCeremony {
      let serial: ChipSerial
      let request: ScsSignRequest
      let role: CredentialRole
      let signerName: String?
      let digest: Data
      let algorithm: SigningAlgorithm
      let expectedSignatureLength: ExpectedResponseLength?
    }

    private static func contextRefusal(
      _ operations: CardOperations,
      purpose: ScsSignPurpose
    ) -> ScsBackendFailure? {
      guard (try? operations.resolveCredentialReferences()) == .organization else {
        return nil
      }
      guard OrganizationCardSupport.isEnabled else {
        return .signingUnavailable("organization card not supported in this build")
      }
      guard purpose == .qualified else {
        return nil
      }
      do {
        try operations.selectEsignDirectory()
        return nil
      } catch {
        ScsLog.error("backend: signature directory unavailable")
        return .signingUnavailable("signature directory unavailable")
      }
    }

    private static func signerSummary(of certificate: SecCertificate) -> String? {
      let summary = SecCertificateCopySubjectSummary(certificate) as String?
      return ScsOriginPolicy.sanitizedSignerName(summary)
    }

    internal func performSign(
      _ operations: CardOperations,
      request: ScsSignRequest,
      digest: Data,
      cancellation: ScsPromptCancellationToken
    ) -> Result<Data, ScsBackendFailure> {
      let purpose = request.purpose
      guard
        let serial = try? operations.readChipSerial(),
        let leaf = resolveSessionLeaf(operations, purpose: purpose),
        let cert = SecCertificateCreateWithData(nil, leaf as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: cert)
      else {
        return .failure(.signingUnavailable("card certificate unavailable"))
      }
      if let refused = Self.contextRefusal(operations, purpose: purpose) {
        return .failure(refused)
      }
      let role: CredentialRole = purpose == .authentication ? .pin1 : .pin2
      guard
        let probe = try? operations.probeRetryCounter(role: role),
        RetryFloor.evaluate(probeOutcome: probe) == .proceed
      else {
        return .failure(.credentialRefused("credential retry state refuses the sign"))
      }
      if case .throttled(let reason) = rateLimiter.checkAndRecordPrompt(
        origin: request.origin, at: Date())
      {
        return .failure(.policyRefused(reason))
      }
      let scheme: SigningScheme =
        switch profile {
        case .ecdsaP256, .ecdsaP384:
          .ecdsa
        case .rsa2048, .rsa3072:
          .rsaPkcs1
        }
      let ceremony = PreparedCeremony(
        serial: serial,
        request: request,
        role: role,
        signerName: Self.signerSummary(of: cert),
        digest: digest,
        algorithm: SigningAlgorithm(hash: request.hash, scheme: scheme),
        expectedSignatureLength: profile.expectedSignatureLength
      )
      return verifyAndSign(operations, ceremony: ceremony, cancellation: cancellation)
    }

    internal func currentLeaf(for purpose: ScsSignPurpose) -> Data? {
      let resolved = withCard(timeoutSeconds: Self.readTimeoutSeconds) { [self] operations in
        resolveSessionLeaf(operations, purpose: purpose)
      }
      if resolved == nil {
        leafCache.withLock { $0.invalidate() }
      }
      return resolved
    }

    internal func resolveSessionLeaf(
      _ operations: CardOperations,
      purpose: ScsSignPurpose
    ) -> Data? {
      guard let serial = try? operations.readChipSerial() else {
        leafCache.withLock { $0.invalidate() }
        return nil
      }
      if let cached = leafCache.withLock({ $0.cachedLeaf(for: purpose, serial: serial) }) {
        return cached
      }
      let slot: CertificateSlot =
        purpose == .authentication ? .authentication : .qualifiedSignature
      guard let fresh = try? operations.readCertificate(slot) else {
        return nil
      }
      leafCache.withLock { $0.store(leaf: fresh, for: purpose, serial: serial) }
      return fresh
    }

    private func verifyAndSign(
      _ operations: CardOperations,
      ceremony: PreparedCeremony,
      cancellation: ScsPromptCancellationToken
    ) -> Result<Data, ScsBackendFailure> {
      let context = ScsPinPrompt.Context(
        role: ceremony.role,
        origin: ceremony.request.origin,
        purpose: ceremony.request.purpose,
        signerName: ceremony.signerName,
        sha256Hex: ceremony.request.sha256Hex
      )
      let entered = ScsPinPrompt.request(context: context, cancellation: cancellation)
      guard
        let currentSerial = try? operations.readChipSerial(),
        currentSerial == ceremony.serial
      else {
        rateLimiter.recordRefusal(origin: ceremony.request.origin, at: Date())
        leafCache.withLock { $0.invalidate() }
        return .failure(.credentialRefused("card was changed or removed during prompt"))
      }
      do {
        switch consume entered {
        case .pin1(let pin):
          try operations.verifyPin1(pin.consumeForSingleTransmission())
          publishHolderNotice(nil)
          return .success(
            try operations.computeAuthenticationSignature(
              overDigest: ceremony.digest,
              algorithm: ceremony.algorithm,
              expectedSignatureLength: ceremony.expectedSignatureLength
            )
          )

        case .pin2(let pin):
          try operations.verifyPin2(pin.consumeForSingleTransmission())
          publishHolderNotice(nil)
          return .success(
            try operations.computeQualifiedSignature(
              overDigest: ceremony.digest,
              algorithm: ceremony.algorithm,
              expectedSignatureLength: ceremony.expectedSignatureLength
            )
          )

        case .invalidFormat:
          rateLimiter.recordRefusal(origin: ceremony.request.origin, at: Date())
          return .failure(.credentialRefused("PIN format invalid"))

        case .cancelled:
          rateLimiter.recordRefusal(origin: ceremony.request.origin, at: Date())
          return .failure(.credentialRefused("PIN entry was cancelled"))

        case .busy:
          return .failure(.policyRefused("another signature prompt is already active"))
        }
      } catch {
        return .failure(mapCardError(error, origin: ceremony.request.origin))
      }
    }

    private func mapCardError(_ error: any Error, origin: String?) -> ScsBackendFailure {
      switch error {
      case CardOperationError.pinRejected(let remaining):
        rateLimiter.recordRefusal(origin: origin, at: Date())
        let count = Int64(remaining.attemptsRemaining)
        publishHolderNotice(
          String(localized: "PIN rejected (\(count) attempts remaining)"))
        return .credentialRefused("PIN rejected")

      case CardOperationError.pinBlocked:
        publishHolderNotice(String(localized: "PIN is blocked on the card"))
        return .credentialRefused("credential blocked")

      case CardOperationError.credentialInvalidated:
        return .credentialRefused("credential invalidated")

      default:
        ScsLog.error("backend: sign chain failed")
        return .signingUnavailable("sign chain failed")
      }
    }

    private func publishHolderNotice(_ message: String?) {
      Task { @MainActor in
        ScsService.shared.setHolderNotice(message)
      }
    }
  }
#endif
