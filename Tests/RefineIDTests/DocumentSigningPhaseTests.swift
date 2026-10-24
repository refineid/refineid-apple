// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// The signing steps and the certificate read ahead of them.
@Suite
internal struct DocumentSigningPhaseTests {
  private enum Fixture {
    static let phases: [DocumentSigningPhase] = [.card, .phone, .timestamp, .validation]
    static let certificate = Data("certificate".utf8)
    static let firstPair = Data("first".utf8)
    static let secondPair = Data("second".utf8)
  }

  private struct ReadFailure: Error {}

  /// What a test saw, from whichever task saw it.
  private final class Seen<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    var value: Value {
      lock.withLock { stored }
    }

    init(_ initial: Value) {
      stored = initial
    }

    func update(_ change: (inout Value) -> Void) {
      lock.withLock { change(&stored) }
    }
  }

  /// Every step reads as its own line.
  @Test
  internal func everyStepHasItsOwnNote() {
    let notes = Fixture.phases.map(\.note)
    #expect(notes.allSatisfy { !$0.isEmpty })
    #expect(Set(notes).count == notes.count)
  }

  /// Steps reach the observer of the signature that reports them.
  @Test
  internal func reportedStepsReachTheObserver() {
    let seen = Seen([DocumentSigningPhase]())
    let observer: @Sendable (DocumentSigningPhase) -> Void = { phase in
      seen.update { $0.append(phase) }
    }
    DocumentSigner.$phaseObserver.withValue(observer) {
      DocumentSigner.report(.phone)
      DocumentSigner.report(.timestamp)
    }
    DocumentSigner.report(.validation)
    #expect(seen.value == [.phone, .timestamp])
  }

  /// The certificate is read once per pairing and read again for
  /// another.
  @Test
  internal func certificateIsReadOncePerPairing() async throws {
    let store = DocumentSigner.RemoteCertificateStore()
    let reads = Seen(0)
    let fetch: @Sendable () -> Data = {
      reads.update { $0 += 1 }
      return Fixture.certificate
    }
    _ = try await store.certificate(for: Fixture.firstPair, fetch: fetch)
    _ = try await store.certificate(for: Fixture.firstPair, fetch: fetch)
    #expect(reads.value == 1)
    _ = try await store.certificate(for: Fixture.secondPair, fetch: fetch)
    #expect(reads.value == 2)
    await store.forget()
    _ = try await store.certificate(for: Fixture.secondPair, fetch: fetch)
    #expect(reads.value == 3)
  }

  /// A failed read is not held: the next signature reads again.
  @Test
  internal func failedReadIsRetried() async throws {
    let store = DocumentSigner.RemoteCertificateStore()
    await #expect(throws: ReadFailure.self) {
      try await store.certificate(for: Fixture.firstPair) { throw ReadFailure() }
    }
    let certificate = try await store.certificate(for: Fixture.firstPair) {
      Fixture.certificate
    }
    #expect(certificate == Fixture.certificate)
  }
}
