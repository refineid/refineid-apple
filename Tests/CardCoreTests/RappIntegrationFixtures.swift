// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  internal enum RappIntegrationFixtures {
    // MARK: Nested Types

    internal typealias FrameReceiver = @Sendable (Data) async -> Void

    /// How far the custodian took an operation before it ended.
    internal struct ProxyProgress: Equatable {
      internal var prerequisites = 0
      internal var approvals = 0
      internal var executions = 0
    }

    /// Each way the custodian ends an operation without a completed
    /// result, and the registered error the requester receives for it
    /// (RAPP v26.10.29 §10.3).
    internal enum ProxyTermination: CaseIterable, Sendable {
      case cardError
      case operationFailed
      case retryFloor
      case unsupportedRequest
      case userDenied

      // MARK: Computed Properties

      internal var reason: RappTerminalReason {
        switch self {
        case .cardError:
          .cardError

        case .operationFailed:
          .operationFailed

        case .retryFloor:
          .retryFloor

        case .unsupportedRequest:
          .unsupportedParameter

        case .userDenied:
          .userCancelled
        }
      }

      /// Where the custodian stops: a refusal before consent, a denial at
      /// consent, or a card command that produced no answer.
      internal var progress: ProxyProgress {
        switch self {
        case .retryFloor, .unsupportedRequest:
          ProxyProgress(prerequisites: 1)

        case .userDenied:
          ProxyProgress(prerequisites: 1, approvals: 1)

        case .cardError, .operationFailed:
          ProxyProgress(prerequisites: 1, approvals: 1, executions: 1)
        }
      }

      /// A synthetic origin naming the path, so each case signs its own
      /// challenge.
      internal var origin: String {
        "https://\(self).example.invalid"
      }
    }

    internal enum TestFailure: Error {
      case connectionClosed(RappConnectionCoordinator.CloseReason)
      case operationEndedWithoutResult
      case operationTerminated(RappTerminalReason)
      case pairingClosed(RappPairingCoordinator.CloseReason)
      case pairingEndedWithoutRecord
      case receiverMissing
      case unexpectedConnectionEvent
      case unexpectedResult(RappOperationResult)
    }

    internal enum FixtureTiming {
      internal static let operationExpiryMilliseconds: UInt64 = 60_000
      internal static let connectionMaximumLifetimeMilliseconds: UInt64 = 60_000
    }

    internal struct PairingFixture {
      internal let requesterVault: RappDeviceVault
      internal let proxyVault: RappDeviceVault
      internal let requesterSummary: RappPairingCoordinator.PairSummary
      internal let proxySummary: RappPairingCoordinator.PairSummary
      internal let requesterFrames: (frames: [Data], closeCount: Int)
      internal let proxyFrames: (frames: [Data], closeCount: Int)
      internal let requesterPrefix: String
      internal let proxyPrefix: String
    }

    internal struct ConnectionFixture {
      internal let requester: RappConnectionCoordinator
      internal let proxy: RappConnectionCoordinator
      internal let requesterOutbound: FrameEndpoint
      internal let proxyOutbound: FrameEndpoint
    }

    internal enum RequestedOperation: Sendable, Equatable {
      case browserAuthentication(
        origin: String,
        digest:
          Data)
      case documentSigning(
        documentName: String,
        digest:
          Data)

      // MARK: Computed Properties

      internal var kind: RappOperationDriver.OperationKind {
        switch self {
        case .browserAuthentication:
          .browserAuthenticate

        case .documentSigning:
          .signDocument
        }
      }

      internal var displayContext: String {
        switch self {
        case .browserAuthentication(let origin, _):
          origin

        case .documentSigning(let documentName, _):
          documentName
        }
      }

      internal var digest: Data {
        switch self {
        case .browserAuthentication(_, let digest), .documentSigning(_, let digest):
          digest
        }
      }

      // MARK: Static Functions

      /// A browser authentication for `origin` over the SHA-256 digest of
      /// a synthetic challenge, the digest size the ECDSA P-256 profile
      /// signs.
      internal static func browserAuthentication(origin: String) -> Self {
        .browserAuthentication(
          origin: origin, digest: Data(SHA256.hash(data: Data("challenge for \(origin)".utf8))))
      }

      // MARK: Functions

      internal func begin(on coordinator: RappConnectionCoordinator) async throws {
        switch self {
        case .browserAuthentication(let origin, let digest):
          try await coordinator.beginBrowserAuthentication(
            origin: origin,
            keyProfile: .ecdsaP256,
            algorithm: .ecdsaSHA256,
            digest: digest,
            expiresAfterMilliseconds: FixtureTiming.operationExpiryMilliseconds
          )

        case .documentSigning(let documentName, let digest):
          try await coordinator.beginSignDocument(
            documentName: documentName,
            keyProfile: .ecdsaP256,
            algorithm: .ecdsaSHA256,
            digest: digest,
            expiresAfterMilliseconds: FixtureTiming.operationExpiryMilliseconds
          )
        }
      }

      internal func matches(_ operation: RappOperationDriver.Operation) -> Bool {
        operation.kind == kind
          && operation.displayContext == displayContext
          && operation.keyProfile == .ecdsaP256
          && operation.algorithm == .ecdsaSHA256
          && operation.digest == digest
      }
    }

    internal actor FrameEndpoint {
      // MARK: Properties

      private var receiver: FrameReceiver?
      private var frames: [Data] = []
      private var closeCount = 0
      /// The latest delivery; each frame waits for the one before it.
      private var tail: Task<Void, Never>?

      // MARK: Functions

      internal func install(_ receiver: @escaping FrameReceiver) {
        self.receiver = receiver
      }

      /// Hands the frame to the peer without waiting for it to be processed.
      ///
      /// A real transport returns once the frame is on its way. Delivering
      /// it inline instead suspends the sender inside its own coordinator
      /// until the peer has finished, so a reply that arrives during that
      /// window waits for an actor the sender still holds and neither side
      /// moves again. The peers are two actors here, and every exchange in
      /// this protocol is a reply.
      internal func send(_ frame: Data) async throws {
        frames.append(frame)
        guard let receiver else { throw TestFailure.receiverMissing }
        let previous = tail
        tail = Task {
          await previous?.value
          await receiver(frame)
        }
        // Lets the delivery above begin before the sender continues; frames
        // still arrive in the order they were sent, as on a real transport.
        await Task.yield()
      }

      internal func close() {
        closeCount += 1
      }

      internal func snapshot() -> (frames: [Data], closeCount: Int) {
        (frames, closeCount)
      }
    }

    internal actor TransportRecorder {
      // MARK: Properties

      private var frames: [Data] = []
      private var closeCount = 0

      // MARK: Functions

      internal func record(_ frame: Data) {
        frames.append(frame)
      }

      internal func close() {
        closeCount += 1
      }

      internal func snapshot() -> (frames: [Data], closeCount: Int) {
        (frames, closeCount)
      }
    }

    // MARK: Static Properties

    internal static let profiles = rappCredentialProfiles()
    internal static let transportProfile = rappStreamProfileName()

    /// A synthetic signature; the custodian relays the card's bytes
    /// without reading them.
    internal static let signature = Data("synthetic card signature".utf8)

    /// The fingerprint of a synthetic authentication certificate, naming
    /// the card the custodian serves.
    internal static let cardFingerprint = RappCertificateFingerprint(
      certificate: Data("synthetic authentication certificate".utf8))
  }
#endif
