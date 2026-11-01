// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One PACE suite a card publishes: `id-PACE-ECDH-GM-AES-CBC-CMAC-256` or
/// `id-PACE-ECDH-IM-AES-CBC-CMAC-256`, `PACEInfo` version 2, over a
/// standardized domain parameter from ``PaceDomain``.
///
/// Exists only through ``CardAccess/parse(_:)``, so a value is proof that
/// the card listed the suite.
public struct PaceInfo: Equatable, Sendable {
  /// The mapping the suite names.
  public let mapping: PaceMapping

  /// The domain parameter the suite names.
  public let domain: PaceDomain

  /// The protocol object-identifier body MSE:Set AT and the authentication
  /// token carry (BSI TR-03110-3 sections A.2.4 and B.14.1).
  internal var protocolOidBody: [UInt8] {
    switch mapping {
    case .generic:
      PaceValues.protocolOidBody

    case .integrated:
      PaceValues.integratedMappingOidBody
    }
  }

  internal init(mapping: PaceMapping, domain: PaceDomain) {
    self.mapping = mapping
    self.domain = domain
  }
}
