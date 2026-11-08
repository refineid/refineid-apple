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
    @ObservedObject private var trustedLists = TrustedListStore.shared
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
        VerifyTrustedListsSection(trustedLists: trustedLists)
      }
      .navigationTitle(text("verify.title", "Verify"))
      .task { await trustedLists.refreshIfNeeded() }
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
        VerifySignatureSection(entry: row.entry, checking: row.checking)
      }
      Section {
        Button(text("verify.another", "Verify another document")) {
          model.reset()
          importing = true
        }
        .accessibilityIdentifier("verifyAnotherDocument")
      }
    }

    private func text(
      _ key: StaticString,
      _ fallback: String.LocalizationValue
    ) -> String {
      VerifyText.text(key, fallback)
    }
  }

#endif
