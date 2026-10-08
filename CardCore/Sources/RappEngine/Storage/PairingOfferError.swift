// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the offer is validated, so the source reads in
// the order the failures can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Structural or policy failure in a pairing offer.
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
  case invalidLifetime
  case deadlineOverflow
  case oversized
  case wire(WireError)
}

// swiftlint:enable sorted_enum_cases
