// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A phone in pairing mode showing a code: a real custodian ceremony
  /// behind one in-memory pairing connection.
  internal struct RappTestPairingPhone {
    // MARK: Properties

    internal let custodian: RappPairingCoordinator
    internal let link: RappTestPairingLink
    internal let vault: RappDeviceVault
    /// Everything the ceremony reported, in order.
    internal let outcomes: Task<[RappPairingCoordinator.Event], Never>

    // MARK: Static Functions

    /// A phone showing `code`, keeping its pairing under `servicePrefix`;
    /// its link drops after it sent `dropAfter` frames.
    internal static func showing(
      _ code: String, name: String, servicePrefix: String, dropAfter: Int?
    ) async throws -> Self {
      let phoneVault = RappDeviceVault(accessGroup: nil, servicePrefix: servicePrefix)
      let phoneLink = RappTestPairingLink(servedOffer: nil, dropAfter: dropAfter)
      let ceremony = try RappPairingCoordinator.custodian(
        options: RappPairingCoordinator.Options(
          code: code,
          profiles: RappIntegrationFixtures.profiles,
          transportProfile: RappIntegrationFixtures.transportProfile,
          displayName: name,
          platform: "iOS",
          vault: phoneVault),
        transport: phoneLink.custodianTransport())
      await phoneLink.attach(ceremony)
      let events = ceremony.events
      let reported = Task {
        var seen: [RappPairingCoordinator.Event] = []
        for await event in events {
          seen.append(event)
        }
        return seen
      }
      await ceremony.start()
      return Self(custodian: ceremony, link: phoneLink, vault: phoneVault, outcomes: reported)
    }

    // MARK: Functions

    /// The offer this phone serves.
    internal func offer() async throws -> Data {
      try await custodian.bootstrapOffer()
    }

    /// Ends the phone's ceremony and hands back what it reported.
    internal func close() async -> [RappPairingCoordinator.Event] {
      await custodian.close()
      return await outcomes.value
    }
  }
#endif
