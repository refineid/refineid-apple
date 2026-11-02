// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The name a device gives itself in `pairing.hello`.
///
/// A computer names its operating system, a hyphen, and its host name,
/// such as "macOS - example-host". A phone or a tablet names only
/// itself, such as "iPhone 15 Pro Max": the device already says which
/// system it runs. A peer's name is shown as it arrived.
internal enum PeerDisplayName: Equatable, Sendable {
  /// A computer: its operating system and its host name.
  case computer(system: String, host: String)
  /// A phone or a tablet: its own name.
  case handheld(name: String)

  /// The operating system a Mac names.
  internal static let macSystem = "macOS"

  /// Between a computer's system and its host name.
  private static let separator = " - "

  /// The name as sent, the device's name trimmed of surrounding blanks.
  internal var text: String {
    switch self {
    case .computer(let system, let host):
      system + Self.separator + Self.trimmed(host)

    case .handheld(let name):
      Self.trimmed(name)
    }
  }

  private static func trimmed(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
