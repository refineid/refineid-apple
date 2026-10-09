// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    /// The BLE candidate the direct proximity profile binds (RAPP v26.10.1
    /// §4.2); its parameters live in the offer the custodian serves.
    public static var bleCandidate: TransportCandidate {
      TransportCandidate(
        profile: RappBleGattProfile.name, candidateID: RappBleGattProfile.candidateId,
        parametersCBOR: Data())
    }

    /// The custodian side over BLE: a fresh random offer identifier, served
    /// to the requester through the bootstrap characteristic.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code.
    public static func bleCustodian(options: Options) throws -> RappPairingCoordinator {
      let code = try canonicalCode(options.code)
      let startedAt = options.clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.bleOffer(
        pairingCode: code,
        offerId: try options.entropy.offerID(),
        profiles: options.profiles,
        startedAtMonotonicMs: startedAt)
      return bleCoordinator(role: .proxy, bridge: bridge, options: options, startedAt: startedAt)
    }

    /// The requester side over BLE, from the offer read off the custodian's
    /// bootstrap characteristic.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a malformed code or
    ///   an offer that names no acceptable suite or no BLE candidate.
    public static func bleRequester(
      options: Options, bootstrapOffer: Data
    ) throws -> RappPairingCoordinator {
      let code = try canonicalCode(options.code)
      let startedAt = options.clock.monotonicMilliseconds()
      let bridge = try RappPairingBridge.bootstrapOffer(
        encodedOffer: bootstrapOffer, pairingCode: code, startedAtMonotonicMs: startedAt)
      return bleCoordinator(
        role: .requester, bridge: bridge, options: options, startedAt: startedAt)
    }

    private static func canonicalCode(_ raw: String) throws -> String {
      let code = RappPairingCode.normalize(raw)
      guard RappPairingCode.isValid(code) else { throw RappBindingError.InvalidInput }
      return code
    }

    private static func bleCoordinator(
      role: Role, bridge: RappPairingBridge, options: Options, startedAt: UInt64
    ) -> RappPairingCoordinator {
      RappPairingCoordinator(
        role: role,
        bridge: bridge,
        candidateID: RappBleGattProfile.candidateId,
        profiles: options.profiles,
        displayName: options.displayName,
        platform: options.platform,
        vault: options.vault,
        transport: options.transport,
        clock: options.clock,
        entropy: options.entropy,
        offerDeadlineMilliseconds: deadline(
          startedAt: startedAt, lifetime: RappBleGattProfile.offerLifetimeMilliseconds))
    }

    /// The offer the custodian serves on the bootstrap characteristic.
    nonisolated public func bootstrapOffer() throws -> Data {
      try bridge.encodedOffer()
    }
  }
#endif
