// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for the Bluetooth attribute protocol codes RAPP uses.
///
/// Every constant is named and documented here exactly once; no other
/// production or test file may carry a raw hex literal
/// (`.swiftlint.yml` `unexplained_hex`). Section references are to the
/// Bluetooth Core Specification, Vol 3, Part F.
internal enum BleAttValues {
  /// The first ATT error code the specification reserves for the
  /// application (section 3.4.1.1, application errors run to `0x9F`).
  ///
  /// A RAPP custodian refuses a CPace step 1 write it cannot admit with it
  /// (RAPP v26.10.29 §3.3 item 6, §4.2 "Busy Refusal" item 2).
  internal static let applicationError = 0x80
}
