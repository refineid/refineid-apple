// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Drives one explicit, one-use RAPP pairing attempt. No pair secret is exposed
  /// to Swift; the generated Rust bridge owns the QR bearer secret, Noise state,
  /// private keys, transcript checks, and final pair record.
  public actor RappPairingCoordinator {
    // MARK: Nested Types

    /// One transport option offered for the pairing attempt.
    public struct TransportCandidate: Sendable, Equatable {
      // MARK: Properties

      /// Registered transport profile name.
      public let profile: String
      /// Opaque identifier echoed back after peer authentication.
      public let candidateID: String
      /// Deterministic-CBOR map of profile-specific public parameters.
      public let parametersCBOR: Data

      // MARK: Computed Properties

      /// Underlying transport candidate bridge representation.
      public var binding: RappTransportCandidate {
        RappTransportCandidate(
          profile: profile,
          candidateId: candidateID,
          parametersCbor: parametersCBOR
        )
      }

      // MARK: Lifecycle

      /// Creates a candidate from already-encoded public parameters.
      public init(profile: String, candidateID: String, parametersCBOR: Data) {
        self.profile = profile
        self.candidateID = candidateID
        self.parametersCBOR = parametersCBOR
      }
    }

    /// Authenticated peer facts shown for the explicit pairing decision.
    public struct Peer: Sendable, Equatable {
      // MARK: Properties

      /// User-visible peer label shown during pairing confirmation.
      public let displayName: String
      /// Peer platform label.
      public let platform: String
      /// Exact requester profile list; absent when the peer is the proxy.
      public let requestedProfiles: [String]?
      // swiftlint:disable:previous discouraged_optional_collection

      // MARK: Lifecycle

      internal init(_ hello: RappPeerHello) {
        displayName = hello.displayName
        platform = hello.platform
        requestedProfiles = hello.requestedProfiles
      }
    }

    /// Local endpoint role, driven during pairing and bound into the pair record.
    public enum Role: Sendable, Equatable {
      case requester
      case proxy
    }

    /// Non-secret metadata for a completed pairing.
    public struct PairSummary: Sendable, Equatable {
      // MARK: Properties

      /// Transcript-derived pair identifier.
      public let pairID: Data
      /// Local role permanently bound into the pair record.
      public let role: Role
      /// Exact mutually confirmed profile names.
      public let profiles: [String]
      /// Transport profile bound into the pair.
      public let transportProfile: String
      /// Transport candidate identifier bound into the pair.
      public let candidateID: String
      /// Wall-clock creation time recorded in the pair record.
      public let createdAtMilliseconds: UInt64

      // MARK: Lifecycle

      internal init(_ metadata: RappPairMetadata) {
        pairID = metadata.pairId
        role = metadata.role == .requester ? .requester : .proxy
        profiles = metadata.profiles
        transportProfile = metadata.transportProfile
        candidateID = metadata.candidateId
        createdAtMilliseconds = metadata.createdAtMs
      }
    }

    /// Reason the pairing attempt ended without a completed pair.
    public enum CloseReason: Sendable, Equatable {
      case denied
      case localRequest
      case transportFailure
      case protocolFailure
      case persistenceFailure
      case offerExpired
    }

    /// One externally visible pairing event.
    public enum Event: Sendable, Equatable {
      /// Secret-bearing text intended only for a QR renderer. It must never be
      /// logged, persisted, copied to analytics, or synchronized.
      case offerReady(uri: String)
      /// The same unconsumed requester offer is ready after an
      /// unauthenticated candidate failed. A fresh transport is required.
      case offerRestored(uri: String)
      case reviewPeer(Peer)
      case paired(PairSummary)
      case closed(CloseReason)
    }

    internal enum State: Equatable {
      case offer
      case awaitingRequesterCpace
      case awaitingResponderCpace
      case awaitingRequesterHandshake
      case awaitingResponderHandshake
      case awaitingFinalRequesterHandshake
      case awaitingPeerHello
      case awaitingLocalDecision
      case awaitingPeerConfirmation
      case completed
      case closed
    }

    // MARK: Properties

    /// Delivers pairing events in order until the attempt ends.
    nonisolated public let events: AsyncStream<Event>
    /// Secret-bearing QR text; present only for the requester role.
    nonisolated public let offerURI: String?

    internal let role: Role
    internal let bridge: RappPairingBridge
    internal let vault: RappDeviceVault
    internal var transport: any RappFrameTransport
    internal let candidateID: String
    internal let displayName: String
    internal let platform: String
    internal let clock: RappPlatformClock
    internal let offerDeadlineMilliseconds: UInt64
    internal let pairingCode: String
    internal let continuation: AsyncStream<Event>.Continuation
    internal var state = State.offer
    internal var peer: Peer?
    internal var peerGrantedProfiles: [String] = []
    internal var localConfirmationSent = false
    internal var offerExpiryTask: Task<Void, Never>?

    // MARK: Lifecycle

    internal init(
      role: Role,
      bridge: RappPairingBridge,
      offerURI: String?,
      selectedCandidateID: String,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      clock: RappPlatformClock,
      offerDeadlineMilliseconds: UInt64,
      pairingCode: String
    ) {
      self.role = role
      self.bridge = bridge
      self.offerURI = offerURI
      self.candidateID = selectedCandidateID
      self.displayName = displayName
      self.platform = platform
      self.vault = vault
      self.transport = transport
      self.clock = clock
      self.offerDeadlineMilliseconds = offerDeadlineMilliseconds
      self.pairingCode = pairingCode

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    deinit {
      offerExpiryTask?.cancel()
      continuation.finish()
    }
  }
#endif
