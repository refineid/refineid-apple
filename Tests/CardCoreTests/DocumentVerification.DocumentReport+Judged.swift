// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@testable import CardCore

extension DocumentVerification.DocumentReport {
  /// The judged signature reports, in document order, unsupported
  /// rows left out.
  internal var judged: [DocumentVerification.SignatureReport] {
    signatures.compactMap { entry in
      guard case .judged(let report) = entry else { return nil }
      return report
    }
  }
}
