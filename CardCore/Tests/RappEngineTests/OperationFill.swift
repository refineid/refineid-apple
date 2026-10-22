// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The byte each fixture is filled with, distinct so a mix-up shows.
internal enum OperationFill {
  internal static let operationIdentifier: UInt8 = 0x44
  internal static let otherOperation: UInt8 = 0x55
  internal static let digest: UInt8 = 0x66
  internal static let signature: UInt8 = 0x88
  internal static let certificate: UInt8 = 0x99
  internal static let challenge: UInt8 = 0xC7

  /// Sizes the fixtures are built at.
  internal static let signatureLength = 64
  internal static let certificateLength = 300
}
