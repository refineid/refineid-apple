// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The wire version every parameter echo repeats.
internal var wireVersionValue: WireValue {
  .array([
    .unsigned(RappNoise.wireVersion.major), .unsigned(RappNoise.wireVersion.minor),
    .unsigned(RappNoise.wireVersion.patch),
  ])
}

internal func requireVersion(_ map: inout [String: WireValue]) throws {
  guard map.removeValue(forKey: "version") == wireVersionValue else {
    throw MessageFieldError.invalidField("version")
  }
}

internal func requireSuite(_ map: inout [String: WireValue], _ expected: String) throws {
  guard map.removeValue(forKey: "suite") == .text(expected) else {
    throw MessageFieldError.invalidField("suite")
  }
}

internal func profileName(_ value: WireValue) throws -> ProfileName {
  guard case .text(let name) = value else {
    print("[profileName] value is not .text: \(value)")
    Darwin.fflush(stdout)
    throw MessageFieldError.invalidField("profiles")
  }
  guard let profile = ProfileName(rawValue: name) else {
    print("[profileName] unrecognized profile text: '\(name)'")
    Darwin.fflush(stdout)
    throw MessageFieldError.invalidField("profiles")
  }
  return profile
}

/// A profile set must be present and name each profile once.
internal func validateProfileSet(_ profiles: [ProfileName]) throws {
  guard !profiles.isEmpty, Set(profiles.map(\.rawValue)).count == profiles.count else {
    throw MessageFieldError.invalidField("profiles")
  }
}

/// Profiles are ordered by their name bytes so both peers agree on the set's
/// encoding regardless of the order the user chose them in.
internal func sortedByNameBytes(_ profiles: [ProfileName]) -> [ProfileName] {
  profiles.sorted { left, right in
    Array(left.rawValue.utf8).lexicographicallyPrecedes(Array(right.rawValue.utf8))
  }
}

internal func validateLabel(_ value: String, _ field: String) throws {
  guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    value.utf8.count <= FlowLimit.labelBytes
  else { throw MessageFieldError.invalidField(field) }
}

internal func validateTransportName(_ value: String, _ field: String) throws {
  let bytes = Array(value.utf8)
  guard !bytes.isEmpty, bytes.count <= FlowLimit.transportNameBytes,
    bytes.allSatisfy({ byte in
      isAsciiAlphanumeric(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
        || byte == UInt8(ascii: "_")
    })
  else { throw MessageFieldError.invalidField(field) }
}

/// Whether a byte is an unaccented letter or a digit.
private func isAsciiAlphanumeric(_ byte: UInt8) -> Bool {
  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
}

internal func takeMessageValue(
  _ map: inout [String: WireValue], _ field: String
) throws -> WireValue {
  guard let value = map.removeValue(forKey: field) else {
    throw MessageFieldError.invalidField(field)
  }
  return value
}

internal func takeMessageText(_ map: inout [String: WireValue], _ field: String) throws -> String {
  guard case .text(let value) = try takeMessageValue(&map, field) else {
    throw MessageFieldError.invalidField(field)
  }
  return value
}

internal func takeMessageBytes(_ map: inout [String: WireValue], _ field: String) throws -> Data {
  guard case .bytes(let value) = try takeMessageValue(&map, field) else {
    throw MessageFieldError.invalidField(field)
  }
  return value
}

internal func takeMessageMap(
  _ map: inout [String: WireValue], _ field: String
) throws -> [String: WireValue] {
  guard case .map(let value) = try takeMessageValue(&map, field) else {
    throw MessageFieldError.invalidField(field)
  }
  return value
}
