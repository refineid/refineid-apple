// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Bounds the human-readable context an operation may carry.
internal enum OperationLimit {
  /// Byte length of one name an authorizer shows: `origin` (RAPP v26.11.8
  /// §9.2), `document_name`, an entry of `document_names` or of
  /// `contained_files` (§9.3), `tstr .size (1..256)`.
  internal static let displayNameBytes = 1...256
  /// The directory an ASiC-E container reserves for its manifest and
  /// signatures; no entry of `contained_files` lies under it (§9.3).
  internal static let containerReservedDirectory = "META-INF/"
}
