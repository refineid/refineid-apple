// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A service instance name's instance portion: what withdrawal hints bind
/// to.
internal struct InstanceName: Equatable {
  internal static let maximumSize = 63

  private static let serviceSuffixes = ["._tcp", "._udp", ".local", ".local."]

  internal let bytes: Data

  internal init?(_ name: String) {
    let octets = Data(name.utf8)
    let lowered = name.lowercased()
    guard !octets.isEmpty, octets.count <= Self.maximumSize,
      !Self.serviceSuffixes.contains(where: { lowered.hasSuffix($0) })
    else { return nil }
    bytes = octets
  }
}
