// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation
  import Security

  /// The setup of an organization card on the phone's antenna.
  ///
  /// Such a card answers nothing but EF.CardAccess until PACE has run with
  /// PIN 1 or PIN 2 (FINEID S1 v4.0, organizational cards, section 2.1),
  /// so the holder's PIN 1 opens the channel the certificates are read
  /// through. What is stored is the organization prime, certificates and
  /// chip serial only, under the card model's historical bytes
  /// (``OrganizationPrimeStore``); PIN 1 is spent on this one handshake and
  /// is neither stored nor held.
  extension CardPriming {
    /// PACE with PIN 1, the reads behind it, and the prime stored.
    internal static func readOrganization(
      channel: SmartCardChannel,
      pin1: Pin1Entry,
      execution: HoldExecution
    ) throws -> HoldRead {
      let opened: OrganizationCardOpening.Opened
      do {
        opened = try OrganizationCardOpening.pin1(
          over: channel,
          pin1.issue().consumeForSingleTransmission(),
          spending: .entered)
      } catch {
        throw Self.organizationFailure(error)
      }
      let operations = opened.operations
      execution.sheet.reach(.certificate)
      let certificate = try operations.readCertificate(.authentication)
      let serial = try operations.readChipSerial()
      guard let instance = TokenInstanceID(chipSerial: serial) else {
        throw Failure.unidentifiedCard
      }
      guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
        throw Failure.certificateUnreadable
      }
      let issuer = TrustRootsCache.shared.issuer(
        for: certificate,
        cardIssuer: { try? operations.readCertificate(.issuing) },
        cardRoot: { nil })
      // Optional, so read last: a refused select of an absent file can
      // leave another file current.
      let signatureCertificate =
        (try? operations.readCertificate(.qualifiedSignature))
        ?? (try? operations.readCertificate(.secondQualifiedSignature))
      execution.sheet.reach(.stored)
      guard
        let prime = OrganizationPrime(
          certificate: certificate,
          issuer: issuer,
          signatureCertificate: signatureCertificate,
          chipSerial: serial),
        OrganizationPrimeStore.store(prime, answerToReset: execution.session.answerToReset)
      else {
        throw Failure.primeNotStored
      }
      return HoldRead(instance: instance, credentialReport: nil)
    }

    /// The setup failure a refused PIN 1 handshake comes to, worded with
    /// the sentences a refused PIN 1 already has.
    private static func organizationFailure(_ error: any Error) -> any Error {
      switch error {
      case SmartCardChannel.TransportError.responseTimedOut:
        return Failure.secureChannelTimedOut

      case PaceEstablishment.Failure.wrongPin(let remaining):
        return remaining.isBlocked
          ? CardOperationError.pinBlocked
          : CardOperationError.pinRejected(remaining: remaining)

      case PaceEstablishment.Failure.retryFloorRefused(_, .remaining(let remaining)):
        return Failure.pin1LowAttempts(remaining)

      case PaceEstablishment.Failure.retryFloorRefused(_, .locked):
        return CardOperationError.pinBlocked

      case PaceEstablishment.Failure.retryFloorRefused,
        PaceEstablishment.Failure.passwordDeactivated:
        return Failure.pin1Unavailable

      default:
        return error
      }
    }
  }

#endif
