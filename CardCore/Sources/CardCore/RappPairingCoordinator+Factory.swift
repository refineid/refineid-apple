// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    // MARK: Factory Options

    /// What one side of a ceremony starts from.
    ///
    /// Both sides must name the same profiles and candidate: the offer hash
    /// binds them, and both peers derive the offer from the code alone.
    public struct Options: Sendable {
      // MARK: Properties

      /// The pairing code, canonicalized before use.
      ///
      /// The custodian generates and shows it; the requester's user types it.
      public let code: String
      /// Credential profiles the offer names and the requester asks for.
      public let profiles: [String]
      /// The one transport candidate the offer advertises.
      public let candidate: TransportCandidate
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
        candidate: TransportCandidate,
        displayName: String,
        platform: String,
        vault: RappDeviceVault,
        transport: any RappFrameTransport,
        entropy: RappPlatformEntropy = RappPlatformEntropy(),
        clock: RappPlatformClock = RappPlatformClock()
      ) {
        self.code = code
        self.profiles = profiles
        self.candidate = candidate
        self.displayName = displayName
        self.platform = platform
        self.vault = vault
        self.transport = transport
        self.entropy = entropy
        self.clock = clock
      }
    }

    // MARK: Static Factories

    /// The requester side: the user typed the code the custodian shows.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not
    ///   exactly six characters of the code alphabet.
    public static func requester(options: Options) throws -> RappPairingCoordinator {
      try make(role: .requester, options: options)
    }

    /// The custodian side: this device shows the code and holds the card.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code.
    public static func custodian(options: Options) throws -> RappPairingCoordinator {
      try make(role: .proxy, options: options)
    }

    private static func make(role: Role, options: Options) throws -> RappPairingCoordinator {
      let code = RappPairingCode.normalize(options.code)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      let startedAt = options.clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.codeOffer(
        role: role == .requester ? .requester : .proxy,
        pairingCode: code,
        profiles: options.profiles,
        transports: [options.candidate.binding],
        offerTtlMs: RappPairingCode.offerLifetimeMilliseconds,
        startedAtMonotonicMs: startedAt
      )
      return RappPairingCoordinator(
        role: role,
        bridge: bridge,
        candidateID: options.candidate.candidateID,
        profiles: options.profiles,
        displayName: options.displayName,
        platform: options.platform,
        vault: options.vault,
        transport: options.transport,
        clock: options.clock,
        entropy: options.entropy,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAt, lifetime: RappPairingCode.offerLifetimeMilliseconds)
      )
    }

    internal static func deadline(startedAt: UInt64, lifetime: UInt64) -> UInt64 {
      let (result, overflow) = startedAt.addingReportingOverflow(lifetime)
      return overflow ? UInt64.max : result
    }
  }
#endif
