// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Translations between the public vocabulary and the engine's own.
///
/// The public names are the ones callers already wrote against, so they are
/// kept even where the engine spells a value differently.
extension RappOperationResult {
  internal init(_ result: CardOperationResult) {
    switch result {
    case .inspection(let report):
      self.init(
        kind: .inspection, pin1Factory: report.pin1Factory, pin2Factory: report.pin2Factory,
        pin1Attempts: report.pin1Attempts, pin2Attempts: report.pin2Attempts,
        pukAttempts: report.pukAttempts)

    case .identity(let identity):
      self.init(
        kind: .identity, displayName: identity.holderName, personId: identity.cardIdentifier,
        bytes: identity.certificates.first ?? Data())

    case .certificate(let der, let cardSerial):
      self.init(kind: .certificate, personId: cardSerial, bytes: der)

    case .signature(let signature):
      self.init(kind: .signature, bytes: signature)

    case .signatures(let signatures):
      self.init(kind: .signatures, signatures: signatures)
    }
  }
}
