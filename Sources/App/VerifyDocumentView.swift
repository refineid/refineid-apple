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

        case .report(let rows, _):
          reportSections(rows)

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
        VerifyDocumentRow(indicator: .fails) {
          PersonRowLabel(configured: false)
        } value: {
          Text(text("verify.errorUnsupported", "The signature profile is not supported."))
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
      _ rows: [VerifyDocumentModel.SignatureRow]
    ) -> some View {
      Section {
        VerifyDocumentRow(indicator: nil) {
          Text(text("signing.document", "Document"))
        } value: {
          Text(model.documentName)
            .fixedSize(horizontal: false, vertical: true)
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
        VerifyDocumentRow(indicator: nil) {
          PersonRowLabel(configured: report.isValid)
        } value: {
          Text(holder(of: report))
            .textSelection(.enabled)
            .accessibilityIdentifier("verifySigner")
        }
        factRow(text("verify.intact", "Document intact"), holds: report.documentIntact)
        factRow(text("verify.signature", "Signature"), holds: report.signatureValid)
        factRow(text("verify.chain", "Certificate chain"), holds: report.chainVerified)
        factRow(text("verify.timestamp", "Timestamp"), timestampValue(of: report))
        factRow(
          text("verify.revocation", "Revocation"),
          revocationValue(report.revocation, checking: checking)
        )
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

    /// One fact row: its name, the value line under it when there is
    /// one, and the indicator column.
    private func factRow(
      _ name: String,
      _ value: VerifyDocumentRowValue
    ) -> some View {
      VerifyDocumentRow(indicator: value.indicator) {
        Text(name)
      } value: {
        if let line = value.line {
          Text(line)
            .accessibilityLabel(Text(verbatim: value.accessibilityLine))
        }
      }
    }

    private func factRow(_ name: String, holds: Bool) -> some View {
      factRow(name, VerifyDocumentRowValue(indicator: holds ? .holds : .fails))
    }

    private func formatted(_ date: Date) -> String {
      date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The timestamp row of one signature: the best signature time,
    /// which is the earliest anchored time, a claimed time marked
    /// unproven, a failed token, or none.
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
        return VerifyDocumentRowValue(indicator: .progress)
      }
      switch revocation {
      case .good:
        return VerifyDocumentRowValue(indicator: .holds)

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
