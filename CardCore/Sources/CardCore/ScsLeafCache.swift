// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Card-serial-bound cache of the authentication and qualified leaf
/// certificates read for the SCS signing backend.
///
/// Binding cached leaves to `ChipSerial` (`EF.TokenInfo`) ensures that
/// swapping cards invalidates cached certificates and holder names
/// immediately rather than naming the previous card's holder on a
/// prompt signed by the new card.
public struct ScsLeafCache: Sendable {
  private var chipSerial: ChipSerial?
  private var authenticationLeaf: Data?
  private var qualifiedLeaf: Data?

  /// Creates an empty leaf cache bound to no card.
  public init() {
    // Starts unbound until a card session reports its ChipSerial.
  }

  /// Returns the cached leaf for `purpose` only when `serial` matches
  /// the bound card; a different serial invalidates both slots first.
  public mutating func cachedLeaf(
    for purpose: ScsSignPurpose,
    serial: ChipSerial
  ) -> Data? {
    if chipSerial != serial {
      chipSerial = serial
      authenticationLeaf = nil
      qualifiedLeaf = nil
      return nil
    }
    switch purpose {
    case .authentication:
      return authenticationLeaf

    case .qualified:
      return qualifiedLeaf
    }
  }

  /// Stores `leaf` for `purpose` bound to `serial`, evicting any leaf
  /// cached from a different card.
  public mutating func store(
    leaf: Data,
    for purpose: ScsSignPurpose,
    serial: ChipSerial
  ) {
    if chipSerial != serial {
      chipSerial = serial
      authenticationLeaf = nil
      qualifiedLeaf = nil
    }
    switch purpose {
    case .authentication:
      authenticationLeaf = leaf

    case .qualified:
      qualifiedLeaf = leaf
    }
  }

  /// Drops all cached leaves and card binding on card removal or server
  /// stop.
  public mutating func invalidate() {
    chipSerial = nil
    authenticationLeaf = nil
    qualifiedLeaf = nil
  }
}
