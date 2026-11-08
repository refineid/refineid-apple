// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// One document's name and what its verification found.
  internal struct VerifiedDocumentSections: View {
    internal let name: String
    @ObservedObject internal var model: VerifyDocumentModel

    internal var body: some View {
      Section {
        VerifyDocumentRow(indicator: nil) {
          Text(VerifyText.text("signing.document", "Document"))
        } value: {
          Text(name)
            .fixedSize(horizontal: false, vertical: true)
        }
        switch model.phase {
        case .idle, .verifying:
          ProgressView(VerifyText.text("verify.progress", "Verifying"))
            .frame(maxWidth: .infinity)

        case .report:
          EmptyView()

        case .failed(let message):
          CredentialOutcomeText(message: message, tone: .failure)
            .accessibilityIdentifier("verifyOutcome")
        }
      }
      if case .report(let rows, _) = model.phase {
        ForEach(rows, id: \.rowIndex) { row in
          VerifySignatureSection(entry: row.entry, checking: row.checking)
        }
      }
    }
  }

#endif
