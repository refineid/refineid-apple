// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Security

  /// Executes Web eID card inspection, authentication, certificate retrieval,
  /// and qualified signing inside exclusive reader sessions.
  ///
  /// PINs are never cached across Web eID operations and every raw card
  /// signature is verified locally against the card's public key before
  /// leaving the application.
  internal enum WebEidCardRunner {
    // MARK: Nested Types

    internal struct ResolvedCertificate {
      internal let der: Data
      internal let publicKey: SecKey
      internal let profile: CardKeyProfile
      internal let holderName: String
    }

    // MARK: Static Functions

    /// Reads the active reader card without presenting any PIN so the prompt
    /// can display the holder's identity and preflight retry health.
    internal static func inspectCard(
      for command: WebEidCommand
    ) async -> Result<WebEidCardPreview, WebEidCardFailure> {
      let answer: Result<WebEidCardPreview, WebEidCardFailure>? =
        await CardMaintenance.onReader { operations in
          inspectInSession(operations, command: command)
        }
      return answer ?? .failure(.noCard)
    }

    internal static func checkRetryFloor(
      _ operations: CardOperations,
      role: CredentialRole
    ) -> WebEidCardFailure? {
      guard let probe = try? operations.probeRetryCounter(role: role) else {
        return .retryFloorRefused(verdict: .refuseUnreadable, remaining: nil)
      }
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      guard verdict == .proceed else {
        let remaining: RetryCount? =
          if case .remaining(let count) = probe { count } else { nil }
        return .retryFloorRefused(verdict: verdict, remaining: remaining)
      }
      return nil
    }

    internal static func readResolvedCertificate(
      _ operations: CardOperations,
      signing: Bool
    ) -> ResolvedCertificate? {
      let der: Data? =
        if signing {
          (try? operations.readCertificate(.qualifiedSignature))
            ?? (try? operations.readCertificate(.secondQualifiedSignature))
        } else {
          try? operations.readCertificate(.authentication)
        }
      guard
        let der,
        let certificate = SecCertificateCreateWithData(nil, der as CFData),
        let publicKey = SecCertificateCopyKey(certificate),
        let profile = CardKeyProfile.resolve(fromPublicKey: publicKey)
      else {
        return nil
      }
      let holderName =
        DistinguishedName.holderLine(fromCertificate: der)
        ?? (SecCertificateCopySubjectSummary(certificate) as String?)
        ?? ""
      return ResolvedCertificate(
        der: der,
        publicKey: publicKey,
        profile: profile,
        holderName: holderName
      )
    }

    internal static func mapCardError(
      _ error: Error,
      operations: CardOperations
    ) -> WebEidCardFailure {
      switch error {
      case CardOperationError.pinRejected(let remaining):
        return .pinRejected(remaining: remaining)

      case CardOperationError.pinBlocked:
        return .pinBlocked

      case CardOperationError.credentialInvalidated:
        return .invalidated

      case CardOperationError.pinLengthRefused:
        return .invalidPinEntry

      case CardOperationError.signRejected(.conditionsNotSatisfied)
      where operations.resolvedNumbering == .estonian2025
        && (try? operations.requiresPin2ChangeBeforeSigning()) == true:
        Task { @MainActor in
          CredentialRetryHealth.shared.markPin2RequiresChangeBeforeSigning()
        }
        return .pin2RequiresChangeBeforeSigning

      default:
        return .cardError
      }
    }

    internal static func currentAppVersion() -> String {
      let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      return version.flatMap { $0.isEmpty ? nil : $0 } ?? WebEidValues.compatibleProtocolVersion
    }

    private static func inspectInSession(
      _ operations: CardOperations,
      command: WebEidCommand
    ) -> Result<WebEidCardPreview, WebEidCardFailure> {
      guard let serial = try? operations.readChipSerial() else {
        return .failure(.cardError)
      }
      let usesSigningCertificate = isSigningCommand(command)
      guard let resolved = readResolvedCertificate(operations, signing: usesSigningCertificate)
      else {
        return .failure(.certificateUnavailable)
      }
      let numbering =
        (try? operations.resolveCredentialReferences()) ?? operations.resolvedNumbering ?? .citizen
      let pinLengths =
        (try? operations.readCardPinLengths()) ?? CardPinLengths.notListed(numbering: numbering)
      let role = credentialRole(for: command)
      let probe = role.flatMap { try? operations.probeRetryCounter(role: $0) }
      let verdict =
        probe.map(RetryFloor.evaluate(probeOutcome:))
        ?? (role == nil ? .proceed : .refuseUnreadable)
      let requiresPin2Change: Bool
      if usesSigningCertificate {
        do {
          requiresPin2Change = try operations.requiresPin2ChangeBeforeSigning()
        } catch {
          return .failure(.cardError)
        }
      } else {
        requiresPin2Change = false
      }
      if requiresPin2Change {
        Task { @MainActor in
          CredentialRetryHealth.shared.markPin2RequiresChangeBeforeSigning()
        }
      }
      let matchesExpected = expectedCertificateMatches(resolved.der, command: command)
      return .success(
        WebEidCardPreview(
          holderName: resolved.holderName,
          certificateDER: resolved.der,
          chipSerial: serial,
          profile: resolved.profile,
          pinLengths: pinLengths,
          pin2RequiresChangeBeforeSigning: requiresPin2Change,
          retryProbe: probe,
          retryFloorVerdict: verdict,
          certificateMatchesExpected: matchesExpected
        )
      )
    }

    private static func isSigningCommand(_ command: WebEidCommand) -> Bool {
      switch command {
      case .getSigningCertificate, .sign:
        true

      case .status, .authenticate:
        false
      }
    }

    private static func credentialRole(for command: WebEidCommand) -> CredentialRole? {
      switch command {
      case .authenticate:
        .pin1

      case .sign:
        .pin2

      case .status, .getSigningCertificate:
        nil
      }
    }

    private static func expectedCertificateMatches(
      _ liveDER: Data,
      command: WebEidCommand
    ) -> Bool {
      if case .sign(let request) = command {
        return liveDER == request.certificateDER
      }
      return true
    }
  }

#endif
