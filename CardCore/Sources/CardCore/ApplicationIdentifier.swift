// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// An ISO 7816-4 application identifier (AID), validated at construction.
public struct ApplicationIdentifier: Equatable, Sendable {
  /// Shortest AID the standard permits (the 5-byte RID alone).
  public static let minimumByteCount: Int = 5

  /// Longest AID the standard permits.
  public static let maximumByteCount: Int = 16

  /// The FINEID eID application on every supported card
  /// (`FineidValues.applicationAidHexDigits`, from the DVV note).
  public static let fineidApplication: Self = constant(
    FineidValues.applicationAidHexDigits
  )

  /// The ICAO eMRTD application a Finnish identity card also
  /// implements, source of the holder's signature image.
  public static let travelDocumentApplication: Self = constant(
    FineidValues.travelDocumentAidHexDigits
  )

  /// DF.ESIGN on the organization card, by its name "E.SIGN"
  /// (FINEID S4-2 v4.0 §4.6.21).
  public static let esignDirectory: Self = constant(
    FineidValues.esignAidHexDigits
  )

  /// EstEID 2018 (Cosmo v8.1 / v8.2) IAS-ECC root application AID.
  public static let estonian2018Application: Self = constant(
    EstonianEidValues.legacyRootAidHexDigits
  )

  /// EstEID 2018 v2 (Cosmo X) IAS-ECC root application AID
  /// (ID1 Developer Guide 2025 section 6).
  public static let estonian2018V2Application: Self = constant(
    EstonianEidValues.legacyCosmoXRootAidHexDigits
  )

  /// The validated AID bytes, read by the command encoder.
  internal let bytes: [UInt8]

  /// Parses an even-length hex-digit string of 5-16 bytes; refuses
  /// everything else.
  public init?(hexDigits: String) {
    let digitsPerByte = 2
    let characters = Array(hexDigits)
    guard
      !characters.isEmpty,
      characters.count.isMultiple(of: digitsPerByte)
    else {
      return nil
    }
    var parsed: [UInt8] = []
    parsed.reserveCapacity(characters.count / digitsPerByte)
    var index = characters.startIndex
    while index < characters.endIndex {
      let pair = String(characters[index...index.advanced(by: 1)])
      guard let byte = UInt8(pair, radix: Iso7816Values.hexRadix) else {
        return nil
      }
      parsed.append(byte)
      index = index.advanced(by: digitsPerByte)
    }
    guard
      parsed.count >= Self.minimumByteCount,
      parsed.count <= Self.maximumByteCount
    else {
      return nil
    }
    self.bytes = parsed
  }

  /// Builds an in-module constant; an invalid constant is a programmer
  /// error caught at first use.
  private static func constant(_ hexDigits: String) -> Self {
    guard let aid = Self(hexDigits: hexDigits) else {
      preconditionFailure("invalid AID constant: \(hexDigits)")
    }
    return aid
  }
}
