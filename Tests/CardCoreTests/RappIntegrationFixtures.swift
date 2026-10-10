// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  internal enum RappIntegrationFixtures {
    // MARK: Nested Types

    internal typealias FrameReceiver = @Sendable (Data) async -> Void

    internal struct ProxyProgress: Equatable {
      internal var prerequisites = 0
      internal var approvals = 0
      internal var executions = 0
      internal var acknowledgments = 0
    }

    internal enum ProxyTermination: CaseIterable, Sendable {
      case cardCompletionAmbiguous
      case cardRemovedBeforeTransmit
      case retryPolicyRefused
      case userDenied

      // MARK: Computed Properties

      internal var reason: RappOperationDriver.TerminalReason {
        switch self {
        case .userDenied:
          .userDenied

        case .retryPolicyRefused:
          .retryPolicyRefused

        case .cardRemovedBeforeTransmit:
          .cardRemovedBeforeTransmit

        case .cardCompletionAmbiguous:
          .cardCompletionAmbiguous
        }
      }

      internal var progress: ProxyProgress {
        switch self {
        case .userDenied:
          ProxyProgress(prerequisites: 1, approvals: 1)

        case .retryPolicyRefused:
          ProxyProgress(prerequisites: 1)

        case .cardRemovedBeforeTransmit:
          ProxyProgress(prerequisites: 1, approvals: 1)

        case .cardCompletionAmbiguous:
          ProxyProgress(prerequisites: 1, approvals: 1, executions: 1)
        }
      }

      internal var proxyTransportCloseCount: Int {
        switch self {
        case .retryPolicyRefused, .cardCompletionAmbiguous:
          1

        case .userDenied, .cardRemovedBeforeTransmit:
          0
        }
      }
    }

    internal enum TestFailure: Error {
      case connectionClosed(RappConnectionCoordinator.CloseReason)
      case operationEndedWithoutResult
      case operationTerminated(RappOperationDriver.TerminalReason?)
      case pairingClosed(RappPairingCoordinator.CloseReason)
      case pairingEndedWithoutRecord
      case receiverMissing
      case unexpectedConnectionEvent
      case unexpectedTransportError
    }

    internal enum FixtureTiming {
      internal static let operationExpiryMilliseconds: UInt64 = 60_000
      internal static let pairingOfferLifetimeMilliseconds: UInt64 = 60_000
      internal static let connectionMaximumLifetimeMilliseconds: UInt64 = 60_000
      internal static let probingBaseIntervalMilliseconds: UInt64 = 60_000
      internal static let probingResponseTimeoutMilliseconds: UInt64 = 10_000
      internal static let probingMaximumIntervalMilliseconds: UInt64 = 60_000
      internal static let toleratedMisses: UInt8 = 3
      internal static let interactiveBaseIntervalMilliseconds: UInt64 = 5_000
      internal static let interactiveResponseTimeoutMilliseconds: UInt64 = 3_000
      internal static let interactiveMaximumJitterMilliseconds: UInt64 = 500
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
        Task { await receiver(frame) }
        // Lets the delivery above begin before the sender continues, which
        // is the ordering a real transport gives without being asked.
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

    internal static let profiles = [
      "fi.refineid.card-status.v1",
      "fi.refineid.authentication.v1",
      "fi.refineid.document-signing.v1",
    ]
    internal static let transportProfile = "apple-peer-v1"
    internal static let candidateID = "apple-peer-v1.nearby"
    internal static let liveness = RappOperationDriver.Liveness(
      baseIntervalMilliseconds: FixtureTiming.probingBaseIntervalMilliseconds,
      responseTimeoutMilliseconds: FixtureTiming.probingResponseTimeoutMilliseconds,
      maximumIntervalMilliseconds: FixtureTiming.probingMaximumIntervalMilliseconds,
      maximumJitterMilliseconds: 0,
      maximumMisses: FixtureTiming.toleratedMisses
    )

    /// What the shipped requester actually runs with.
    ///
    /// The suite's own liveness never fires inside a test, so every path
    /// below was measured with no probe in flight. A card read takes
    /// several seconds of antenna time, which is longer than this
    /// interval, so on a device a probe is always in flight while an
    /// operation is executing -- the one arrangement the fast fixture
    /// could not produce.
    internal static let interactiveLiveness = RappOperationDriver.Liveness(
      baseIntervalMilliseconds: FixtureTiming.interactiveBaseIntervalMilliseconds,
      responseTimeoutMilliseconds: FixtureTiming.interactiveResponseTimeoutMilliseconds,
      maximumIntervalMilliseconds: FixtureTiming.probingMaximumIntervalMilliseconds,
      maximumJitterMilliseconds: FixtureTiming.interactiveMaximumJitterMilliseconds,
      maximumMisses: FixtureTiming.toleratedMisses
    )
  }
#endif
