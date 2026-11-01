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
    let directory: AuthenticationObjectDirectory?
    do {
      try selectFineidApplication()
      let content = try readElementaryFile(.authenticationObjectDirectory, expectedLength: nil)
      directory = AuthenticationObjectDirectory.parse(content)
    } catch CardOperationError.selectRejected, CardOperationError.readFailed {
      directory = nil
    }
    return CardPinLengths.mapping(directory, numbering: numbering)
  }
}
