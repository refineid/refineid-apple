// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappOperationDriver.OperationKind {
  /// Whether the operation only reads: it commands no private key and no
  /// PIN, and asks the holder nothing (RAPP v26.10.22 §8.2 item 6).
  public var isSafeRead: Bool {
    switch self {
    case .inspectCard, .readIdentity, .readAuthenticationCertificate, .readSignatureCertificate:
      return true

    case .browserAuthenticate, .signDocument, .batchSignDocuments:
      return false
    }
  }
}
