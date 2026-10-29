// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the offer is validated, so the source reads in
// the order the failures can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Structural or policy failure in a bootstrap answer: a `pairing-offer` or
/// a `pairing-busy`.
internal enum PairingOfferError: Error, Equatable {
  case wrongScheme
  case unsupportedVersion
  case wrongType
  case missingField(String)
  case unknownField
  case wrongLength(String)
  case emptyRequiredArray
  case mandatorySuiteMissing
  case tooManyTransports
  case invalidTransport
  /// The offer does not list the transport it was received over.
  case transportNotOffered
  /// A `pairing-busy` wait outside the schema's range.
  case retryAfterOutOfRange(UInt64)
  case invalidLifetime
  case deadlineOverflow
  case oversized
  case wire(WireError)
}

// swiftlint:enable sorted_enum_cases
