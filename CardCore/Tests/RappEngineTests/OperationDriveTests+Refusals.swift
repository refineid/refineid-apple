// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// 2. Grant enforcement and registry refusals
internal func step2() throws {
  // MARK: - 2. Grant enforcement and registry refusals
  try grantEnforcement()
  try profileActionOwnership()
  try unknownActionRefused()
  try unexpectedFieldRefused()
  try wrongDigestLengthRefused()
  try keyAlgorithmMismatchRefused()
  try invalidDisplayContextRefused()
}

/// Ungranted profiles are refused before any card contact; granted ones admitted.
private func grantEnforcement() throws {
  let request = try browserRequest()
  var refused = false
  do {
    try request.requireGranted(by: [.cardStatus, .documentSigning])
  } catch CardOperationError.profileNotGranted {
    refused = true
  }
  check("an ungranted profile is refused before any card contact", refused)
  var permitted = true
  do {
    try request.requireGranted(by: [.authentication])
  } catch {
    permitted = false
  }
  check("a granted profile is admitted", permitted)
}
/// A profile that does not own the action is refused.
private func profileActionOwnership() throws {
  var mismatched = false
  do {
    _ = try OperationRequest(
      operationIdentifier: OperationFixture.operationIdentifier,
      pairIdentifier: OperationFixture.pairIdentifier,
      sessionIdentifier: OperationFixture.sessionIdentifier,
      profile: .cardStatus,
      localStartMilliseconds: OperationFixture.startMilliseconds,
      expiresAfterMilliseconds: OperationFixture.lifetimeMilliseconds,
      operation: .browserAuthenticate(
        origin: OperationFixture.origin, keyProfile: .ecdsaP256, algorithm: .ecdsaSha256,
        digest: OperationFixture.digest))
  } catch CardOperationError.profileActionMismatch {
    mismatched = true
  }
  check("a profile that does not own the action is refused", mismatched)
}
/// An unregistered action is refused.
private func unknownActionRefused() throws {
  var unknown = false
  do {
    _ = try CardOperation.from(action: "transmit_apdu", context: [:], payload: [:])
  } catch CardOperationError.unknownAction {
    unknown = true
  }
  check("an unregistered action is refused", unknown)
}
/// An unregistered field is refused.
private func unexpectedFieldRefused() throws {
  var extraField = false
  do {
    _ = try CardOperation.from(
      action: "read_identity", context: [:], payload: ["apdu": .bytes(Data([0x00]))])
  } catch CardOperationError.unexpectedField {
    extraField = true
  }
  check("an unregistered field is refused", extraField)
}
/// A digest of the wrong length is refused.
private func wrongDigestLengthRefused() throws {
  var wrongDigest = false
  do {
    _ = try CardOperation.from(
      action: "browser_authenticate",
      context: ["origin": .text(OperationFixture.origin)],
      payload: [
        "key_profile": .text(CardKeyProfile.ecdsaP256.rawValue),
        "algorithm": .text(SignatureAlgorithm.ecdsaSha256.rawValue),
        "digest": .bytes(Data(repeating: 0x01, count: DigestLength.sha384)),
      ])
  } catch CardOperationError.wrongDigestLength {
    wrongDigest = true
  }
  check("a digest of the wrong length is refused", wrongDigest)
}
/// An elliptic scheme on an RSA key is refused.
private func keyAlgorithmMismatchRefused() throws {
  var crossFamily = false
  do {
    _ = try CardOperation.from(
      action: "browser_authenticate",
      context: ["origin": .text(OperationFixture.origin)],
      payload: [
        "key_profile": .text(CardKeyProfile.rsa3072.rawValue),
        "algorithm": .text(SignatureAlgorithm.ecdsaSha256.rawValue),
        "digest": .bytes(OperationFixture.digest),
      ])
  } catch CardOperationError.keyAlgorithmMismatch {
    crossFamily = true
  }
  check("an elliptic scheme on an RSA key is refused", crossFamily)
}
/// An unpresentable request is refused.
private func invalidDisplayContextRefused() throws {
  var emptyContext = false
  do {
    _ = try CardOperation.from(
      action: "sign_document",
      context: ["document_name": .text("   ")],
      payload: [
        "key_profile": .text(CardKeyProfile.rsa3072.rawValue),
        "algorithm": .text(SignatureAlgorithm.rsaPkcs1Sha256.rawValue),
        "digest": .bytes(OperationFixture.digest),
      ])
  } catch CardOperationError.invalidDisplayContext {
    emptyContext = true
  }
  check("an unpresentable request is refused", emptyContext)
}
/// 4. Results
internal func step4() throws {
  // MARK: - 4. Results
  let transaction = try AuthorizationTransaction(request: try browserRequest())
  try completedResultRoundTrip(transaction)
  try wrongShapeRefused(transaction)
  try emptyCompletedRefused(transaction)
  try failureRegistryRoundTrips(transaction)
  try contradictoryStatusRefused(transaction)
  try foreignResultRefused(transaction)
}

/// A completed result round-trips and answers its operation.
private func completedResultRoundTrip(_ transaction: AuthorizationTransaction) throws {
  let completed = OperationResultMessage.completed(
    reference: transaction.reference, result: .signature(OperationFixture.signature))
  let encoded = try completed.encoded()
  check("a completed result round-trips", try OperationResultMessage.decode(encoded) == completed)

  var validated = true
  do {
    try completed.validate(for: transaction.reference, operation: transaction.request.operation)
  } catch {
    validated = false
  }
  check("a signature answers a browser authentication", validated)
}
/// A body that answers a different operation is refused.
private func wrongShapeRefused(_ transaction: AuthorizationTransaction) throws {
  let wrongShape = OperationResultMessage.completed(
    reference: transaction.reference, result: .certificate(OperationFixture.certificate))
  var wrongAccepted = false
  do {
    try wrongShape.validate(
      for: transaction.reference, operation: transaction.request.operation)
    wrongAccepted = true
  } catch is CardOperationError {
    // A response carries no variant tag, so one shaped for another
    // operation simply does not read as an answer to this one.
    wrongAccepted = false
  }
  check("a result that answers another operation is refused", !wrongAccepted)
}
/// A completed result carrying no output is refused, and an empty body does not decode.
private func emptyCompletedRefused(_ transaction: AuthorizationTransaction) throws {
  let emptyCompleted = OperationResultMessage(
    operationIdentifier: transaction.reference.operationIdentifier,
    requestHash: transaction.reference.requestHash,
    status: .completed)
  var emptyAccepted = false
  do {
    try emptyCompleted.validate(
      for: transaction.reference, operation: transaction.request.operation)
    emptyAccepted = true
  } catch CardOperationError.invalidField {
    emptyAccepted = false
  }
  check("a completed result carrying no output is refused", !emptyAccepted)

  var decodedEmpty = false
  do {
    _ = try OperationResultMessage.decode(try emptyCompleted.encoded())
    decodedEmpty = true
  } catch {
    decodedEmpty = false
  }
  check("a completed result with no response does not decode", !decodedEmpty)
}
/// Every registered failure round-trips under its own status.
private func failureRegistryRoundTrips(_ transaction: AuthorizationTransaction) throws {
  var registryHolds = true
  for failure in [
    ProxyFailure.userDenied, .requestExpired, .cancelled, .requestInvalidOrUnsupported,
    .unauthorized, .retryPolicyRefused, .credentialRejected, .cardRemovedBeforeTransmit,
    .cardCompletionAmbiguous,
  ] {
    let message = OperationResultMessage.failure(
      reference: transaction.reference, failure: failure)
    if message.error?.permits(message.status) != true { registryHolds = false }
    if (try? OperationResultMessage.decode(try message.encoded())) != message {
      registryHolds = false
    }
  }
  check("every registered failure round-trips under its own status", registryHolds)
}
/// A failure name that contradicts its status is refused.
private func contradictoryStatusRefused(_ transaction: AuthorizationTransaction) throws {
  let contradictory = OperationResultMessage(
    operationIdentifier: transaction.reference.operationIdentifier,
    requestHash: transaction.reference.requestHash,
    status: .rejected,
    error: .cardError)
  var contradictionAccepted = false
  do {
    try contradictory.validate(
      for: transaction.reference, operation: transaction.request.operation)
    contradictionAccepted = true
  } catch CardOperationError.invalidField {
    contradictionAccepted = false
  }
  check("a failure name that contradicts its status is refused", !contradictionAccepted)
}
/// A result bound to another operation is refused.
private func foreignResultRefused(_ transaction: AuthorizationTransaction) throws {
  let foreign = OperationResultMessage.completed(
    reference: OperationReference(
      operationIdentifier: OperationFixture.otherOperation,
      requestHash: transaction.reference.requestHash),
    result: .signature(OperationFixture.signature))
  var foreignAccepted = false
  do {
    try foreign.validate(for: transaction.reference, operation: transaction.request.operation)
    foreignAccepted = true
  } catch CardOperationError.requestHashMismatch {
    foreignAccepted = false
  }
  check("a result bound to another operation is refused", !foreignAccepted)
}
