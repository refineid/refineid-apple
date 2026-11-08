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
    /// The app's verifier, under the anchors the trusted lists yield
    /// and the clock.
    internal static let live = Self(
      anchors: { await TrustedListStore.shared.verificationAnchors() },
      verify: { document, anchors in
        try DocumentVerification.verify(document: document, anchors: anchors)
      },
      liveStatus: VerifyDocumentModel.liveStatus(of:),
      now: Date.init
    )

    /// The anchors to verify under, or why no trusted list could be
    /// read.
    internal let anchors:
      @Sendable () async -> Result<TrustAnchors, TrustedListStore.RefreshFailure>

    /// Verifies one document offline under the anchors.
    internal let verify:
      @Sendable (Data, TrustAnchors) throws -> DocumentVerification.DocumentReport

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

  /// The message when no trusted list has been read, so no anchor
  /// exists.
  private static var noTrustedListsMessage: String {
    text(
      "verify.errorNoTrustedLists",
      "The trusted lists have not been fetched yet, so no certificate chain can be verified.")
  }

  /// The message when no trusted list is stored and the device is
  /// offline, so none can be fetched.
  internal static var offlineWithoutTrustedListsMessage: String {
    text(
      "verify.errorOfflineNoTrustedLists",
      """
      No EU trusted lists are stored yet and this device is offline. \
      Connect to the internet once to fetch them; after that, documents verify offline too.
      """
    )
  }

  /// The message for a CMS SignedData file, which carries signatures
  /// this verifier does not verify.
  internal static var cmsSignedDataMessage: String {
    text("verify.errorCades", "This signature format (CAdES) can't be verified here yet.")
  }

  /// The extensions of CMS SignedData files (RFC 5751 section 3.2.1),
  /// in whatever encoding they hold it.
  private static let cmsSignedDataExtensions: Set<String> = ["p7m", "p7s", "p7c"]

  /// The message for a document without signatures.
  internal static var noSignaturesMessage: String {
    text("verify.errorNoSignatures", "The document carries no signatures.")
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
    // A file that is neither a PDF nor a signature container carries
    // no signature this verifier reads.
    case .notAPdf, .noSignatures:
      Self.noSignaturesMessage

    case .unreadable:
      Self.unreadableMessage

    case .cmsSignedData:
      Self.cmsSignedDataMessage

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

  /// The outcome of reading and verifying one document under `anchors`.
  nonisolated private static func outcome(
    _ load: @Sendable () throws -> Data,
    anchors: TrustAnchors,
    verify: @Sendable (Data, TrustAnchors) throws -> DocumentVerification.DocumentReport
  ) -> Result<DocumentVerification.DocumentReport, DocumentVerification.Failure> {
    guard let document = try? load() else { return .failure(.unreadable) }
    // A ZIP that is not an ASiC container, such as an office document,
    // is an unsigned document.
    if AsicVerification.isZipArchive(document), !AsicVerification.isAsicContainer(document) {
      return .failure(.noSignatures)
    }
    do {
      let report = try verify(document, anchors)
      // A report without a signature row has nothing to show but that.
      guard !report.signatures.isEmpty else { return .failure(.noSignatures) }
      return .success(report)
    } catch let failure as DocumentVerification.Failure {
      return .failure(failure)
    } catch {
      return .failure(.unreadable)
    }
  }

  /// What a verification without anchors says.
  ///
  /// Whether the document carries signatures at all needs no anchor, so an unsigned or
  /// unreadable one says that first; a signed one says why no trusted
  /// list could be read.
  private static func missingAnchorsMessage(
    _ failure: TrustedListStore.RefreshFailure,
    load: @escaping @Sendable () throws -> Data,
    verify: @escaping @Sendable (Data, TrustAnchors) throws -> DocumentVerification.DocumentReport
  ) async -> String {
    let anchorless = await Task.detached(priority: .userInitiated) {
      Self.outcome(load, anchors: .empty, verify: verify)
    }.value
    if case .failure(let unsigned) = anchorless {
      return Self.message(for: unsigned)
    }
    return failure == .offline ? Self.offlineWithoutTrustedListsMessage : Self.noTrustedListsMessage
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
    documentName = name
    let fileExtension = URL(filePath: name).pathExtension.lowercased()
    guard !Self.cmsSignedDataExtensions.contains(fileExtension) else {
      verification = nil
      phase = .failed(Self.cmsSignedDataMessage)
      return
    }
    phase = .verifying
    let verifier = dependencies.verify
    let anchorSource = dependencies.anchors
    verification = Task { [weak self] in
      let anchors: TrustAnchors
      switch await anchorSource() {
      case .success(let read):
        anchors = read

      case .failure(let failure):
        let message = await Self.missingAnchorsMessage(failure, load: load, verify: verifier)
        guard let self, !Task.isCancelled, generation == current else { return }
        phase = .failed(message)
        return
      }
      let outcome = await Task.detached(priority: .userInitiated) {
        Self.outcome(load, anchors: anchors, verify: verifier)
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
