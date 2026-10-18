// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// The bodies RAPP v26.10.18 added, against the vendored bytes.
extension OperationBodyTests {
  @Test("The storage confirmation, card status and consent bodies match byte for byte")
  internal func revisionBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let reference = try Self.reference(corpus.fixedInputs)
    let pairIdentifier = try Data(hex: corpus.fixedInputs.pairIdentifier)
    let stored = try WireValue.map(PairingStored(pairIdentifier: pairIdentifier).body()).encoded()
    #expect(try stored.hex == Self.expected(corpus, "pairing-stored"))
    #expect(
      try Self.encoded(.cardStatus(cardPresent: true))
        == Self.expected(corpus, "card-status-present"))
    #expect(
      try Self.encoded(.cardStatus(cardPresent: false))
        == Self.expected(corpus, "card-status-absent"))
    let consent = OperationProgressMessage(reference: reference, event: .consentShown)
    #expect(
      try Self.encoded(.operationProgress(consent))
        == Self.expected(corpus, "progress-consent-shown"))
    let waiting = OperationProgressMessage(reference: reference, event: .waitingForCard)
    #expect(
      try Self.encoded(.operationProgress(waiting))
        == Self.expected(corpus, "progress-waiting-for-card"))
  }
}
