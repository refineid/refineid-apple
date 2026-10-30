// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD

  import CardCore
  import Foundation
  import Security

  /// The setup flow that teaches this device the card.
  ///
  /// The reads behind the secure channel are platform-neutral; the field
  /// that carries them lives in the iOS extensions of this type.
  internal enum CardPriming {
    /// Stores the identity while the card is still in the field.
    internal typealias StoreIdentity = (Identity) throws -> Void

    /// The identity a first prime stores: everything the token
    /// extension's mint and a later signature need from the card.
    internal struct Identity: Sendable {
      /// CryptoTokenKit instance ID derived from the printed serial.
      internal let instance: TokenInstanceID

      /// Authentication certificate DER.
      internal let certificate: Data

      /// Issuing certificate DER when the cache or the card supplied it.
      internal let issuer: Data?

      /// Chip serial retained for exact reconstruction.
      internal let tokenSerial: String

      /// Proof that the live card did not report a factory activation state.
      internal let activationCheck: PrimedIdentity.ActivationCheck
    }

    /// What the one field reads off a card this device has never primed.
    internal struct Payload: Sendable {
      /// The identity, stored before the rest of the hold's reads.
      internal let identity: Identity

      /// The credential counters read in this same hold.
      ///
      /// Read here because the recovery route decided right after this
      /// hold is what consumes them; nothing stores them as a lasting
      /// claim about the card.
      internal let credentialReport: CredentialProbeReport?
    }

    /// Reads the identity behind the established secure channel, stores
    /// it, then reads the counters and learns any missing root.
    ///
    /// `sheet` reaches the certificate step before the identity read and
    /// the stored step before the store; a throw leaves the step it broke
    /// in running for the caller to fail.
    ///
    /// The qualified signature certificate is not read here: the first
    /// signature that needs it reads it in its own card session.
    internal static func readSecuredPayload(
      operations: CardOperations,
      sheet: NearFieldSheet,
      store: StoreIdentity
    ) throws -> Payload {
      sheet.reach(.certificate)
      let identity = try Self.readIdentity(operations: operations)
      sheet.reach(.stored)
      try store(identity)
      let credentialReport = try? operations.probeCredentials()
      Self.learnRoot(above: identity.issuer, operations: operations)
      return Payload(identity: identity, credentialReport: credentialReport)
    }

    /// The reads behind the secure channel, validated into an identity.
    ///
    /// PIN1 is not sent. The certificate is public and the secure channel
    /// is the only thing it needs, so setup asks the card for nothing it
    /// will not use. The issuer comes from the cache when one matches and
    /// from the card otherwise.
    private static func readIdentity(
      operations: CardOperations
    ) throws -> Identity {
      let certificate = try operations.readCertificate(.authentication)
      let activationCheck = try Self.activationCheck(
        certificate: certificate,
        operations: operations
      )
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
        cardRoot: { nil }
      )
      return Identity(
        instance: instance,
        certificate: certificate,
        issuer: issuer,
        tokenSerial: serial.value,
        activationCheck: activationCheck)
    }

    /// Reads the card's root only when no cached root issued `issuer`.
    private static func learnRoot(above issuer: Data?, operations: CardOperations) {
      guard let issuer else { return }
      TrustRootsCache.shared.learnRoot(
        above: issuer,
        cardRoot: { try? operations.readCertificate(.root) })
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
  }

#endif
