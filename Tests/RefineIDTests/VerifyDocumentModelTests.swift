// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// Live revocation and generations in the verification model.
@MainActor
@Suite
internal struct VerifyDocumentModelTests {
  /// Holds each live revocation call until the test releases it.
  private actor LiveGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var calls = 0
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Suspends the calling live revocation until it is released.
    func hold() async {
      calls += 1
      let reached = callWaiters.filter { waiter in waiter.count <= calls }
      callWaiters.removeAll { waiter in waiter.count <= calls }
      for waiter in reached { waiter.continuation.resume() }
      await withCheckedContinuation { continuation in waiting.append(continuation) }
    }

    /// Returns once `count` calls have been made.
    func waitForCalls(_ count: Int) async {
      guard calls < count else { return }
      await withCheckedContinuation { continuation in
        callWaiters.append((count, continuation))
      }
    }

    /// Releases the earliest held call.
    func releaseOne() {
      guard !waiting.isEmpty else { return }
      waiting.removeFirst().resume()
    }
  }

  /// The document text the fake verifier never reads.
  private static let document = Data("document".utf8)

  /// One verification's name.
  private static let firstName = "first.pdf"

  /// Another verification's name.
  private static let secondName = "second.pdf"

  /// The second live revocation call.
  private static let secondCall = 2

  private static func dependencies(
    gate: LiveGate?
  ) -> VerifyDocumentModel.Dependencies {
    VerifyDocumentModel.Dependencies(
      verify: { _ in VerifyDocumentModelFixture.documentReport },
      liveStatus: { _ in
        await gate?.hold()
        return .ocsp(VerifyDocumentModelFixture.goodResponse)
      },
      now: { VerifyDocumentModelFixture.currentTime }
    )
  }

  private static func onlyReport(
    _ model: VerifyDocumentModel
  ) -> (row: VerifyDocumentModel.SignatureRow, report: DocumentVerification.SignatureReport)? {
    guard
      case .report(let rows, _) = model.phase,
      let row = rows.first,
      case .judged(let report) = row.entry
    else {
      return nil
    }
    return (row, report)
  }

  /// A live OCSP answer is applied to the row, dated at producedAt.
  @Test
  internal func liveOcspAnswerIsApplied() async throws {
    let model = VerifyDocumentModel(dependencies: Self.dependencies(gate: nil))
    model.verify(document: Self.document, name: Self.firstName)
    await model.verification?.value

    let shown = try #require(Self.onlyReport(model))
    #expect(!shown.row.checking)
    guard case .good = shown.report.revocation else {
      Issue.record("The live OCSP answer was not applied")
      return
    }
  }

  /// An answer for an earlier verification does not reach the rows of
  /// the current one.
  @Test
  internal func staleAnswerIsIgnored() async throws {
    let gate = LiveGate()
    let model = VerifyDocumentModel(dependencies: Self.dependencies(gate: gate))
    model.verify(document: Self.document, name: Self.firstName)
    await gate.waitForCalls(1)
    let first = model.verification
    model.verify(document: Self.document, name: Self.secondName)
    await gate.waitForCalls(Self.secondCall)

    await gate.releaseOne()
    await first?.value
    let pending = try #require(Self.onlyReport(model))
    #expect(pending.row.checking)
    #expect(pending.report.revocation == .unavailable)
    #expect(model.documentName == Self.secondName)

    await gate.releaseOne()
    await model.verification?.value
    let answered = try #require(Self.onlyReport(model))
    #expect(!answered.row.checking)
  }

  /// Reset stops a running verification, and its answer never brings
  /// the report back.
  @Test
  internal func resetCancelsTheVerification() async {
    let gate = LiveGate()
    let model = VerifyDocumentModel(dependencies: Self.dependencies(gate: gate))
    model.verify(document: Self.document, name: Self.firstName)
    await gate.waitForCalls(1)
    let running = model.verification
    model.reset()

    await gate.releaseOne()
    await running?.value
    guard case .idle = model.phase else {
      Issue.record("The cancelled verification resurrected a report")
      return
    }
    #expect(model.documentName.isEmpty)
  }
}
