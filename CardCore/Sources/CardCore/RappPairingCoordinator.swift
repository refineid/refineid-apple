// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Drives one RAPP v26.10.1 pairing ceremony over one transport.
  ///
  /// The custodian shows a pairing code and waits; the requester types it
  /// and connects. CPace KC2 proves both hold the code, Noise_XXpsk3 binds
  /// fresh pair keys, and the custodian grants the requested profiles
  /// without a separate approval: entering the code is the authorization.
  /// The engine owns every secret; this actor moves frames and reports
  /// progress.
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
      case localRequest
      case transportFailure
      case protocolFailure
      case persistenceFailure
      case offerExpired
      /// Three wrong codes destroyed the custodian's offer.
      case attemptsExhausted
    }

    /// One externally visible pairing event.
    public enum Event: Sendable, Equatable {
      /// A custodian attempt failed and the same offer awaits a new
      /// connection; the transport must be replaced before it can answer.
      case offerRestored
      /// The peer's authenticated introduction, for naming the pairing.
      case peerIntroduced(Peer)
      case paired(PairSummary)
      case closed(CloseReason)
    }

    internal enum State: Equatable {
      case offer
      case requesterAwaitingStepTwo
      case requesterAwaitingHandshakeTwo
      case custodianAwaitingStepOne
      case custodianAwaitingStepThree
      case custodianAwaitingHandshakeOne
      case custodianAwaitingHandshakeThree
      case awaitingPeerHello
      case awaitingPeerConfirmation
      case completed
      case closed
    }

    // MARK: Properties

    /// Delivers pairing events in order until the attempt ends.
    nonisolated public let events: AsyncStream<Event>

    internal let role: Role
    internal let bridge: RappPairingBridge
    internal let vault: RappDeviceVault
    internal var transport: any RappFrameTransport
    internal let candidateID: String
    internal let profiles: [String]
    internal let displayName: String
    internal let platform: String
    internal let clock: RappPlatformClock
    internal let entropy: RappPlatformEntropy
    internal let offerDeadlineMilliseconds: UInt64
    internal let continuation: AsyncStream<Event>.Continuation
    internal var state = State.offer
    internal var deadlineTask: Task<Void, Never>?

    // MARK: Lifecycle

    internal init(
      role: Role,
      bridge: RappPairingBridge,
      candidateID: String,
      profiles: [String],
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      clock: RappPlatformClock,
      entropy: RappPlatformEntropy,
      offerDeadlineMilliseconds: UInt64
    ) {
      self.role = role
      self.bridge = bridge
      self.candidateID = candidateID
      self.profiles = profiles
      self.displayName = displayName
      self.platform = platform
      self.vault = vault
      self.transport = transport
      self.clock = clock
      self.entropy = entropy
      self.offerDeadlineMilliseconds = offerDeadlineMilliseconds

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    deinit {
      deadlineTask?.cancel()
      continuation.finish()
    }
  }
#endif
