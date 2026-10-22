// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Strict wire-format failure.
///
/// After decryption every case is an authenticated protocol violation, so the
/// names cross the conformance corpus verbatim.
internal enum WireError: Error, Equatable, CustomStringConvertible {
  case collectionTooLarge(got: Int)
  case duplicateMapKey
  case forbiddenCborType
  case integerOverflow
  case invalidUtf8
  case invalidValue(field: String)
  case missingField(field: String)
  case nestingTooDeep
  case nonCanonical
  case nonTextMapKey
  case oversizedPlaintext(got: Int)
  case sequenceWrapped
  case textTooLong(got: Int)
  case trailingData
  case truncated
  case unknownField
  case unknownMessageType
  case unsupportedVersion
  case wrongLength(field: String, expected: Int, got: Int)
  case wrongSequence(expected: UInt64, got: UInt64)
  case wrongSession
  case wrongType(field: String)

  internal var description: String {
    switch self {
    case .collectionTooLarge(let got):
      "CollectionTooLarge { got: \(got) }"

    case .duplicateMapKey:
      "DuplicateMapKey"

    case .forbiddenCborType:
      "ForbiddenCborType"

    case .integerOverflow:
      "IntegerOverflow"

    case .invalidUtf8:
      "InvalidUtf8"

    case .invalidValue(let field):
      "InvalidValue { field: \"\(field)\" }"

    case .missingField(let field):
      "MissingField { field: \"\(field)\" }"

    case .nestingTooDeep:
      "NestingTooDeep"

    case .nonCanonical:
      "NonCanonical"

    case .nonTextMapKey:
      "NonTextMapKey"

    case .oversizedPlaintext(let got):
      "OversizedPlaintext { got: \(got) }"

    case .sequenceWrapped:
      "SequenceWrapped"

    case .textTooLong(let got):
      "TextTooLong { got: \(got) }"

    case .trailingData:
      "TrailingData"

    case .truncated:
      "Truncated"

    case .unknownField:
      "UnknownField"

    case .unknownMessageType:
      "UnknownMessageType"

    case .unsupportedVersion:
      "UnsupportedVersion"

    case .wrongLength(let field, let expected, let got):
      "WrongLength { field: \"\(field)\", expected: \(expected), got: \(got) }"

    case .wrongSequence(let expected, let got):
      "WrongSequence { expected: \(expected), got: \(got) }"

    case .wrongSession:
      "WrongSession"

    case .wrongType(let field):
      "WrongType { field: \"\(field)\" }"
    }
  }
}
