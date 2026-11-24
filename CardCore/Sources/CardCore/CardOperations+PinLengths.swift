// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CardOperations {
  /// Reads the PIN 1, PIN 2 and PUK lengths the card accepts,
  /// counter-safe.
  ///
  /// Resolves the reference numbering (remembered for the session),
  /// then reads EF.AOD under the PKCS#15 application, which leaves that
  /// application selected. An EF.AOD that cannot be selected, read or
  /// decoded lists nothing, and a credential the card does not list
  /// takes its FINEID bounds. Called where PINs are set -- activation,
  /// change and reset -- never on the signing or login paths. Throws
  /// only when the card session itself fails.
  public func readCardPinLengths() throws -> CardPinLengths {
    let numbering = try resolveCredentialReferences()
    if numbering == .estonian2018 {
      // IDEMIA IAS-ECC EF.AOD encodes the padded 12-byte stored length as both
      // minLength and maxLength (ID1 Developer Guide 2025 section 8.1), so the
      // card family's documented 4-12 / 5-12 / 8-12 bounds govern input validation.
      return CardPinLengths.notListed(numbering: .estonian2018)
    }
    let directory: AuthenticationObjectDirectory?
    do {
      try selectCardApplication()
      let content = try readAuthenticationObjectDirectoryBytes(for: numbering)
      directory = AuthenticationObjectDirectory.parse(content)
    } catch CardOperationError.selectRejected, CardOperationError.readFailed {
      directory = nil
    }
    return CardPinLengths.mapping(directory, numbering: numbering)
  }

  private func readAuthenticationObjectDirectoryBytes(
    for numbering: CredentialReferenceSet
  ) throws -> Data {
    if numbering == .estonian2025 {
      discoverEstonian2025Directory()
      let file = referenceMemo.discoveredAodFile ?? .estonian2025Aod
      return try readElementaryFile(file, expectedLength: nil)
    }
    return try readElementaryFile(.authenticationObjectDirectory, expectedLength: nil)
  }
}
