// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Owns one established RAPP operation runtime and translates engine
  /// records into Sendable Apple-side values. It never performs card I/O
  /// itself. Nothing of an operation outlives the session (RAPP v26.10.21
  /// §8.1 item 3).
  public actor RappOperationDriver {
    internal let bridge: RappOperationBridge
    internal let entropy: RappPlatformEntropy
    internal let clock: RappPlatformClock
    internal var closed = false

    internal init(
      role: RappSessionDriver.Role,
      session: RappSessionBridge,
      maximumLifetimeMilliseconds: UInt64,
      entropy: RappPlatformEntropy,
      clock: RappPlatformClock
    ) throws {
      self.entropy = entropy
      self.clock = clock
      let now = clock.monotonicMilliseconds()
      switch role {
      case .requester:
        bridge = try RappOperationBridge.beginRequester(
          session: session, maximumLifetimeMs: maximumLifetimeMilliseconds, nowMs: now)

      case .proxy:
        bridge = try RappOperationBridge.beginProxy(
          session: session, maximumLifetimeMs: maximumLifetimeMilliseconds, nowMs: now)
      }
    }

    /// Starts a requester inspection of the card's answer to reset.
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

    /// Starts a requester batch signature over named documents (RAPP
    /// v26.10.21 §9.3); names and digests pair up by position.
    public func beginBatchSignDocuments(
      documentNames: [String],
      keyProfile: KeyProfile,
      algorithm: SignatureAlgorithm,
      digests: [Data],
      expiresAfterMilliseconds: UInt64
    ) throws -> [Command] {
      try commands(
        bridge.beginBatchSignDocuments(
          operationId: entropy.operationID(),
          documentNames: documentNames,
          keyProfile: keyProfile.binding,
          algorithm: algorithm.binding,
          digests: digests,
          localStartMs: clock.monotonicMilliseconds(),
          expiresAfterMs: expiresAfterMilliseconds
        ))
    }

    /// The recorder a custodian's card session records each batch
    /// signature through, as the card makes it.
    nonisolated public func batchSignatureRecorder(
      operationID: RappOperationIdentifier
    ) -> RappBatchSignatureRecorder {
      RappBatchSignatureRecorder(bridge: bridge, operationID: operationID)
    }

    /// Completes a batch once every document is signed.
    public func completeBatch(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(bridge.completeBatch(operationId: operationID))
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
          bridge.receiveFrame(bytes: frame, nowMs: clock.monotonicMilliseconds()))
      } catch {
        return protocolFailure()
      }
    }

    /// Reports a change of the live operation's state (§8.2).
    public func reportProgress(operationID: RappOperationIdentifier, event: ProgressEvent) throws
      -> [Command]
    {
      try commands(bridge.reportProgress(operationId: operationID, event: event))
    }

    /// The operation has the card and its prerequisite reads are done; a
    /// read runs at once and an operation past its deadline is cancelled
    /// (§8.1 item 2, §8.2 items 3 and 6).
    public func prerequisitesComplete(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(
        bridge.prerequisitesComplete(operationId: operationID, nowMs: clock.monotonicMilliseconds())
      )
    }

    /// Approves exactly the request displayed by the authorizer UI.
    public func approve(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(
        bridge.approve(operationId: operationID, approvedAtMs: clock.monotonicMilliseconds()))
    }

    /// The holder declined.
    public func deny(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(bridge.deny(operationId: operationID))
    }

    /// Rejects a request that is unsupported or contradicts the live card.
    public func requestInvalidOrUnsupported(operationID: RappOperationIdentifier) throws
      -> [Command]
    {
      try commands(bridge.requestInvalidOrUnsupported(operationId: operationID))
    }

    /// The retry floor refused before any verification (§10.2).
    public func retryFloor(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(bridge.retryFloor(operationId: operationID))
    }

    /// The card did not answer: no card within the wait, the field lost, a
    /// transmission fault.
    public func cardError(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(bridge.cardError(operationId: operationID))
    }

    /// The custodian could not carry the operation out for a reason of its
    /// own.
    public func operationFailed(operationID: RappOperationIdentifier) throws -> [Command] {
      try commands(bridge.operationFailed(operationId: operationID))
    }

    /// Cancels the live operation when its deadline passed before the card
    /// was commanded (§8.1 item 2).
    public func expireDue() -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(bridge.expireDue(nowMs: clock.monotonicMilliseconds()))
      } catch {
        return []
      }
    }

    /// Completes an inspection with the card's answer to reset, or its
    /// historical bytes; empty when the platform exposes neither.
    public func completeInspection(operationID: RappOperationIdentifier, answerToReset: Data) throws
      -> [Command]
    {
      try commands(
        bridge.completeInspection(operationId: operationID, answerToReset: answerToReset))
    }

    /// Completes an identity read (§9.1).
    public func completeIdentity(operationID: RappOperationIdentifier, identity: Identity) throws
      -> [Command]
    {
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

    /// Completes a certificate read with DER bytes read from the card.
    public func completeCertificate(operationID: RappOperationIdentifier, der: Data) throws
      -> [Command]
    {
      try commands(bridge.completeCertificate(operationId: operationID, der: der))
    }

    /// Completes a signing operation with the card-produced signature.
    public func completeSignature(operationID: RappOperationIdentifier, signature: Data) throws
      -> [Command]
    {
      try commands(bridge.completeSignature(operationId: operationID, signature: signature))
    }
  }
#endif
