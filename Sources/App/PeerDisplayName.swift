// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The name a device gives itself in `pairing.hello`.
///
/// Its operating system, a hyphen, and its own name, such as
/// "macOS - example-host". A peer's name is shown as it arrived.
internal struct PeerDisplayName: Equatable, Sendable {
  /// The operating system a Mac names.
  internal static let macSystem = "macOS"
  /// The operating system an iPhone names.
  internal static let iPhoneSystem = "iOS"
  /// The operating system an iPad names.
  internal static let iPadSystem = "iPadOS"

  /// Between the system and the device's name.
  private static let separator = " - "

  /// The operating system.
  internal let system: String
  /// The device's own name: a Mac's local host name, a phone's or a
  /// tablet's device name.
  internal let host: String

  /// The name as sent, the device's name trimmed of surrounding blanks.
  internal var text: String {
    system + Self.separator + host.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
