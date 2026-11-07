// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Externally fixed values of the trusted-list regime.
internal enum TrustedListValues {
  /// 1 July 2016 00:00:00 UTC as a Unix time: the instant Regulation
  /// (EU) No 910/2014 applies from (its article 52(2)), when ETSI TS
  /// 119 612 annex J moved every service holding a status of Directive
  /// 1999/93/EC to `granted` or `withdrawn`.
  internal static let directiveRegimeEndUnixTime: TimeInterval = 1_467_331_200
}
