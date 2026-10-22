// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Translations between the public vocabulary and the engine's own.
extension RappOperationResult {
  internal init(_ result: CardOperationResult) {
    switch result {
    case .inspection(let answerToReset):
      self = .inspection(answerToReset: answerToReset)

    case .identity(let identity):
      self = .identity(RappCardIdentity(identity))

    case .certificate(let der):
      self = .certificate(der)

    case .signature(let signature):
      self = .signature(signature)

    case .signatures(let signatures):
      self = .signatures(signatures)
    }
  }
}
