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

    /// Reports that proxy-side prerequisites for the operation are met.
    public func prerequisitesComplete(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.prerequisitesComplete(operationID: operationID))
    }

    /// Records the local user's approval of the pending operation.
    public func approve(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.approve(operationID: operationID))
    }

    /// Records the local user's denial of the pending operation.
    public func deny(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.deny(operationID: operationID))
    }

    /// Rejects the operation as malformed or unsupported on this device.
    public func requestInvalidOrUnsupported(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.requestInvalidOrUnsupported(
          operationID: operationID
        ))
    }

    /// Reports that the local retry policy refused to run the operation.
    public func retryRefused(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.retryRefused(operationID: operationID))
    }

    /// Reports that the card rejected the presented credential.
    public func credentialRejected(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(try await driver.credentialRejected(operationID: operationID))
    }

    /// Reports that the card left the reader before the command was sent.
    public func cardRemovedBeforeTransmit(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.cardRemovedBeforeTransmit(
          operationID: operationID
        ))
    }

    /// Reports that the card command's completion could not be confirmed.
    public func cardCompletionAmbiguous(operationID: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.cardCompletionAmbiguous(
          operationID: operationID
        ))
    }

    /// Completes an inspection with PIN factory state and attempt counts.
    public func completeInspection(
      operationID: Data,
      inspection: RappOperationDriver.Inspection
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeInspection(
          operationID: operationID,
          inspection: inspection
        ))
    }

    /// Completes an identity read (RAPP v26.10.1 §9.1).
    public func completeIdentity(
      operationID: Data,
      identity: RappOperationDriver.Identity
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeIdentity(operationID: operationID, identity: identity))
    }

    /// Completes a certificate read with the DER-encoded certificate and optional card serial.
    public func completeCertificate(
      operationID: Data,
      der: Data,
      cardSerial: String? = nil
    ) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeCertificate(
          operationID: operationID,
          der: der,
          cardSerial: cardSerial
        ))
    }

    /// Completes a signature operation with the raw signature bytes.
    public func completeSignature(operationID: Data, signature: Data) async throws {
      let driver = try operationDriver()
      await handleOperation(
        try await driver.completeSignature(
          operationID: operationID,
          signature: signature
        ))
    }
  }
#endif
