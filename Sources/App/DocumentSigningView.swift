// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Foundation
  import SwiftUI
  import UniformTypeIdentifiers

  /// Multi-document qualified signing over a reader or Core NFC session.
  @MainActor
  internal struct DocumentSigningView: View {
    internal struct Input {
      internal let inputID = UUID()
      internal let name: String
      internal let data: Data
      internal let isPDF: Bool
    }

    private struct ExportDocument: FileDocument {
      static var readableContentTypes: [UTType] { [.data] }
      let data: Data

      init(data: Data) { self.data = data }

      init(configuration: ReadConfiguration) {
        data = configuration.file.regularFileContents ?? Data()
      }

      func fileWrapper(
        configuration _: WriteConfiguration
      ) -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
      }
    }

    private struct Output {
      let document: ExportDocument
      let name: String
      let contentType: UTType
    }

    internal let transport: CardMaintenance.Transport
    internal let cardAccessNumber: String?

    @Environment(\.dismiss)
    private var dismiss

    @State private var inputs: [Input] = []
    @State private var format: SignatureFormat = .pades
    @State private var pin2 = ""
    @State private var importsDocuments = false
    @State private var exportsDocument = false
    @State private var isSigning = false
    @State private var output: Output?
    @State private var message: String?
    @State private var messageTone: CredentialOutcomeText.Tone = .failure

    internal var body: some View {
      Form {
        DocumentSigningSections(
          inputs: $inputs,
          format: $format,
          pin2: $pin2,
          importsDocuments: $importsDocuments,
          isSigning: isSigning,
          canSign: canSign,
          pin2IsValid: pin2IsValid,
          requiresRequesterPIN2: requiresRequesterPIN2,
          message: message,
          messageTone: messageTone,
          onCommit: { Task { await sign() } }
        )
      }
      .navigationTitle(text("signing.title", "Sign documents"))
      .navigationBarTitleDisplayMode(.inline)
      .fileImporter(
        isPresented: $importsDocuments,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true,
        onCompletion: importResult
      )
      .fileExporter(
        isPresented: $exportsDocument,
        document: output?.document,
        contentType: output?.contentType ?? .data,
        defaultFilename: output?.name ?? "signed"
      ) { result in
        switch result {
        case .success:
          dismiss()

        case .failure:
          showFailure(
            text("error.export", "The signed file could not be saved."))
        }
      }
      .onAppear { seedVirtualRequestIfNeeded() }
      .onValueChange(of: DemoMode.shared.revision) { _ in
        seedVirtualRequestIfNeeded()
      }
    }

    private var pin2IsValid: Bool {
      Pin2(digits: pin2) != nil
    }

    private var canSign: Bool {
      !isSigning && !inputs.isEmpty && (!requiresRequesterPIN2 || pin2IsValid)
    }

    private var requiresRequesterPIN2: Bool {
      !DocumentSigner.usesRappSigning
    }

    private func importResult(_ result: Result<[URL], Error>) {
      do {
        let urls = try result.get()
        var imported: [Input] = []
        for url in urls {
          let accessed = url.startAccessingSecurityScopedResource()
          defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
          }
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          let isPDF = data.starts(with: Data("%PDF-".utf8))
          imported.append(
            Input(
              name: url.lastPathComponent,
              data: data,
              isPDF: isPDF))
        }
        inputs.append(contentsOf: imported)
        format = DocumentSigningSections.normalizedFormat(format, for: inputs)
        message = nil
      } catch {
        showFailure(
          text(
            "error.import",
            "The selected documents could not be read."))
      }
    }

    private func sign() async {
      guard canSign else { return }
      isSigning = true
      message = nil
      let enteredPIN2: String? = requiresRequesterPIN2 ? pin2 : nil
      defer {
        pin2 = ""
        isSigning = false
      }
      if DemoMode.shared.isActive {
        await signWithVirtualCard(pin2: enteredPIN2 ?? "")
        return
      }
      do {
        let data: Data
        if format == .pades, let input = inputs.first {
          let product = try await DocumentSigner.sign(
            input.data,
            named: input.name,
            reason: nil,
            location: nil,
            access: DocumentSigner.SigningAccess(
              pin2: enteredPIN2,
              transport: transport,
              cardAccessNumber: cardAccessNumber
            )
          )
          data = product.bytes
        } else {
          let objects = inputs.map { input in
            AsicSigner.dataObject(input.data, named: input.name)
          }
          data = try await AsicSigner.sign(
            objects,
            pin2: enteredPIN2,
            transport: transport,
            cardAccessNumber: cardAccessNumber)
        }
        output = Output(
          document: ExportDocument(data: data),
          name: SignedDocumentName.suggested(
            sourceNames: inputs.map(\.name),
            format: format,
            at: Date()),
          contentType: format == .pades
            ? .pdf
            : (UTType(filenameExtension: "asice") ?? .zip))
        finishSuccessfully()
      } catch {
        showFailure(DocumentSigningMessage.message(for: error))
      }
    }

    private func signWithVirtualCard(pin2: String) async {
      let result = await DemoMode.shared.authorizeQualifiedSignature(pin2: pin2)
      switch result {
      case .success:
        finishSuccessfully()

      case .invalidEntry:
        showFailure(
          text("error.pin2Format", "PIN 2 must contain 6 to 12 digits."))

      case .blocked:
        showFailure(
          text(
            "error.pin2Blocked",
            "PIN 2 is blocked. Reset it in PIN settings."))

      case .rejected(let remaining):
        showFailure(
          text("error.pin2Incorrect", "PIN 2 is incorrect.")
            + "\n"
            + String(
              format: text(
                "error.attempts",
                "You have %d attempts remaining."),
              Int(remaining)))

      case .refusedLowAttempts(let remaining):
        showFailure(
          text("error.operationRefused", "Operation refused")
            + "\n"
            + String(
              format: text(
                "error.attempts",
                "You have %d attempts remaining."),
              Int(remaining)))

      case .certificateUnavailable:
        showFailure(
          text(
            "error.signatureCertificate",
            "The signature certificate is unavailable."))

      case .transportFailure:
        showFailure(
          text("error.connection", "The card connection was lost."))
      }
    }

    private func seedVirtualRequestIfNeeded() {
      guard DemoMode.shared.isActive,
        DemoMode.shared.state.device.pendingSigningRequest,
        inputs.isEmpty
      else { return }
      inputs = [
        Input(
          name: text("demo.document", "Review document.pdf"),
          data: Data(
            "%PDF-1.4\n% Virtual demonstration document\n%%EOF".utf8),
          isPDF: true)
      ]
      format = .pades
    }

    private func showFailure(_ value: String) {
      messageTone = .failure
      message = value
    }

    /// A saved or demonstrated signature returns to the front page;
    /// only a failure keeps this screen, with its message.
    private func finishSuccessfully() {
      message = nil
      if output != nil {
        exportsDocument = true
      } else {
        dismiss()
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
