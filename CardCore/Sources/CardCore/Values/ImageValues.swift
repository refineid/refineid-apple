// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Byte values that identify an image encoding.
internal enum ImageValues {
  /// Every JPEG marker opens with this byte (ITU-T T.81 B.1.1.3).
  internal static let markerIntroducer: UInt8 = 0xFF

  /// The start-of-image marker's own byte.
  internal static let startOfImage: UInt8 = 0xD8
}
