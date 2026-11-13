// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import os
  import RappEngine
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
      /// accepted, so the held value was not sent (RAPP v26.11.8 §11 item
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

    /// What one browser authentication answered, paired with the pre-VERIFY
    /// PIN 1 counter reading and the certificate fingerprint of the card
    /// that signed.
    internal struct BrowserAuthenticationOutcome: Sendable, Equatable {
      internal let outcome: Outcome
      internal let preVerifyProbe: RetryProbeOutcome?
      internal let authenticatedCard: RappCertificateFingerprint?

      /// How this authentication settles ``HeldPin1`` for `card`.
      internal func pin1Settlement(
        spending pin1: SigningPin
      ) -> CardBoundPin1<RappCertificateFingerprint>.Settlement {
        switch outcome {
        case .result:
          switch pin1 {
          case .enteredPin1(let entry):
            return .accepted(
              entry,
              preVerifyProbe: preVerifyProbe ?? .noInformation,
              card: authenticatedCard
            )

          case .heldPin1:
            return .probed(preVerifyProbe ?? .noInformation)

          case .pin2:
            return .unchanged
          }

        case .rejected(.credential(.pin1, _)),
          .refusedBeforeCredentialTransmit(.invalidCredential(.pin1)),
          .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch),
          .refusedBeforeCredentialTransmit(.certificateUnavailable):
          return .clear

        case .refusedBeforeCredentialTransmit(.cardUnavailable):
          return .cardUnavailable

        case .refusedBeforeCredentialTransmit(.heldPin1Unconfirmed),
          .refusedBeforeCredentialTransmit(.retryFloor(.pin1, _)),
          .refusedBeforeCredentialTransmit(.credentialBlocked(.pin1)),
          .refusedBeforeCredentialTransmit(.credentialInvalidated(.pin1)):
          return .probed(preVerifyProbe ?? .noInformation)

        default:
          if let probe = preVerifyProbe {
            return .probed(probe)
          }
          return .unchanged
        }
      }
    }

    /// Collects the pre-VERIFY PIN 1 probe and authenticated card identity
    /// observed during one browser authentication, while clearing
    /// ``HeldPin1`` immediately on any non-pristine probe or refusal.
    internal final class Pin1ProbeObserver: Sendable {
      private let recorded = OSAllocatedUnfairLock<
        (card: RappCertificateFingerprint?, probe: RetryProbeOutcome?)
      >(initialState: (card: nil, probe: nil))

      internal var authenticatedCard: RappCertificateFingerprint? {
        recorded.withLock { $0.card }
      }

      internal var preVerifyProbe: RetryProbeOutcome? {
        recorded.withLock { $0.probe }
      }

      internal func recordCard(_ certificateDER: Data) {
        let card = RappCertificateFingerprint(certificate: certificateDER)
        recorded.withLock { $0.card = card }
      }

      internal func recordProbe(_ probe: RetryProbeOutcome) {
        HeldPin1.shared.retain(after: probe)
        recorded.withLock { state in
          if state.probe == nil || !Pin1Retention.permitsHolding(after: probe) {
            state.probe = probe
          }
        }
      }

      internal func clearHeld() {
        HeldPin1.shared.clear()
      }
    }

    /// The PIN a signature spends (RAPP v26.11.8 section 8.2 item 3, section
    /// 11 item 2).
    ///
    /// Each case carries the holder's zeroizing entry; every card command
    /// is sent a single-use PIN the entry issues for it.
    internal enum SigningPin: Sendable {
      /// PIN 1 the holder typed for this browser authentication.
      case enteredPin1(Pin1Entry)
      /// PIN 1 held from an earlier operation the card accepted; spent only
      /// while the card's PIN 1 counter shows no refusal since.
      case heldPin1(Pin1Entry)
      /// PIN 2 the holder typed for this signature or batch.
      case pin2(Pin2Entry)

      /// The credential the card checks it as.
      internal var role: CredentialRole {
        switch self {
        case .enteredPin1, .heldPin1:
          .pin1

        case .pin2:
          .pin2
        }
      }

      /// Where the PIN comes from, for the counter check before it is sent.
      internal var spending: PinAdmission.Spending {
        switch self {
        case .heldPin1:
          .heldPin1

        case .enteredPin1, .pin2:
          .entered
        }
      }
    }

    internal struct SignParameters {
      internal let cardAccessNumber: String?
      internal let pin: SigningPin
      internal let keyProfile: RappOperationDriver.KeyProfile
      internal let algorithm: RappOperationDriver.SignatureAlgorithm
      internal let digest: Data

      internal var role: CredentialRole { pin.role }

      /// Whether this is a qualified signature, with PIN 2.
      internal var qualified: Bool { pin.role == .pin2 }

      /// The certificate whose key signs.
      internal var slot: CertificateSlot { qualified ? .qualifiedSignature : .authentication }
    }

    internal struct Identity {
      internal let certificateDER: Data
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
      await withCard(
        cardAccessNumber: cardAccessNumber,
        operation: operation,
        organization: nil,
        personal: { operations, _ in work(operations) }
      )
    }

    /// Runs `work` on the card in an attached reader, or else on the
    /// phone's own antenna with the sheet drawing the meter of
    /// `operation`.
    ///
    /// On the antenna a personal card opens with `cardAccessNumber`. The
    /// phone's organization card opens only with the PIN an operation
    /// spends, so `organization` runs instead, on the field's plain
    /// channel, and runs its own PACE; an operation without it, such as a
    /// certificate read the prime does not answer, finds no card.
    internal static func withCard(
      cardAccessNumber: String?,
      operation: NearFieldOperation,
      organization: (
        @Sendable (CardOperations, RappNearFieldSessionHolder.Context) -> Outcome
      )?,
      personal work:
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
      OrganizationCardStore.synchronize()
      if OrganizationCardStore.kind() == .organization {
        guard let organization else {
          return .refusedBeforeCredentialTransmit(.cardUnavailable)
        }
        return await RappNearFieldSessionHolder.shared.execute(
          opening: .organizationCard,
          operation: operation,
          organization
        ) ?? .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      guard let cardAccessNumber else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      guard
        let result = await RappNearFieldSessionHolder.shared.execute(
          opening: .cardAccessNumber(cardAccessNumber),
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
