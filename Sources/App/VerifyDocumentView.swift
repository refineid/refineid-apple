// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// Verifies a chosen signed PDF and reports each signature's facts.
  internal struct VerifyDocumentView: View {
    private static let supportedDocumentTypes: [UTType] = {
      var types: [UTType] = [.pdf]
      if let asice = UTType("org.etsi.asic-e") {
        types.append(asice)
      }
      if let bdoc = UTType("ee.ria.bdoc") {
        types.append(bdoc)
      }
      for ext in ["asice", "sce", "bdoc"] {
        if let type = UTType(filenameExtension: ext, conformingTo: .data), !types.contains(type) {
          types.append(type)
        }
      }
      return types
    }()

    @StateObject private var model = VerifyDocumentModel()
    @State private var importing = false

    internal var body: some View {
      Form {
        switch model.phase {
        case .idle:
          chooseSection

        case .verifying:
          Section {
            ProgressView(text("verify.progress", "Verifying"))
              .frame(maxWidth: .infinity)
          }

        case .report(let rows, let documentTimestamps):
          reportSections(rows, documentTimestamps: documentTimestamps)

        case .failed(let message):
          Section {
            CredentialOutcomeText(message: message, tone: .failure)
          }
          chooseSection
        }
      }
      .navigationTitle(text("verify.title", "Verify"))
      .fileImporter(
        isPresented: $importing,
        allowedContentTypes: Self.supportedDocumentTypes
      ) { result in
        if case .success(let url) = result {
          model.verify(url: url)
        }
      }
    }

    private var chooseSection: some View {
      Section {
        Button(text("verify.choose", "Choose a signed document")) {
          importing = true
        }
        .accessibilityIdentifier("verifyChooseDocument")
      }
    }

    private var unsupportedSection: some View {
      Section {
        LabeledContent {
          VerifyDocumentRowValue(
            text: text("verify.errorUnsupported", "The signature profile is not supported."),
            indicator: .fails
          )
        } label: {
          PersonRowLabel(configured: false)
        }
      } header: {
        sectionHeader
      }
    }

    private var sectionHeader: some View {
      Text(text("verify.signature", "Signature"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private func reportSections(
      _ rows: [VerifyDocumentModel.SignatureRow],
      documentTimestamps: [TimestampState]
    ) -> some View {
      Section {
        LabeledContent(text("signing.document", "Document")) {
          Text(model.documentName)
            .multilineTextAlignment(.trailing)
        }
        ForEach(Array(documentTimestamps.enumerated()), id: \.offset) { stamp in
          factRow(text("verify.documentTimestamp", "Document timestamp")) {
            timestampValue(stamp.element)
          }
        }
      }
      ForEach(rows, id: \.rowIndex) { row in
        switch row.entry {
        case .judged(let report):
          signatureSection(report, checking: row.checking)

        case .unsupported:
          unsupportedSection
        }
      }
      Section {
        Button(text("verify.another", "Verify another document")) {
          model.reset()
          importing = true
        }
        .accessibilityIdentifier("verifyAnotherDocument")
      }
    }

    private func signatureSection(
      _ report: DocumentVerification.SignatureReport,
      checking: Bool
    ) -> some View {
      Section {
        LabeledContent {
          Text(holder(of: report))
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("verifySigner")
        } label: {
          PersonRowLabel(configured: report.isValid)
        }
        factRow(text("verify.intact", "Document intact"), holds: report.documentIntact)
        factRow(text("verify.signature", "Signature"), holds: report.signatureValid)
        factRow(text("verify.chain", "Certificate chain"), holds: report.chainVerified)
        factRow(text("verify.timestamp", "Timestamp")) {
          timestampValue(of: report)
        }
        factRow(text("verify.revocation", "Revocation")) {
          revocationValue(report.revocation, checking: checking)
        }
      } header: {
        sectionHeader
      }
    }

    /// The signer's commonName as carried, with control and
    /// bidirectional-formatting characters left out so they cannot
    /// reorder or hide what is shown.
    private func holder(
      of report: DocumentVerification.SignatureReport
    ) -> String {
      DisplayedSignerName.text(of: report.signerCommonName)
    }

    /// One fact row: its name, then the value and the indicator at the
    /// trailing end, the indicator column the same on every row.
    private func factRow(
      _ name: String,
      value: () -> VerifyDocumentRowValue
    ) -> some View {
      LabeledContent(name) {
        value()
      }
    }

    private func factRow(_ name: String, holds: Bool) -> some View {
      factRow(name) {
        VerifyDocumentRowValue(indicator: holds ? .holds : .fails)
      }
    }

    private func formatted(_ date: Date) -> String {
      date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The timestamp row of one signature: the proven time, a claimed
    /// time marked unproven, a failed token, or none.
    private func timestampValue(
      of report: DocumentVerification.SignatureReport
    ) -> VerifyDocumentRowValue {
      if let proven = report.proofOfExistence {
        return VerifyDocumentRowValue(text: formatted(proven), indicator: .holds)
      }
      if let claimed = report.claimedTime {
        return unprovenValue(claimed)
      }
      if report.hasInvalidTimestamp {
        return VerifyDocumentRowValue(indicator: .fails)
      }
      return VerifyDocumentRowValue(secondaryText: text("verify.timestampNone", "None"))
    }

    private func timestampValue(_ state: TimestampState) -> VerifyDocumentRowValue {
      switch state {
      case .anchored(let proven):
        VerifyDocumentRowValue(text: formatted(proven), indicator: .holds)

      case .claimed(let claimed):
        unprovenValue(claimed)

      case .invalid, .unsupported:
        VerifyDocumentRowValue(indicator: .fails)
      }
    }

    private func unprovenValue(_ claimed: Date) -> VerifyDocumentRowValue {
      VerifyDocumentRowValue(
        text: formatted(claimed),
        secondaryText: text("verify.timestampUnproven", "Unproven")
      )
    }

    private func revocationValue(
      _ revocation: RevocationState,
      checking: Bool
    ) -> VerifyDocumentRowValue {
      if checking {
        return VerifyDocumentRowValue(progress: true)
      }
      switch revocation {
      case .good(let evidenceTime):
        return VerifyDocumentRowValue(text: formatted(evidenceTime), indicator: .holds)

      case .revoked:
        return VerifyDocumentRowValue(text: text("verify.revoked", "Revoked"), indicator: .fails)

      case .unavailable:
        return VerifyDocumentRowValue(secondaryText: text("verify.notChecked", "Not checked"))
      }
    }

    private func text(
      _ key: StaticString,
      _ fallback: String.LocalizationValue
    ) -> String {
      String(localized: key, defaultValue: fallback, table: "DocumentSigning")
    }
  }

#endif
