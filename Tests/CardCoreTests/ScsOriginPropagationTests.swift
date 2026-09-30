// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The requesting origin reaches the signing backend on every path.
///
/// The end user is shown which site asked for a signature (DVV SCS
/// specification v1.3 §2.1), and only the backend can put that in
/// front of them. An origin dropped anywhere between the HTTP head and
/// the card session becomes a prompt that names nothing, which is the
/// state the requirement exists to prevent.
@Suite
internal struct ScsOriginPropagationTests {
  private static let origin = "https://dvv.fineid.fi"

  private func backend() -> ScriptedScsBackend {
    ScriptedScsBackend(
      chain: [Data([0x30, 0x00])],
      algorithm: .rsa,
      signature: Data([0xaa]))
  }

  private func jsonSignBody() throws -> Data {
    try JSONEncoder().encode(
      ScsSignRequestDocument(
        content: Data("payload".utf8).base64EncodedString(),
        contentType: "data",
        selector: ScsSignRequestDocument.Selector(keyusages: ["nonRepudiation"]),
        hashAlgorithm: "SHA256",
        signatureType: "signature"
      )
    )
  }

  private func dispatch(
    origin: String?,
    backend: ScriptedScsBackend
  ) throws -> Data {
    ScsDispatcher.dispatch(
      request: ScsHttpRequest(
        method: "POST",
        path: "/sign",
        origin: origin,
        contentType: "application/json",
        bodyLength: 0
      ),
      body: try jsonSignBody(),
      backend: backend,
      transactions: ScsTransactionManager()
    )
  }

  /// Every sign the protocol layer asks for carries the requesting
  /// origin, because the end user is asked to approve each one by name.
  @Test
  internal func aJsonSignCarriesItsOriginToTheBackend() throws {
    let scripted = backend()
    _ = try dispatch(origin: Self.origin, backend: scripted)
    #expect(scripted.signedOrigins == [Self.origin])
  }

  /// A sign with no Origin must reach the backend as absent rather
  /// than as a guess: the holder decides on the facts in the prompt.
  @Test
  internal func aJsonSignWithNoOriginReachesTheBackendAsAbsent() throws {
    let scripted = backend()
    _ = try dispatch(origin: nil, backend: scripted)
    #expect(scripted.signedOrigins == [nil])
  }
}
