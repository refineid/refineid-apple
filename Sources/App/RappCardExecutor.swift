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
      /// The PIN 1 counter shows a refusal since the held PIN 1 was
      /// accepted, so the held value was not sent (RAPP v26.10.29 §11 item
      /// 2).
      case heldPin1Unconfirmed
      case invalidCredential(CredentialRole)
      case keyOrAlgorithmMismatch
      case retryFloor(CredentialRole, RetryFloorVerdict)
    }

    internal enum Rejection: Sendable, Equatable {
      case cardAccessNumber
      case credential(CredentialRole, remaining: RetryCount?)
    }

    internal enum Outcome: Sendable, Equatable, NearFieldOutcome {
      case completionAmbiguous
      case refusedBeforeCredentialTransmit(Refusal)
      case rejected(Rejection)
      case result(Data)

      /// Whether the operation has the card's result.
      internal var isResult: Bool {
        if case .result = self { return true }
        return false
      }

      /// The step an outcome without the card's result broke at.
      internal var failedStep: NearFieldStep? {
        switch self {
        case .result:
          nil

        case .rejected(.cardAccessNumber), .refusedBeforeCredentialTransmit(.cardUnavailable):
          .secureChannel

        case .refusedBeforeCredentialTransmit(.certificateUnavailable),
          .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch):
          .certificate

        case .rejected(.credential), .refusedBeforeCredentialTransmit:
          .credential

        case .completionAmbiguous:
          .signature
        }
      }

      /// Whether the card answered the operation.
      internal var cardAnswered: Bool {
        switch self {
        case .result, .rejected:
          true

        case .refusedBeforeCredentialTransmit(let refusal):
          refusal != .cardUnavailable

        case .completionAmbiguous:
          false
        }
      }
    }

    internal struct Identity {
      internal let publicKey: SecKey
      internal let request: SignRequest
    }

    internal static func readCertificate(
      cardAccessNumber: String?,
      signatureCertificate: Bool
    ) async -> Outcome {
      let slot: CertificateSlot =
        signatureCertificate ? .qualifiedSignature : .authentication
      let fallbackSlot: CertificateSlot =
        signatureCertificate ? .secondQualifiedSignature : .secondAuthentication
      return await withCard(cardAccessNumber: cardAccessNumber, operation: .identity) {
        operations in
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
      await withCard(cardAccessNumber: cardAccessNumber, operation: .identity) { operations in
        if let cert = try? operations.readCertificate(slot) {
          return .result(cert)
        }
        return .refusedBeforeCredentialTransmit(.certificateUnavailable)
      }
    }

    internal static func withCard(
      cardAccessNumber: String?,
      operation: NearFieldOperation,
      _ work: @escaping @Sendable (CardOperations) -> Outcome
    ) async -> Outcome {
      await withCard(cardAccessNumber: cardAccessNumber, operation: operation) { operations, _ in
        work(operations)
      }
    }

    /// Runs `work` on the card in an attached reader, or else on the
    /// phone's own antenna with the sheet drawing the meter of
    /// `operation`.
    internal static func withCard(
      cardAccessNumber: String?,
      operation: NearFieldOperation,
      _ work:
        @escaping @Sendable (
          CardOperations,
          RappNearFieldSessionHolder.Context?
        ) -> Outcome
    ) async -> Outcome {
      if let readerResult = await RappReaderSessionHolder.shared.execute(
        cardAccessNumber: cardAccessNumber,
        work
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
          operation: operation,
          work
        )
      else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      return result
    }
  }
#endif
