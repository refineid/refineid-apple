// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ResultResponse {
  /// The `response` map one card answer becomes (RAPP v26.10.21 §9).
  ///
  /// The response names no variant: the requester reads it against the
  /// operation it asked for.
  internal init(_ result: CardOperationResult) {
    switch result {
    case .inspection(let answerToReset):
      self.init(fields: [
        "atr": .bytes(answerToReset),
        "supported_profiles": .array(ProfileName.allCases.map { .text($0.rawValue) }),
      ])

    case .identity(let identity):
      var map: [String: WireValue] = [
        "card_holder_name": .text(identity.holderName),
        "card_id": .text(identity.cardIdentifier),
        "issuance_date": .text(identity.issuanceDate),
        "expiration_date": .text(identity.expirationDate),
        "certificates": .array(identity.certificates.map(WireValue.bytes)),
      ]
      if let tokenDisplayName = identity.tokenDisplayName {
        map["token_display_name"] = .text(tokenDisplayName)
      }
      self.init(fields: map)

    case .certificate(let bytes):
      self.init(fields: ["certificate": .bytes(bytes)])

    case .signature(let bytes):
      self.init(fields: ["signature": .bytes(bytes)])

    case .signatures(let signatures):
      self.init(fields: ["signatures": .array(signatures.map(WireValue.bytes))])
    }
  }

  /// This response read as the answer to `operation`.
  internal func typed(for operation: CardOperation) throws -> CardOperationResult {
    var map = fields
    let result: CardOperationResult
    switch operation {
    case .inspectCard:
      let answerToReset = try takeOperationBytes(&map, "atr")
      _ = try takeOperationArray(&map, "supported_profiles")
      result = .inspection(answerToReset: answerToReset)

    case .readIdentity:
      let identity = try CardIdentity(
        holderName: try takeOperationText(&map, "card_holder_name"),
        cardIdentifier: try takeOperationText(&map, "card_id"),
        issuanceDate: try takeOperationText(&map, "issuance_date"),
        expirationDate: try takeOperationText(&map, "expiration_date"),
        certificates: try takeOperationBytesArray(&map, "certificates"),
        tokenDisplayName: map["token_display_name"] == nil
          ? nil : try takeOperationText(&map, "token_display_name"))
      result = .identity(identity)

    case .readCertificate:
      result = .certificate(try takeOperationBytes(&map, "certificate"))

    case .browserAuthenticate, .signDocument:
      result = .signature(try takeOperationBytes(&map, "signature"))

    case .batchSignDocuments:
      let signatures = try takeOperationBytesArray(&map, "signatures")
      guard signatures.allSatisfy({ !$0.isEmpty }) else {
        throw CardOperationError.invalidField(field: "signatures")
      }
      result = .signatures(signatures)
    }
    guard map.isEmpty else { throw CardOperationError.unexpectedField }
    return result
  }
}
