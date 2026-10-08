// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

internal func decodedMap(_ bytes: Data) throws -> [String: WireValue] {
  guard let decoded = try? decodeDeterministicCbor(bytes), case .map(let map) = decoded else {
    throw PairRecordError.invalidInput
  }
  return map
}

/// Encodes a card result as the journal stores it.
///
/// The journal names the variant `kind` and carries certificate bytes under
/// `bytes`, while the wire body names the variant `type` and uses `der`. The
/// two encodings are deliberately separate and must not be interchanged.
internal func journalResultValue(_ result: CardOperationResult) -> WireValue {
  switch result {
  case .inspection(let inspection):
    return .map([
      "kind": .text("inspection"),
      "pin1_factory": .boolean(inspection.pin1Factory),
      "pin2_factory": .boolean(inspection.pin2Factory),
      "pin1_attempts": attemptValue(inspection.pin1Attempts),
      "pin2_attempts": attemptValue(inspection.pin2Attempts),
      "puk_attempts": attemptValue(inspection.pukAttempts),
    ])

  case .identity(let identity):
    var map: [String: WireValue] = ["kind": .text("identity")]
    for (key, value) in wireResponse(.identity(identity)) {
      map[key] = value
    }
    return .map(map)

  case .certificate(let bytes, let cardSerial):
    var map: [String: WireValue] = ["kind": .text("certificate"), "bytes": .bytes(bytes)]
    if let cardSerial {
      map["card_serial"] = .text(cardSerial)
    }
    return .map(map)

  case .signature(let bytes):
    return .map(["kind": .text("signature"), "bytes": .bytes(bytes)])
  }
}

internal func journalResultFrom(_ value: WireValue) throws -> CardOperationResult {
  guard case .map(var map) = value else { throw PairRecordError.invalidInput }
  let result: CardOperationResult
  switch try takeText(&map, "kind") {
  case "inspection":
    result = .inspection(try inspectionFrom(&map))

  case "identity":
    let identity = try cardResult(fromResponse: map, for: .readIdentity)
    map = [:]
    result = identity

  case "certificate":
    let bytes = try takeBytes(&map, "bytes")
    let cardSerial: String?
    if let val = map.removeValue(forKey: "card_serial") {
      guard case .text(let str) = val else { throw PairRecordError.invalidInput }
      cardSerial = str
    } else {
      cardSerial = nil
    }
    result = .certificate(bytes, cardSerial: cardSerial)

  case "signature":
    result = .signature(try takeBytes(&map, "bytes"))

  default:
    throw PairRecordError.invalidInput
  }
  guard map.isEmpty else { throw PairRecordError.invalidInput }
  return result
}

/// The `response` map one card answer becomes (RAPP v26.10.1 §9).
///
/// The response names no variant: the requester reads it against the
/// operation it asked for. The factory flags and counters of an inspection
/// travel beside the registered fields.
internal func wireResponse(_ result: CardOperationResult) -> [String: WireValue] {
  switch result {
  case .inspection(let inspection):
    return [
      "card_present": .boolean(true),
      "atr": .bytes(inspection.answerToReset),
      "supported_profiles": .array(ProfileName.allCases.map { .text($0.rawValue) }),
      "pin1_factory": .boolean(inspection.pin1Factory),
      "pin2_factory": .boolean(inspection.pin2Factory),
      "pin1_attempts": attemptValue(inspection.pin1Attempts),
      "pin2_attempts": attemptValue(inspection.pin2Attempts),
      "puk_attempts": attemptValue(inspection.pukAttempts),
    ]

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
    return map

  case .certificate(let bytes, let cardSerial):
    var map: [String: WireValue] = ["certificate": .bytes(bytes)]
    if let cardSerial {
      map["card_serial"] = .text(cardSerial)
    }
    return map

  case .signature(let bytes):
    return ["signature": .bytes(bytes)]
  }
}

/// Reads a `response` map as the answer to `operation`.
internal func cardResult(
  fromResponse response: [String: WireValue], for operation: CardOperation
) throws -> CardOperationResult {
  var map = response
  switch operation {
  case .inspectCard:
    guard try takeBoolean(&map, "card_present") else { throw PairRecordError.invalidInput }
    let answerToReset = try takeBytes(&map, "atr")
    _ = try takeArray(&map, "supported_profiles")
    var inspection = CardInspection(
      pin1Factory: try takeBoolean(&map, "pin1_factory", absent: false),
      pin2Factory: try takeBoolean(&map, "pin2_factory", absent: false),
      pin1Attempts: try takeOptionalAttempt(&map, "pin1_attempts"),
      pin2Attempts: try takeOptionalAttempt(&map, "pin2_attempts"),
      pukAttempts: try takeOptionalAttempt(&map, "puk_attempts"))
    inspection.answerToReset = answerToReset
    return .inspection(inspection)

  case .readIdentity:
    let identity = CardIdentity(
      holderName: try takeText(&map, "card_holder_name"),
      cardIdentifier: try takeText(&map, "card_id"),
      issuanceDate: try takeText(&map, "issuance_date"),
      expirationDate: try takeText(&map, "expiration_date"),
      certificates: try takeArray(&map, "certificates").map { value in
        guard case .bytes(let certificate) = value else { throw PairRecordError.invalidInput }
        return certificate
      },
      tokenDisplayName: try takeOptionalText(&map, "token_display_name"))
    try identity.validate()
    return .identity(identity)

  case .readCertificate:
    let certificate = try takeBytes(&map, "certificate")
    return .certificate(certificate, cardSerial: try takeOptionalText(&map, "card_serial"))

  case .browserAuthenticate, .signDocument:
    return .signature(try takeBytes(&map, "signature"))
  }
}

/// A boolean the map may omit, read as `absent` when it does.
internal func takeBoolean(
  _ map: inout [String: WireValue], _ field: String, absent: Bool
) throws -> Bool {
  guard map[field] != nil else { return absent }
  return try takeBoolean(&map, field)
}

private func takeOptionalText(
  _ map: inout [String: WireValue], _ field: String
) throws -> String? {
  switch map.removeValue(forKey: field) {
  case .none:
    return nil

  case .some(.text(let value)):
    return value

  case .some:
    throw PairRecordError.invalidInput
  }
}

private func takeOptionalAttempt(
  _ map: inout [String: WireValue], _ field: String
) throws -> UInt8? {
  guard map[field] != nil else { return nil }
  return try takeAttempt(&map, field)
}

private func takeArray(_ map: inout [String: WireValue], _ field: String) throws -> [WireValue] {
  guard case .array(let values)? = map.removeValue(forKey: field) else {
    throw PairRecordError.invalidInput
  }
  return values
}

internal func inspectionFrom(_ map: inout [String: WireValue]) throws -> CardInspection {
  CardInspection(
    pin1Factory: try takeBoolean(&map, "pin1_factory"),
    pin2Factory: try takeBoolean(&map, "pin2_factory"),
    pin1Attempts: try takeAttempt(&map, "pin1_attempts"),
    pin2Attempts: try takeAttempt(&map, "pin2_attempts"),
    pukAttempts: try takeAttempt(&map, "puk_attempts")
  )
}

/// The journal annotation of a status report.
///
/// `retired` is written only when set, so annotations stored before the
/// field existed keep their exact bytes.
internal func statusReportValue(_ report: StatusReport) -> WireValue {
  var map: [String: WireValue] = [
    "operation_id": .bytes(report.operationIdentifier),
    "known": .boolean(report.known),
    "state": report.state.map { .text($0.rawValue) } ?? .null,
    "request_hash": report.requestHash.map { .bytes($0) } ?? .null,
  ]
  if report.retired {
    map["retired"] = .boolean(true)
  }
  return .map(map)
}

/// The operation state a status report names, absent when stored as null.
private func takeReportedState(_ map: inout [String: WireValue]) throws -> OperationState? {
  switch try takeStoredValue(&map, "state") {
  case .null:
    return nil

  case .text(let name):
    guard let parsed = OperationState(rawValue: name) else { throw PairRecordError.invalidInput }
    return parsed

  default:
    throw PairRecordError.invalidInput
  }
}

/// The request hash a status report names, absent when stored as null.
private func takeReportedRequestHash(_ map: inout [String: WireValue]) throws -> Data? {
  switch try takeStoredValue(&map, "request_hash") {
  case .null:
    return nil

  case .bytes(let bytes):
    guard bytes.count == JournalSize.requestHash else { throw PairRecordError.invalidInput }
    return bytes

  default:
    throw PairRecordError.invalidInput
  }
}

internal func statusReportFrom(_ value: WireValue) throws -> StatusReport {
  guard case .map(var map) = value else { throw PairRecordError.invalidInput }
  let operationIdentifier = try takeBytes(&map, "operation_id")
  guard operationIdentifier.count == JournalSize.operationIdentifier else {
    throw PairRecordError.invalidInput
  }
  let known = try takeBoolean(&map, "known")
  let state = try takeReportedState(&map)
  let requestHash = try takeReportedRequestHash(&map)
  let retired = try takeBoolean(&map, "retired", absent: false)
  guard map.isEmpty else { throw PairRecordError.invalidInput }
  return StatusReport(
    operationIdentifier: operationIdentifier, known: known, state: state,
    requestHash: requestHash, retired: retired)
}

/// An absent attempt counter is stored as null rather than omitted.
internal func attemptValue(_ attempts: UInt8?) -> WireValue {
  attempts.map { .unsigned(UInt64($0)) } ?? .null
}

internal func takeAttempt(
  _ map: inout [String: WireValue], _ field: String
) throws -> UInt8? {
  switch try takeStoredValue(&map, field) {
  case .null:
    return nil

  case .unsigned(let value):
    guard let narrowed = UInt8(exactly: value) else { throw PairRecordError.invalidInput }
    return narrowed

  default:
    throw PairRecordError.invalidInput
  }
}
