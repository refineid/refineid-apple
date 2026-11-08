// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    // MARK: Factory Options

    /// What one side of a ceremony starts from, whichever connection
    /// carries it.
    ///
    /// The custodian's offer names the profiles and the transports; the
    /// requester learns both from the offer it reads.
    public struct Options: Sendable {
      // MARK: Properties

      /// The pairing code, canonicalized before use.
      ///
      /// The custodian generates and shows it; the requester's user types it.
      public let code: String
      /// Credential profiles the offer names and the requester asks for.
      public let profiles: [String]
      /// The registered transport profiles this side pairs over: the
      /// custodian's offer lists each (RAPP v26.11.8 §4.2), and a requester
      /// runs the ceremony on a connection of any of them.
      public let transportProfiles: [String]
      /// User-visible name this endpoint introduces itself with.
      public let displayName: RappDisplayName
      /// Platform label this endpoint introduces itself with.
      public let platform: String
      /// Persistent storage for the completed pair record.
      public let vault: RappDeviceVault
      /// Entropy source; defaults to the platform entropy provider.
      public let entropy: RappPlatformEntropy
      /// Clock source; defaults to the platform clock.
      public let clock: RappPlatformClock

      // MARK: Lifecycle

      /// Creates the option set for either role.
      public init(
        code: String,
        profiles: [String],
        transportProfiles: [String],
        displayName: RappDisplayName,
        platform: String,
        vault: RappDeviceVault,
        entropy: RappPlatformEntropy = RappPlatformEntropy(),
        clock: RappPlatformClock = RappPlatformClock()
      ) {
        self.code = code
        self.profiles = profiles
        self.transportProfiles = transportProfiles
        self.displayName = displayName
        self.platform = platform
        self.vault = vault
        self.entropy = entropy
        self.clock = clock
      }
    }

    // MARK: Static Factories

    /// The custodian side: this device creates one random offer for every
    /// transport in `options`, shows the code and holds the card.
    ///
    /// Each pairing connection is attached with
    /// ``attach(_:transportProfile:)`` before ``transportConnected()``.
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
        transportProfiles: options.transportProfiles,
        startedAtMonotonicMs: startedAt)
      return RappPairingCoordinator(
        role: .proxy,
        bridge: bridge,
        binding: nil,
        options: options,
        offerDeadlineMilliseconds: deadline(startedAt: startedAt, lifetime: rappOfferTtlMs()))
    }

    /// The requester side over `transport`, a connection of
    /// `transportProfile`, from the bridge built on the offer that
    /// connection served through its bootstrap: the custodian's first
    /// stream frame or the BLE bootstrap characteristic (RAPP v26.11.8
    /// §4.2, Bootstrap Read Flow).
    ///
    /// `bootstrap` is the requester's ``RappPairingBridge`` over that offer,
    /// built with the typed code; CPace begins once the transport is
    /// connected.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code, or
    ///   a transport profile that is unregistered or not one of `options`.
    public static func requester(
      options: Options,
      transport: any RappFrameTransport,
      transportProfile: String,
      bootstrap: RappPairingBridge
    ) throws -> RappPairingCoordinator {
      _ = try canonicalCode(options.code)
      guard options.transportProfiles.contains(transportProfile) else {
        throw RappBindingError.InvalidInput
      }
      return RappPairingCoordinator(
        role: .requester,
        bridge: bootstrap,
        binding: try Binding(transport: transport, transportProfile: transportProfile),
        options: options,
        offerDeadlineMilliseconds: deadline(
          startedAt: options.clock.monotonicMilliseconds(), lifetime: rappOfferTtlMs()))
    }

    internal static func canonicalCode(_ raw: String) throws -> String {
      let code = RappPairingCode.normalize(raw)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      return code
    }

    internal static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
      let (result, overflow) = startedAt.addingReportingOverflow(lifetime)
      return overflow ? UInt64.max : result
    }
  }
#endif
