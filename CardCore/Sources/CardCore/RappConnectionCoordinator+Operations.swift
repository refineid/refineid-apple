// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappConnectionCoordinator {
    /// Starts an inspect-card operation with the given expiry window.
    public func beginInspectCard(expiresAfterMilliseconds: UInt64) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginInspectCard(
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a read-identity operation with the given expiry window.
    public func beginReadIdentity(expiresAfterMilliseconds: UInt64) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginReadIdentity(
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a read of the authentication or signature certificate.
    public func beginReadCertificate(
      signatureCertificate: Bool,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginReadCertificate(
          signatureCertificate: signatureCertificate,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a browser-authentication operation over a digest for an origin.
    public func beginBrowserAuthentication(
      origin: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginBrowserAuthentication(
          origin: origin,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Starts a batch signature over the digests of named documents.
    public func beginBatchSignDocuments(
      documentNames: [String],
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digests: [Data],
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginBatchSignDocuments(
          documentNames: documentNames,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digests: digests,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// The recorder a card session records each batch signature through.
    public func batchSignatureRecorder(
      operationID: RappOperationIdentifier
    ) throws -> RappBatchSignatureRecorder {
      try operationDriver().batchSignatureRecorder(operationID: operationID)
    }

    /// Completes a batch once every document is signed.
    public func completeBatch(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.completeBatch(operationID: operationID))
    }

    /// Starts a sign-document operation over the digest of a named document.
    public func beginSignDocument(
      documentName: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data,
      expiresAfterMilliseconds: UInt64
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.beginSignDocument(
          documentName: documentName,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: expiresAfterMilliseconds
        ))
    }

    /// Tells the requester which card can answer now (RAPP v26.10.22 §8.4).
    public func reportCardStatus(_ status: RappCardStatus) async throws {
      let driver = try operationDriver()
      await handleOperation(await driver.reportCardStatus(status))
    }

    /// Reports progress on an active operation, such as a PIN prompt being
    /// on screen (RAPP v26.10.22 §8.2 item 3).
    public func reportProgress(operationID: RappOperationIdentifier, event: ProgressEvent)
      async throws
    {
      let driver = try operationDriver()
      await handleOperation(try await driver.reportProgress(operationID: operationID, event: event))
    }

    /// Reports that proxy-side prerequisites for the operation are met.
    public func prerequisitesComplete(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.prerequisitesComplete(operationID: operationID))
    }

    /// Records the local user's approval of the pending operation.
    public func approve(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.approve(operationID: operationID))
    }

    /// Records the local user's denial of the pending operation.
    public func deny(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.deny(operationID: operationID))
    }

    /// Rejects the operation as malformed or unsupported on this device.
    public func requestInvalidOrUnsupported(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.requestInvalidOrUnsupported(
          operationID: operationID
        ))
    }

    /// The retry floor refused before any verification (RAPP v26.10.22
    /// §10.2).
    public func retryFloor(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.retryFloor(operationID: operationID))
    }

    /// The card did not answer: no card within the wait, the field lost, a
    /// transmission fault.
    public func cardError(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.cardError(operationID: operationID))
    }

    /// The custodian could not carry the operation out for a reason of its
    /// own.
    public func operationFailed(operationID: RappOperationIdentifier) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.operationFailed(operationID: operationID))
    }

    /// Completes an inspection with the card's answer to reset, or its
    /// historical bytes.
    public func completeInspection(operationID: RappOperationIdentifier, answerToReset: Data)
      async throws
    {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeInspection(operationID: operationID, answerToReset: answerToReset)
      )
    }

    /// Completes an identity read (RAPP v26.10.22 §9.1).
    public func completeIdentity(
      operationID: RappOperationIdentifier,
      identity: RappOperationDriver.Identity
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeIdentity(operationID: operationID, identity: identity))
    }

    /// Completes a certificate read with the DER-encoded certificate.
    public func completeCertificate(operationID: RappOperationIdentifier, der: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeCertificate(operationID: operationID, der: der))
    }

    /// Completes a signature operation with the raw signature bytes.
    public func completeSignature(operationID: RappOperationIdentifier, signature: Data)
      async throws
    {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeSignature(
          operationID: operationID,
          signature: signature
        ))
    }
  }
#endif
