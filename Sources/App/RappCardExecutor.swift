// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import Security

  internal typealias RappNfcCardExecutor = RappCardExecutor

  /// The physical-card boundary for the iPhone RAPP proxy.
  ///
  /// Each call connects through an attached card reader or an NFC hold. Safe reads
  /// never accept credentials. Consequential calls validate the live certificate
  /// and retry state before constructing a one-shot PIN transmission. Once that
  /// transmission begins, every unclassified transport/card failure is completion-ambiguous
  /// rather than permission to retry.
  internal enum RappCardExecutor {
    internal enum Refusal: Sendable, Equatable {
      case cardUnavailable
      case certificateUnavailable
      case credentialBlocked(CredentialRole)
      case credentialInvalidated(CredentialRole)
      case invalidCredential(CredentialRole)
      case keyOrAlgorithmMismatch
      case retryFloor(CredentialRole, RetryFloorVerdict)
    }

    internal enum Rejection: Sendable, Equatable {
      case cardAccessNumber
      case credential(CredentialRole, remaining: RetryCount?)
    }

    internal enum Outcome: Sendable, Equatable {
      case completionAmbiguous
      case refusedBeforeCredentialTransmit(Refusal)
      case rejected(Rejection)
      case result(Data)
    }

    internal struct Identity {
      internal let publicKey: SecKey
      internal let request: SignRequest
    }

    private static var holdMessage: String {
      String(localized: "Hold your identity card near the top of the iPhone.")
    }

    internal static func readCertificate(
      cardAccessNumber: String?,
      signatureCertificate: Bool
    ) async -> Outcome {
      let slot: CertificateSlot =
        signatureCertificate ? .qualifiedSignature : .authentication
      let fallbackSlot: CertificateSlot =
        signatureCertificate ? .secondQualifiedSignature : .secondAuthentication
      return await withCard(cardAccessNumber: cardAccessNumber) { operations in
        if let cert = (try? operations.readCertificate(slot))
          ?? (try? operations.readCertificate(fallbackSlot))
        {
          return .result(cert)
        }
        return .refusedBeforeCredentialTransmit(.certificateUnavailable)
      }
    }

    internal static func readCertificate(
      cardAccessNumber: String?,
      slot: CertificateSlot
    ) async -> Outcome {
      await withCard(cardAccessNumber: cardAccessNumber) { operations in
        if let cert = try? operations.readCertificate(slot) {
          return .result(cert)
        }
        return .refusedBeforeCredentialTransmit(.certificateUnavailable)
      }
    }

    internal static func withCard(
      cardAccessNumber: String?,
      _ operation: @escaping @Sendable (CardOperations) -> Outcome
    ) async -> Outcome {
      await withCard(cardAccessNumber: cardAccessNumber) { operations, _ in
        operation(operations)
      }
    }

    internal static func withCard(
      cardAccessNumber: String?,
      _ operation:
        @escaping @Sendable (
          CardOperations,
          RappNearFieldSessionHolder.Context?
        ) -> Outcome
    ) async -> Outcome {
      if let readerResult = await RappReaderSessionHolder.shared.execute(
        cardAccessNumber: cardAccessNumber,
        operation
      ) {
        switch readerResult {
        case .connected(let outcome):
          return outcome

        case .wrongCardAccessNumber:
          return .rejected(.cardAccessNumber)

        case .failed:
          return .refusedBeforeCredentialTransmit(.cardUnavailable)
        }
      }
      guard let cardAccessNumber else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      guard
        let result = await RappNearFieldSessionHolder.shared.execute(
          cardAccessNumber: cardAccessNumber,
          message: holdMessage,
          operation
        )
      else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      return result
    }
  }
#endif
