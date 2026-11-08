// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  extension RappPairingCoordinator {
    /// A custodian's ceremony with `transport` attached as its pairing
    /// connection, of the first transport profile its offer lists.
    internal static func attachedCustodian(
      options: Options, transport: any RappFrameTransport
    ) async throws -> RappPairingCoordinator {
      let custodian = try custodian(options: options)
      guard let profile = options.transportProfiles.first,
        await custodian.attach(transport, transportProfile: profile)
      else {
        throw RappBindingError.WrongPhase
      }
      return custodian
    }
  }
#endif
