// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the specification registers the operations, so the
// source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

/// A typed card operation.
public enum RappOperationKind: Sendable {
  case inspectCard
  case readIdentity
  case readAuthenticationCertificate
  case readSignatureCertificate
  case readRootCertificate
  case readIntermediateCertificate
  case browserAuthenticate
  case signDocument
  case batchSignDocuments
}

// swiftlint:enable sorted_enum_cases
