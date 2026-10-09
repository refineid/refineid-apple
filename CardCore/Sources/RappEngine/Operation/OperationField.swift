// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

internal func takeCertificateKind(_ payload: inout [String: WireValue]) throws -> CertificateKind {
  guard let kind = CertificateKind(rawValue: try takeOperationText(&payload, "kind")) else {
    throw CardOperationError.invalidField(field: "kind")
  }
  return kind
}

internal func takeKeyProfile(_ payload: inout [String: WireValue]) throws -> CardKeyProfile {
  guard let profile = CardKeyProfile(rawValue: try takeOperationText(&payload, "key_profile"))
  else { throw CardOperationError.invalidField(field: "key_profile") }
  return profile
}

internal func takeAlgorithm(_ payload: inout [String: WireValue]) throws -> SignatureAlgorithm {
  guard let algorithm = SignatureAlgorithm(rawValue: try takeOperationText(&payload, "algorithm"))
  else { throw CardOperationError.invalidField(field: "algorithm") }
  return algorithm
}

internal func takeOperationText(_ map: inout [String: WireValue], _ field: String) throws -> String
{
  guard case .some(.text(let value)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return value
}

internal func takeOperationBytes(_ map: inout [String: WireValue], _ field: String) throws -> Data {
  guard case .some(.bytes(let value)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return value
}

internal func takeOperationUnsigned(_ map: inout [String: WireValue], _ field: String) throws
  -> UInt64
{
  guard case .some(.unsigned(let value)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return value
}

internal func takeOperationMap(_ map: inout [String: WireValue], _ field: String) throws
  -> [String: WireValue]
{
  guard case .some(.map(let value)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return value
}

internal func takeOperationTextArray(_ map: inout [String: WireValue], _ field: String) throws
  -> [String]
{
  guard case .some(.array(let values)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return try values.map { value in
    guard case .text(let text) = value else { throw CardOperationError.invalidField(field: field) }
    return text
  }
}

internal func takeOperationBytesArray(_ map: inout [String: WireValue], _ field: String) throws
  -> [Data]
{
  guard case .some(.array(let values)) = map.removeValue(forKey: field) else {
    throw CardOperationError.invalidField(field: field)
  }
  return try values.map { value in
    guard case .bytes(let bytes) = value else {
      throw CardOperationError.invalidField(field: field)
    }
    return bytes
  }
}
