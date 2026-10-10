// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappOperationDriver.OperationKind {
  /// Whether the operation only reads public data.
  ///
  /// Safe reads within one session ride on the session's single consent;
  /// a consequential operation always asks the holder.
  public var isSafeRead: Bool {
    switch self {
    case .inspectCard, .readIdentity,
      .readAuthenticationCertificate, .readSignatureCertificate,
      .readRootCertificate, .readIntermediateCertificate:
      return true

    case .browserAuthenticate, .signDocument, .batchSignDocuments:
      return false
    }
  }
}
