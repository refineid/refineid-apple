// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import SwiftUI

/// Verifies one chosen signed document and holds its report.
///
/// The verdict is computed offline from the evidence the document
/// carries. A path certificate whose revocation the document left
/// unavailable is then asked of the network, and that answer is judged
/// at the time of the check. Each verification carries a generation;
/// a result or answer from an earlier one is dropped.
@MainActor
internal final class VerifyDocumentModel: ObservableObject {
  /// One signature found in the document, with whether its live
  /// revocation check is still running.
  internal struct SignatureRow: Sendable {
    internal let rowIndex: Int
    internal let generation: Int
    internal var entry: DocumentVerification.SignatureEntry
    internal var checking: Bool
  }

  internal enum Phase {
    case idle
    case verifying
    case report([SignatureRow], documentTimestamps: [TimestampState])
    case failed(String)
  }

  /// How a document becomes a report and a query a live answer.
  internal struct Dependencies: Sendable {
    /// The app's verifier, under the pinned anchors and the clock.
    internal static let live = Self(
      verify: { document in try DocumentVerification.verify(document: document) },
      liveStatus: VerifyDocumentModel.liveStatus(of:),
      now: Date.init
    )

    /// Verifies one document offline.
    internal let verify: @Sendable (Data) throws -> DocumentVerification.DocumentReport

    /// The live evidence for one path certificate, nil when none came.
    internal let liveStatus:
      @Sendable (DocumentVerification.RevocationQuery) async ->
        ValidationMaterialCollector.StatusEvidence?

    /// The time a live answer is judged at.
    internal let now: @Sendable () -> Date
  }

  private static var unreadableMessage: String {
    text("verify.errorUnreadable", "The document could not be read.")
  }

  @Published internal private(set) var phase = Phase.idle

  /// The verified file's name, for the report heading.
  @Published internal private(set) var documentName = ""

  /// The running verification, cancelled by `reset()` and by a newer
  /// verification.
  internal private(set) var verification: Task<Void, Never>?

  /// The current verification's generation.
  private var generation = 0

  private let dependencies: Dependencies

  internal convenience init() {
    self.init(dependencies: .live)
  }

  internal init(dependencies: Dependencies) {
    self.dependencies = dependencies
  }

  private static func message(
    for failure: DocumentVerification.Failure
  ) -> String {
    switch failure {
    case .notAPdf:
      text("error.notPDF", "The selected file is not a PDF.")

    case .unreadable:
      Self.unreadableMessage

    case .noSignatures:
      text("verify.errorNoSignatures", "The document carries no signatures.")

    case .unsupportedProfile:
      text("verify.errorUnsupported", "The signature profile is not supported.")
    }
  }

  private static func text(
    _ key: StaticString,
    _ fallback: String.LocalizationValue
  ) -> String {
    String(localized: key, defaultValue: fallback, table: "DocumentSigning")
  }

  /// The live answer for one path certificate.
  nonisolated private static func liveStatus(
    of query: DocumentVerification.RevocationQuery
  ) async -> ValidationMaterialCollector.StatusEvidence? {
    guard let facts = CertificateFacts(der: query.certificate) else { return nil }
    do {
      return try await ValidationMaterialCollector.status(
        of: query.certificate,
        facts: facts,
        under: query.issuer,
        at: Date(),
        dependencies: .live
      )
    } catch let revoked as AuthenticatedRevocation {
      return revoked.evidence
    } catch {
      return nil
    }
  }

  /// The outcome of reading and verifying one document.
  nonisolated private static func outcome(
    _ load: @Sendable () throws -> Data,
    verify: @Sendable (Data) throws -> DocumentVerification.DocumentReport
  ) -> Result<DocumentVerification.DocumentReport, DocumentVerification.Failure> {
    guard let document = try? load() else { return .failure(.unreadable) }
    do {
      return .success(try verify(document))
    } catch let failure as DocumentVerification.Failure {
      return .failure(failure)
    } catch {
      return .failure(.unreadable)
    }
  }

  /// Whether a report still lacks revocation status a live answer could
  /// give.
  private static func needsLiveRevocation(
    _ entry: DocumentVerification.SignatureEntry
  ) -> Bool {
    guard case .judged(let report) = entry else { return false }
    return !report.pendingRevocationQueries.isEmpty
  }

  /// Verifies the document at one picked location.
  internal func verify(url: URL) {
    start(name: url.lastPathComponent) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
      }
      return try Data(contentsOf: url)
    }
  }

  /// Verifies one document already in memory.
  internal func verify(document: Data, name: String) {
    start(name: name) { document }
  }

  /// Returns the screen to the picker and stops any verification.
  internal func reset() {
    verification?.cancel()
    verification = nil
    generation += 1
    phase = .idle
    documentName = ""
  }

  /// Starts one verification, superseding any running one.
  private func start(name: String, load: @escaping @Sendable () throws -> Data) {
    verification?.cancel()
    generation += 1
    let current = generation
    phase = .verifying
    documentName = name
    let verifier = dependencies.verify
    verification = Task { [weak self] in
      let outcome = await Task.detached(priority: .userInitiated) {
        Self.outcome(load, verify: verifier)
      }.value
      guard let self, !Task.isCancelled, generation == current else { return }
      switch outcome {
      case .success(let report):
        let rows = report.signatures.enumerated().map { index, entry in
          SignatureRow(
            rowIndex: index,
            generation: current,
            entry: entry,
            checking: Self.needsLiveRevocation(entry)
          )
        }
        phase = .report(rows, documentTimestamps: report.documentTimestamps)
        await checkRevocation(of: rows, generation: current)

      case .failure(let failure):
        phase = .failed(Self.message(for: failure))
      }
    }
  }

  /// Applies live answers to each row still checking, dropping any
  /// that arrive for an earlier generation.
  private func checkRevocation(of rows: [SignatureRow], generation current: Int) async {
    for row in rows where row.checking {
      guard case .judged(let report) = row.entry else { continue }
      var ocspResponses: [Data] = []
      var revocationLists: [Data] = []
      for query in report.pendingRevocationQueries {
        switch await dependencies.liveStatus(query) {
        case .ocsp(let response):
          ocspResponses.append(response)

        case .revocationList(let list):
          revocationLists.append(list)

        case nil:
          continue
        }
      }
      let updated = report.withLiveRevocation(
        ocspResponses: ocspResponses,
        revocationLists: revocationLists,
        now: dependencies.now()
      )
      guard
        !Task.isCancelled,
        generation == current,
        case .report(var shown, let stamps) = phase,
        let index = shown.firstIndex(where: { shownRow in
          shownRow.rowIndex == row.rowIndex && shownRow.generation == current
        })
      else {
        return
      }
      shown[index].entry = .judged(updated)
      shown[index].checking = false
      phase = .report(shown, documentTimestamps: stamps)
    }
  }
}
