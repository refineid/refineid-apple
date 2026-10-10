// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    // MARK: Factory Options

    /// What one side of a ceremony starts from.
    ///
    /// The custodian's offer names the profiles and the transport; the
    /// requester learns both from the offer it reads.
    public struct Options: Sendable {
      // MARK: Properties

      /// The pairing code, canonicalized before use.
      ///
      /// The custodian generates and shows it; the requester's user types it.
      public let code: String
      /// Credential profiles the offer names and the requester asks for.
      public let profiles: [String]
      /// The registered transport profile the ceremony runs over.
      public let transportProfile: String
      /// User-visible name this endpoint introduces itself with.
      public let displayName: String
      /// Platform label this endpoint introduces itself with.
      public let platform: String
      /// Persistent storage for the completed pair record.
      public let vault: RappDeviceVault
      /// Transport carrying the ceremony's frames.
      public let transport: any RappFrameTransport
      /// Entropy source; defaults to the platform entropy provider.
      public let entropy: RappPlatformEntropy
      /// Clock source; defaults to the platform clock.
      public let clock: RappPlatformClock

      // MARK: Lifecycle

      /// Creates the option set for either role.
      public init(
        code: String,
        profiles: [String],
        transportProfile: String,
        displayName: String,
        platform: String,
        vault: RappDeviceVault,
        transport: any RappFrameTransport,
        entropy: RappPlatformEntropy = RappPlatformEntropy(),
        clock: RappPlatformClock = RappPlatformClock()
      ) {
        self.code = code
        self.profiles = profiles
        self.transportProfile = transportProfile
        self.displayName = displayName
        self.platform = platform
        self.vault = vault
        self.transport = transport
        self.entropy = entropy
        self.clock = clock
      }
    }

    // MARK: Static Factories

    /// The requester side over a frame transport: the user typed the code
    /// the custodian shows, and the offer arrives as the custodian's first
    /// frame after the pairing preamble (RAPP v26.10.9 §4.2).
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not
    ///   exactly six characters of the code alphabet or an unregistered
    ///   transport profile.
    public static func requester(options: Options) throws -> RappPairingCoordinator {
      let code = try canonicalCode(options.code)
      let startedAt = options.clock.monotonicMilliseconds()
      return try coordinator(
        role: .requester, bridge: nil, code: code, options: options, startedAt: startedAt)
    }

    /// The custodian side: this device creates a random offer, shows the
    /// code and holds the card.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code or
    ///   an unregistered transport profile.
    public static func custodian(options: Options) throws -> RappPairingCoordinator {
      let code = try canonicalCode(options.code)
      let startedAt = options.clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.custodianOffer(
        pairingCode: code,
        offerId: try options.entropy.offerID(),
        profiles: options.profiles,
        transportProfiles: [options.transportProfile],
        startedAtMonotonicMs: startedAt)
      return try coordinator(
        role: .proxy, bridge: bridge, code: code, options: options, startedAt: startedAt)
    }

    /// The requester side over BLE, from the offer read off the custodian's
    /// bootstrap characteristic.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code or
    ///   an offer that names no acceptable suite or no entry for the
    ///   transport.
    public static func requester(
      options: Options, bootstrapOffer: Data
    ) throws -> RappPairingCoordinator {
      let code = try canonicalCode(options.code)
      let startedAt = options.clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.bootstrapOffer(
        encodedOffer: bootstrapOffer, transportProfile: options.transportProfile,
        pairingCode: code, startedAtMonotonicMs: startedAt)
      return try coordinator(
        role: .requester, bridge: bridge, code: code, options: options, startedAt: startedAt)
    }

    internal static func canonicalCode(_ raw: String) throws -> String {
      let code = RappPairingCode.normalize(raw)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      return code
    }

    private static func coordinator(
      role: Role, bridge: RappPairingBridge?, code: String, options: Options, startedAt: UInt64
    ) throws -> RappPairingCoordinator {
      guard let candidateID = rappCandidateIdentifier(transportProfile: options.transportProfile)
      else { throw RappBindingError.InvalidInput }
      return RappPairingCoordinator(
        role: role,
        bridge: bridge,
        transportProfile: options.transportProfile,
        candidateID: candidateID,
        pairingCode: code,
        profiles: options.profiles,
        displayName: options.displayName,
        platform: options.platform,
        vault: options.vault,
        transport: options.transport,
        clock: options.clock,
        entropy: options.entropy,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAt, lifetime: RappPairingCode.offerLifetimeMilliseconds))
    }

    internal static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
      let (result, overflow) = startedAt.addingReportingOverflow(lifetime)
      return overflow ? UInt64.max : result
    }
  }
#endif
