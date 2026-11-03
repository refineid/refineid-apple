// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Absent and empty are different bytes on the wire, so the optionality is
// the protocol's own and not a convenience.
// swiftlint:disable discouraged_optional_collection

/// How the peer named itself during the ceremony.
public struct RappPeerHello: Equatable, Sendable {
  /// The name the peer gives itself (RAPP v26.11.2 §4.3 item 3).
  public var displayName: RappDisplayName
  /// The platform the peer runs on.
  public var platform: String
  /// Present on the requester's hello only; absent and empty differ.
  public var requestedProfiles: [String]?

  /// Describes how the peer named itself.
  public init(displayName: RappDisplayName, platform: String, requestedProfiles: [String]?) {
    self.displayName = displayName
    self.platform = platform
    self.requestedProfiles = requestedProfiles
  }
}

// swiftlint:enable discouraged_optional_collection
