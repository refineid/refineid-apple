// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Translations between the public vocabulary and the engine's own.
///
/// The public names are the ones callers already wrote against, so they are
/// kept even where the engine spells a value differently.
extension RappOperationKind {
  internal init(_ operation: CardOperation) {
    switch operation {
    case .inspectCard:
      self = .inspectCard

    case .readIdentity:
      self = .readIdentity

    case .readCertificate(let kind):
      switch kind {
      case .authentication:
        self = .readAuthenticationCertificate
      case .signature:
        self = .readSignatureCertificate
      case .rootCa:
        self = .readRootCertificate
      case .intermediateCa:
        self = .readIntermediateCertificate
      }

    case .browserAuthenticate:
      self = .browserAuthenticate

    case .signDocument:
      self = .signDocument

    case .batchSignDocuments:
      self = .batchSignDocuments
    }
  }
}
