// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && REFINEID_STREAM_TRANSPORT
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// The held session's answers before it is up and after it is down.
  @Suite("Held requester session")
  internal struct RappHeldRequesterSessionTests {
    private actor Reports {
      private(set) var received: [RappHeldRequesterSession.Report] = []

      func record(_ report: RappHeldRequesterSession.Report) {
        received.append(report)
      }
    }

    /// How many times the close report is looked for, and how long apart.
    private static let closeChecks = 50
    private static let closeCheckInterval = Duration.milliseconds(20)

    /// How long a second close is given to produce a report it must not.
    private static let repeatedCloseWait = Duration.milliseconds(50)

    private static func requester() throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      return try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation)
    }

    @Test("A read before the session is up is refused, and after it ended too")
    internal func readsOutsideTheSessionAreRefused() async throws {
      let reports = Reports()
      let session = RappHeldRequesterSession(pair: try Self.requester()) { report in
        Task { await reports.record(report) }
      }
      await #expect(throws: RappHeldRequesterSession.ReadError.notEstablished) {
        try await session.readAuthenticationCertificate()
      }
      session.close()
      var closed = false
      for _ in 0..<Self.closeChecks where !closed {
        closed = await reports.received.contains(.closed(.localRequest))
        if !closed { try await Task.sleep(for: Self.closeCheckInterval) }
      }
      #expect(closed)
      await #expect(throws: RappHeldRequesterSession.ReadError.closed) {
        try await session.readAuthenticationCertificate()
      }
      // A second end is not reported.
      session.close()
      try await Task.sleep(for: Self.repeatedCloseWait)
      #expect(await reports.received == [.closed(.localRequest)])
    }
  }
#endif
