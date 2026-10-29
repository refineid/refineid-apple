// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which certificate a `read_certificate` selects (RAPP v26.10.29 §9.2,
/// §9.3).
internal enum CertificateKind: String, CaseIterable, Equatable, Sendable {
  case authentication = "authentication"
  case signature = "signature"
}
