// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a published identity's token configuration carries: the pairing
/// the identity was offered for, named by its identifier alone.
///
/// The pairing's keys stay in the device vault; the token extension reads
/// them from there through the shared access group when it dials the phone.
public struct PersistentTokenPairing: Equatable, Sendable {
  /// The identifier of the pairing, as the vault stores it.
  public let pairID: Data

  /// The bytes the token configuration holds.
  public var configurationData: Data { pairID }

  /// The pairing `pairID` names; nil unless it is a pair identifier.
  public init?(pairID: Data) {
    guard pairID.count == RappDeviceVault.IdentifierSize.pair else { return nil }
    self.pairID = Data(pairID)
  }

  /// The pairing a token configuration names; nil for configuration data
  /// that is absent or is not a pair identifier.
  public init?(configurationData: Data?) {
    guard let configurationData else { return nil }
    self.init(pairID: configurationData)
  }
}
