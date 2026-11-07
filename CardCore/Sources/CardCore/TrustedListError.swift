// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a trusted list was not read.
public enum TrustedListError: Error, Equatable, Sendable {
  /// A count exceeds its bound.
  case bound(Bound)

  /// A field every list has is absent or does not read.
  case malformed(String)

  /// The list carries no `ds:Signature`, or more than one.
  case noSignature

  /// The list of the lists was asked for but not fetched.
  case notFetched

  /// The list read as the list of the lists is not one.
  case notListOfTheLists

  /// The document element is not a `TrustServiceStatusList`.
  case notTrustedList

  /// A reference digest or the signature value does not verify.
  case signatureInvalid

  /// The signer certificate is none of the certificates entitled to
  /// sign this list.
  case signerNotEntitled

  /// The list exceeds `TrustedList.maximumBytes`.
  case tooLarge

  /// The `TSLType` is neither the EU list of the lists nor an EU
  /// member state list.
  case unknownListType

  /// A service status identifier is none of annex D.5.6.
  case unknownServiceStatus

  /// The signature uses an algorithm, canonicalisation or reference
  /// the verifier does not compute, so it cannot be verified.
  case unverifiable(String)

  /// The bytes are not XML the reader reads.
  case xml(XmlReadError)

  /// A count a list exceeded.
  public enum Bound: Sendable, Equatable {
    /// `TrustedList.maximumHistory`.
    case history

    /// `TrustedList.maximumIdentityCertificates`.
    case identityCertificates

    /// `TrustedList.maximumPointers`.
    case pointers

    /// `TrustedList.maximumPointerSigners`.
    case pointerSigners

    /// `TrustedList.maximumServices`.
    case services
  }
}
