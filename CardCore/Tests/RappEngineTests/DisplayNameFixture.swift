// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// The display names test endpoints give themselves (RAPP v26.11.2 §4.3
/// item 3), in the forms the specification's examples use.
internal enum DisplayNameFixture {
  /// A computer: its operating system and host name.
  internal static let requester = name("macOS - example-host")
  /// A phone: its model name.
  internal static let custodian = name("iPhone 16")

  private static func name(_ text: String) -> RappDisplayName {
    guard let name = RappDisplayName(text) else { preconditionFailure("not a display name") }
    return name
  }
}
