// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for SEC1 elliptic-curve point encoding values.
///
/// Source: SEC 1 v2.0 section 2.3.3, "Elliptic-Curve-Point-to-Octet-String
/// Conversion". Only the uncompressed form is used: the FINEID card and the
/// PACE protocol exchange public points as `04 || X || Y`.
internal enum Sec1Values {
  /// The leading octet marking an uncompressed point, `04 || X || Y`.
  internal static let uncompressedPointTag: UInt8 = 0x04

  /// The length of that leading octet.
  internal static let pointTagLength: Int = 1

  /// The coordinates an uncompressed point carries, `X` and `Y`
  /// (SEC 1 v2 section 2.3.3).
  internal static let uncompressedCoordinateCount: Int = 2
}
