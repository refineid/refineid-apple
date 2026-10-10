// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CardOperationResult {
  /// Whether this output can answer the operation that was requested.
  internal func answers(_ operation: CardOperation) -> Bool {
    switch (self, operation) {
    case (.inspection, .inspectCard),
      (.identity, .readIdentity),
      (.certificate, .readCertificate),
      (.signature, .browserAuthenticate),
      (.signature, .signDocument):
      true

    case (.signatures(let signatures), .batchSignDocuments(_, _, _, let digests)):
      signatures.count == digests.count

    default:
      false
    }
  }
}
