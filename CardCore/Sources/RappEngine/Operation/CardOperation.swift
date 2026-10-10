// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are listed in the order the specification registers the
// operations, so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The closed set of remote card operations.
///
/// A request describes a user-visible goal. It never carries a raw APDU, a
/// card access number, or a PIN; the authorizer collects those locally.
internal enum CardOperation: Equatable {
  case inspectCard

  case readIdentity

  case readCertificate(kind: CertificateKind)

  case browserAuthenticate(
    origin: String, keyProfile: CardKeyProfile, algorithm: SignatureAlgorithm, digest: Data)

  case signDocument(
    documentName: String, keyProfile: CardKeyProfile, algorithm: SignatureAlgorithm, digest: Data)

  /// Signs 1 to 64 documents under one PIN 2 entry (RAPP v26.10.9 §9.3);
  /// names and digests pair up by position.
  case batchSignDocuments(
    documentNames: [String], keyProfile: CardKeyProfile, algorithm: SignatureAlgorithm,
    digests: [Data])

  /// Whether this action crosses the prepare and commit boundary, so that it
  /// may consume a credential attempt or invoke a private key.
  internal var isConsequential: Bool {
    switch self {
    case .browserAuthenticate, .signDocument, .batchSignDocuments:
      true

    case .inspectCard, .readIdentity, .readCertificate:
      false
    }
  }

  /// How many documents a batch signs; nil for any other operation.
  internal var batchTotal: Int? {
    guard case .batchSignDocuments(_, _, _, let digests) = self else { return nil }
    return digests.count
  }

  /// The credential profile that owns this action's schema.
  internal var requiredProfile: ProfileName {
    switch self {
    case .inspectCard, .readIdentity:
      .cardStatus

    case .readCertificate(let kind):
      switch kind {
      case .authentication:
        .authentication
      case .signature:
        .documentSigning
      case .rootCa, .intermediateCa:
        .cardStatus
      }

    case .browserAuthenticate:
      .authentication

    case .signDocument, .batchSignDocuments:
      .documentSigning
    }
  }

  /// The registered wire action name.
  internal var action: String {
    switch self {
    case .inspectCard:
      "inspect_card"

    case .readIdentity:
      "read_identity"

    case .readCertificate:
      "read_certificate"

    case .browserAuthenticate:
      "browser_authenticate"

    case .signDocument:
      "sign_document"

    case .batchSignDocuments:
      "batch_sign_documents"
    }
  }

  /// Consent context, shown to the holder and bound into the request hash.
  internal var context: [String: WireValue] {
    switch self {
    case .inspectCard, .readIdentity, .readCertificate:
      [:]

    case .browserAuthenticate(let origin, _, _, _):
      ["origin": .text(origin)]

    case .signDocument(let documentName, _, _, _):
      ["document_name": .text(documentName)]

    case .batchSignDocuments(let documentNames, _, _, _):
      ["document_names": .array(documentNames.map(WireValue.text))]
    }
  }

  /// Profile payload, separately bounded from the consent context.
  internal var payload: [String: WireValue] {
    switch self {
    case .inspectCard, .readIdentity:
      return [:]

    case .readCertificate(let kind):
      return ["kind": .text(kind.rawValue)]

    case .browserAuthenticate(_, let keyProfile, let algorithm, let digest),
      .signDocument(_, let keyProfile, let algorithm, let digest):
      return [
        "key_profile": .text(keyProfile.rawValue),
        "algorithm": .text(algorithm.rawValue),
        "digest": .bytes(digest),
      ]

    case .batchSignDocuments(_, let keyProfile, let algorithm, let digests):
      return [
        "key_profile": .text(keyProfile.rawValue),
        "algorithm": .text(algorithm.rawValue),
        "digests": .array(digests.map(WireValue.bytes)),
      ]
    }
  }

  private static func validateNamedDigest(
    _ displayContext: String,
    _ keyProfile: CardKeyProfile,
    _ algorithm: SignatureAlgorithm,
    _ digest: Data
  ) throws {
    let trimmed = displayContext.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, displayContext.utf8.count <= OperationLimit.displayContextBytes else {
      throw CardOperationError.invalidDisplayContext
    }
    guard digest.count == algorithm.digestLength else {
      throw CardOperationError.wrongDigestLength
    }
    guard algorithm.supports(keyProfile) else {
      throw CardOperationError.keyAlgorithmMismatch
    }
  }

  /// Rebuilds an operation from an authenticated request body.
  internal static func from(
    action: String,
    context: [String: WireValue],
    payload: [String: WireValue]
  ) throws -> Self {
    var context = context
    var payload = payload
    let operation: Self
    switch action {
    case "inspect_card":
      operation = .inspectCard

    case "read_identity":
      operation = .readIdentity

    case "read_certificate":
      operation = .readCertificate(kind: try takeCertificateKind(&payload))

    case "browser_authenticate":
      operation = .browserAuthenticate(
        origin: try takeOperationText(&context, "origin"),
        keyProfile: try takeKeyProfile(&payload),
        algorithm: try takeAlgorithm(&payload),
        digest: try takeOperationBytes(&payload, "digest"))

    case "sign_document":
      operation = .signDocument(
        documentName: try takeOperationText(&context, "document_name"),
        keyProfile: try takeKeyProfile(&payload),
        algorithm: try takeAlgorithm(&payload),
        digest: try takeOperationBytes(&payload, "digest"))

    case "batch_sign_documents":
      operation = .batchSignDocuments(
        documentNames: try takeOperationTextArray(&context, "document_names"),
        keyProfile: try takeKeyProfile(&payload),
        algorithm: try takeAlgorithm(&payload),
        digests: try takeOperationBytesArray(&payload, "digests"))

    default:
      throw CardOperationError.unknownAction
    }
    guard context.isEmpty, payload.isEmpty else { throw CardOperationError.unexpectedField }
    try operation.validate()
    return operation
  }

  /// Rejects an operation whose parameters do not agree with each other.
  internal func validate() throws {
    switch self {
    case .inspectCard, .readIdentity, .readCertificate:
      return

    case .browserAuthenticate(let origin, let keyProfile, let algorithm, let digest):
      try Self.validateNamedDigest(origin, keyProfile, algorithm, digest)

    case .signDocument(let documentName, let keyProfile, let algorithm, let digest):
      try Self.validateNamedDigest(documentName, keyProfile, algorithm, digest)

    case .batchSignDocuments(let documentNames, let keyProfile, let algorithm, let digests):
      guard OperationLimit.batchDocuments.contains(digests.count),
        documentNames.count == digests.count
      else { throw CardOperationError.invalidField(field: "digests") }
      for (name, digest) in zip(documentNames, digests) {
        guard OperationLimit.batchDocumentNameBytes.contains(name.utf8.count) else {
          throw CardOperationError.invalidDisplayContext
        }
        try Self.validateNamedDigest(name, keyProfile, algorithm, digest)
      }
    }
  }
}

// swiftlint:enable sorted_enum_cases
