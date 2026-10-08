// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Owns one established RAPP operation runtime and translates generated binding
  /// records into Sendable Apple-side values. It never performs card I/O itself.
  public actor RappOperationDriver {
    internal enum OperationCommandKind {
      case inspect
      case approval
      case safeRead
      case cardCommand
    }

    internal let bridge: RappOperationBridge
    internal let entropy: RappPlatformEntropy
    internal let clock: RappPlatformClock
    internal let vault: RappDeviceVault
    internal let pairID: Data
    internal var closed = false

    /// Whether this driver durably revoked the pairing while closing, so
    /// the close is reported as a revocation rather than a released frame.
    internal var revokedWhileClosing = false

    internal init(
      role: RappSessionDriver.Role,
      pairID: Data,
      session: RappSessionBridge,
      vault: RappDeviceVault,
      maximumLifetimeMilliseconds: UInt64,
      liveness: Liveness,
      entropy: RappPlatformEntropy,
      clock: RappPlatformClock
    ) throws {
      self.entropy = entropy
      self.clock = clock
      self.vault = vault
      self.pairID = pairID
      let now = clock.monotonicMilliseconds()
      switch role {
      case .requester:
        bridge = try RappOperationBridge.beginRequester(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )

      case .proxy:
        bridge = try RappOperationBridge.beginProxy(
          session: session,
          vault: vault,
          maximumLifetimeMs: maximumLifetimeMilliseconds,
          liveness: liveness.binding,
          nowMs: now
        )
      }
    }

    /// Starts a requester inspection of card and PIN status.
    public func beginInspectCard(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginInspectCard(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the cardholder identity.
    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) throws -> [Command] {
      try commands(
        bridge.beginReadIdentity(
          operationId: entropy.operationID(),
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester read of the authentication or signature certificate.
    public func beginReadCertificate(
      signatureCertificate: Bool,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginReadCertificate(
          operationId: entropy.operationID(),
          signatureCertificate: signatureCertificate,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester browser-authentication signature for the given origin.
    public func beginBrowserAuthentication(
      origin: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginBrowserAuthentication(
          operationId: entropy.operationID(),
          origin: origin,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Starts a requester document-signing operation for the named document.
    public func beginSignDocument(
      documentName: String,
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginSignDocument(
          operationId: entropy.operationID(),
          documentName: documentName,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digest: digest,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// Consumes one complete opaque frame received from the transport.
    public func receive(_ frame: Data) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.receiveFrame(
            bytes: frame,
            nowMs: clock.monotonicMilliseconds()
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Marks bounded card-status and certificate prerequisites complete.
    public func prerequisitesComplete(operationID: Data) throws -> [Command] {
      try commands(bridge.prerequisitesComplete(operationId: operationID))
    }

    /// Approves exactly the request displayed by the authorizer UI.
    public func approve(operationID: Data) throws -> [Command] {
      try commands(
        bridge.approve(
          operationId: operationID,
          approvedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Denies the exact request and emits a stable denial.
    public func deny(operationID: Data) throws -> [Command] {
      try commands(bridge.deny(operationId: operationID))
    }

    /// Rejects a request that is unsupported or contradicts the live card.
    public func requestInvalidOrUnsupported(operationID: Data) throws -> [Command] {
      try commands(bridge.requestInvalidOrUnsupported(operationId: operationID))
    }

    /// Reports that local retry policy refused the request.
    public func retryRefused(operationID: Data) throws -> [Command] {
      try commands(bridge.retryRefused(operationId: operationID))
    }

    /// Reports that the card rejected the presented credential.
    public func credentialRejected(operationID: Data) throws -> [Command] {
      try commands(
        bridge.credentialRejected(
          operationId: operationID,
          rejectedAtMs: clock.monotonicMilliseconds()
        ))
    }

    /// Reports that the card left the reader before the command was sent.
    public func cardRemovedBeforeTransmit(operationID: Data) throws -> [Command] {
      try commands(bridge.cardRemovedBeforeTransmit(operationId: operationID))
    }

    /// Reports that card completion could not be determined either way.
    public func cardCompletionAmbiguous(operationID: Data) throws -> [Command] {
      try commands(bridge.cardCompletionAmbiguous(operationId: operationID))
    }

    /// Completes an inspection with factory state and remaining attempt counts.
    public func completeInspection(
      operationID: Data,
      inspection: Inspection
    ) throws -> [Command] {
      try commands(
        bridge.completeInspection(
          operationId: operationID,
          answerToReset: inspection.answerToReset,
          pin1Factory: inspection.pin1Factory,
          pin2Factory: inspection.pin2Factory,
          pin1Attempts: inspection.pin1Attempts,
          pin2Attempts: inspection.pin2Attempts,
          pukAttempts: inspection.pukAttempts
        ))
    }

    /// Completes an identity read (RAPP v26.10.1 §9.1).
    public func completeIdentity(operationID: Data, identity: Identity) throws -> [Command] {
      try commands(
        bridge.completeIdentity(
          operationId: operationID,
          holderName: identity.holderName,
          cardId: identity.cardID,
          issuanceDate: identity.issuanceDate,
          expirationDate: identity.expirationDate,
          certificates: identity.certificates
        ))
    }

    /// Completes a certificate read with DER bytes read from the card and optional card serial.
    public func completeCertificate(
      operationID: Data,
      der: Data,
      cardSerial: String? = nil
    ) throws -> [Command] {
      try commands(
        bridge.completeCertificate(
          operationId: operationID,
          der: der,
          cardSerial: cardSerial
        ))
    }

    /// Completes a signing operation with the card-produced signature.
    public func completeSignature(operationID: Data, signature: Data) throws -> [Command] {
      try commands(bridge.completeSignature(operationId: operationID, signature: signature))
    }
  }
#endif
