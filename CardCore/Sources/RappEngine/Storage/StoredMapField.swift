// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

internal func takeStoredValue(
  _ map: inout [String: WireValue], _ field: String
) throws -> WireValue {
  guard let value = map.removeValue(forKey: field) else { throw PairRecordError.invalidInput }
  return value
}

internal func takeText(_ map: inout [String: WireValue], _ field: String) throws -> String {
  guard case .text(let value) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return value
}

internal func takeBytes(_ map: inout [String: WireValue], _ field: String) throws -> Data {
  guard case .bytes(let value) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return value
}

internal func takeUnsigned(
  _ map: inout [String: WireValue], _ field: String
) throws -> UInt64 {
  guard case .unsigned(let value) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return value
}

/// An unsigned field that may be null.
internal func takeOptionalUnsigned(
  _ map: inout [String: WireValue], _ field: String
) throws -> UInt64? {
  switch try takeStoredValue(&map, field) {
  case .null:
    return nil

  case .unsigned(let value):
    return value

  default:
    throw PairRecordError.invalidInput
  }
}

internal func takeBoolean(_ map: inout [String: WireValue], _ field: String) throws -> Bool {
  guard case .boolean(let value) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return value
}

internal func takeMap(
  _ map: inout [String: WireValue], _ field: String
) throws -> [String: WireValue] {
  guard case .map(let value) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return value
}

internal func takeTextArray(
  _ map: inout [String: WireValue], _ field: String
) throws -> [String] {
  guard case .array(let values) = try takeStoredValue(&map, field) else {
    throw PairRecordError.invalidInput
  }
  return try values.map { value in
    guard case .text(let text) = value else { throw PairRecordError.invalidInput }
    return text
  }
}
