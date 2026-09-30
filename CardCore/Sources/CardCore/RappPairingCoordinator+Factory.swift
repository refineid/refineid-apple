// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    // MARK: Requester Factory Options

    /// Configuration for the requester role factory.
    public struct RequesterOptions: Sendable {
      // MARK: Properties

      /// Credential profiles the requester is willing to pair on.
      public let profiles: [String]
      /// All transport candidates the requester exposes.
      public let candidates: [TransportCandidate]
      /// Candidate identifier the requester selected for this attempt.
      public let selectedCandidateID: String
      /// Duration in milliseconds after which the unredeemed offer expires.
      public let offerLifetimeMilliseconds: UInt64
      /// User-visible name shown to the proxy during review.
      public let displayName: String
      /// Platform label sent to the proxy during review.
      public let platform: String
      /// Persistent storage for the completed pair record.
      public let vault: RappDeviceVault
      /// Connected transport ready to carry Noise frames.
      public let transport: any RappFrameTransport
      /// Entropy source; defaults to the platform entropy provider.
      public let entropy: RappPlatformEntropy
      /// Clock source; defaults to the platform clock.
      public let clock: RappPlatformClock
      /// Six-digit code the two peers key the CPace PAKE on.
      public let code: String

      // MARK: Lifecycle

      /// Creates the full requester option set.
      public init(
        profiles: [String],
        candidates: [TransportCandidate],
        selectedCandidateID: String,
        offerLifetimeMilliseconds: UInt64,
        displayName: String,
        platform: String,
        vault: RappDeviceVault,
        transport: any RappFrameTransport,
        code: String,
        entropy: RappPlatformEntropy = RappPlatformEntropy(),
        clock: RappPlatformClock = RappPlatformClock()
      ) {
        self.profiles = profiles
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
        self.offerLifetimeMilliseconds = offerLifetimeMilliseconds
        self.displayName = displayName
        self.platform = platform
        self.vault = vault
        self.transport = transport
        self.entropy = entropy
        self.clock = clock
        self.code = code
      }
    }

    // MARK: Proxy Factory Options

    /// Configuration for the proxy role factory.
    public struct ProxyOptions: Sendable {
      // MARK: Properties

      /// Raw URI scanned from the requester QR code.
      public let scannedOfferURI: String
      /// Candidate identifier the proxy selected for this attempt.
      public let selectedCandidateID: String
      /// User-visible name shown to the requester during review.
      public let displayName: String
      /// Platform label sent to the requester during review.
      public let platform: String
      /// Persistent storage for the completed pair record.
      public let vault: RappDeviceVault
      /// Connected transport ready to carry Noise frames.
      public let transport: any RappFrameTransport
      /// Clock source; defaults to the platform clock.
      public let clock: RappPlatformClock
      /// Six-digit code the two peers key the CPace PAKE on.
      public let code: String

      // MARK: Lifecycle

      /// Creates the full proxy option set.
      public init(
        scannedOfferURI: String,
        selectedCandidateID: String,
        displayName: String,
        platform: String,
        vault: RappDeviceVault,
        transport: any RappFrameTransport,
        code: String,
        clock: RappPlatformClock = RappPlatformClock()
      ) {
        self.scannedOfferURI = scannedOfferURI
        self.selectedCandidateID = selectedCandidateID
        self.displayName = displayName
        self.platform = platform
        self.vault = vault
        self.transport = transport
        self.clock = clock
        self.code = code
      }
    }

    // MARK: Static Factories

    /// Creates the requester side owning a fresh one-use offer.
    public static func requester(options: RequesterOptions) throws -> RappPairingCoordinator {
      let startedAt = options.clock.monotonicMilliseconds()
      let code = RappPairingCode.normalize(options.code)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      let offerId = RappPairingCode.offerIdentifier(for: code)
      let pairingSecret = RappPairingCode.pairingSecret(for: code)
      let bridge = try RappPairingBridge.createRequesterOffer(
        offerId: offerId,
        pairingSecret: pairingSecret,
        profiles: options.profiles,
        transports: options.candidates.map(\.binding),
        offerTtlMs: options.offerLifetimeMilliseconds,
        startedAtMonotonicMs: startedAt
      )
      return RappPairingCoordinator(
        role: .requester,
        bridge: bridge,
        offerURI: try bridge.offerUri(nowMonotonicMs: startedAt),
        selectedCandidateID: options.selectedCandidateID,
        displayName: options.displayName,
        platform: options.platform,
        vault: options.vault,
        transport: options.transport,
        clock: options.clock,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAt, lifetime: options.offerLifetimeMilliseconds
        ),
        pairingCode: code
      )
    }

    /// Creates the proxy side from a scanned requester offer.
    public static func proxy(options: ProxyOptions) throws -> RappPairingCoordinator {
      let startedAt = options.clock.monotonicMilliseconds()
      let code = RappPairingCode.normalize(options.code)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      let bridge = try RappPairingBridge.fromScannedOffer(
        uri: options.scannedOfferURI,
        startedAtMonotonicMs: startedAt
      )
      return RappPairingCoordinator(
        role: .proxy,
        bridge: bridge,
        offerURI: nil,
        selectedCandidateID: options.selectedCandidateID,
        displayName: options.displayName,
        platform: options.platform,
        vault: options.vault,
        transport: options.transport,
        clock: options.clock,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAt, lifetime: bridge.offerTtlMs()
        ),
        pairingCode: code
      )
    }

    // MARK: Convenience Overloads

    /// Creates the requester side owning a fresh one-use offer with discrete parameters.
    public static func requester(  // swiftlint:disable:this function_parameter_count
      profiles: [String],
      candidates: [TransportCandidate],
      selectedCandidateID: String,
      offerLifetimeMilliseconds: UInt64,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      code: String,
      entropy: RappPlatformEntropy = RappPlatformEntropy(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws -> RappPairingCoordinator {
      try requester(
        options: RequesterOptions(
          profiles: profiles,
          candidates: candidates,
          selectedCandidateID: selectedCandidateID,
          offerLifetimeMilliseconds: offerLifetimeMilliseconds,
          displayName: displayName,
          platform: platform,
          vault: vault,
          transport: transport,
          code: code,
          entropy: entropy,
          clock: clock
        )
      )
    }

    /// Creates the proxy side from a scanned requester offer with discrete parameters.
    public static func proxy(  // swiftlint:disable:this function_parameter_count
      scannedOfferURI: String,
      selectedCandidateID: String,
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      code: String,
      clock: RappPlatformClock = RappPlatformClock()
    ) throws -> RappPairingCoordinator {
      try proxy(
        options: ProxyOptions(
          scannedOfferURI: scannedOfferURI,
          selectedCandidateID: selectedCandidateID,
          displayName: displayName,
          platform: platform,
          vault: vault,
          transport: transport,
          code: code,
          clock: clock
        )
      )
    }

    internal static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
      let (result, overflow) = startedAt.addingReportingOverflow(lifetime)
      return overflow ? UInt64.max : result
    }
  }
#endif
