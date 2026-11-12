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

    private struct Output {
      let document: SignedFileDocument
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
    @State private var cardAccessNumberEntry = ""
    @State private var importsDocuments = false
    @State private var exportsDocument = false
    @State private var isSigning = false
    @State private var output: Output?
    @State private var message: String?
    @State private var messageTone: CredentialOutcomeText.Tone = .failure
    #if DEBUG
      /// The notice of a development signature below the long-term
      /// level; the screen stays to show it after the save.
      @State private var developmentNotice: String?
    #endif

    internal var body: some View {
      Form {
        DocumentSigningSections(
          inputs: $inputs,
          format: $format,
          pin2: $pin2,
          cardAccessNumber: $cardAccessNumberEntry,
          importsDocuments: $importsDocuments,
          isSigning: isSigning,
          canSign: canSign,
          pin2IsValid: pin2IsValid,
          cardAccessNumberIsValid: localCardAccessNumberIsValid,
          requiresRequesterPIN2: requiresRequesterPIN2,
          needsCardAccessNumber: needsLocalCardAccessNumber,
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
          #if DEBUG
            if let developmentNotice {
              messageTone = .notice
              message = developmentNotice
              return
            }
          #endif
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

    private var localCardAccessNumberIsValid: Bool {
      CardAccessNumber(digits: cardAccessNumberEntry) != nil
    }

    private var canSign: Bool {
      !isSigning && !inputs.isEmpty && (!requiresRequesterPIN2 || pin2IsValid)
        && (!needsLocalCardAccessNumber || localCardAccessNumberIsValid)
    }

    private var requiresRequesterPIN2: Bool {
      !DocumentSigner.usesRappSigning
    }

    /// Whether this screen takes the card access number itself.
    ///
    /// A citizen card on the phone's own antenna needs its six printed
    /// digits; a reader holds the card already, a paired phone's card is
    /// opened on that phone, an organization card's channel is opened by
    /// PIN 2 with no digits at all, and a demonstration signs with no
    /// card. Without an identity yet the digits arrive here, beside
    /// PIN 2, instead of on the setup screen.
    private var needsLocalCardAccessNumber: Bool {
      cardAccessNumber == nil && transport == .nearField && requiresRequesterPIN2
        && !DemoMode.shared.isActive
        && !OrganizationCardStore.load(from: .standard)
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
      #if DEBUG
        developmentNotice = nil
      #endif
      let enteredPIN2: String? = requiresRequesterPIN2 ? pin2 : nil
      let enteredCardAccessNumber: String? =
        needsLocalCardAccessNumber ? cardAccessNumberEntry : cardAccessNumber
      defer {
        pin2 = ""
        cardAccessNumberEntry = ""
        isSigning = false
      }
      if DemoMode.shared.isActive {
        await signWithVirtualCard(pin2: enteredPIN2 ?? "")
        return
      }
      do {
        let signed = try await signedDocument(
          pin2: enteredPIN2,
          cardAccessNumber: enteredCardAccessNumber
        )
        output = Output(
          document: SignedFileDocument(data: signed.bytes),
          name: SignedDocumentName.suggested(
            sourceNames: inputs.map(\.name),
            format: format,
            at: signed.bestSignatureTime,
            marker: signed.nameMarker),
          contentType: format == .pades
            ? .pdf
            : (UTType(filenameExtension: "asice") ?? .zip))
        #if DEBUG
          developmentNotice = signed.belowLongTerm?.notice
        #endif
        finishSuccessfully()
      } catch {
        showFailure(DocumentSigningMessage.message(for: error))
      }
    }

    /// Signs the imported documents in memory.
    private func signedDocument(pin2: String?, cardAccessNumber: String?) async throws
      -> SignedDocument
    {
      if format == .pades, let input = inputs.first {
        let product = try await DocumentSigner.sign(
          input.data,
          named: input.name,
          reason: nil,
          location: nil,
          access: DocumentSigner.SigningAccess(
            pin2: pin2,
            transport: transport,
            cardAccessNumber: cardAccessNumber
          )
        )
        return SignedDocument(product)
      }
      let objects = inputs.map { input in
        AsicSigner.dataObject(input.data, named: input.name)
      }
      let product = try await AsicSigner.sign(
        objects,
        pin2: pin2,
        transport: transport,
        cardAccessNumber: cardAccessNumber)
      return SignedDocument(product)
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

    internal func showFailure(_ value: String) {
      messageTone = .failure
      message = value
    }

    /// A saved or demonstrated signature returns to the front page;
    /// only a failure keeps this screen, with its message.
    internal func finishSuccessfully() {
      message = nil
      if output != nil {
        exportsDocument = true
      } else {
        dismiss()
      }
    }

    internal func text(
      _ key: StaticString,
      _ fallback: String.LocalizationValue
    ) -> String {
      String(localized: key, defaultValue: fallback, table: "DocumentSigning")
    }
  }

#endif
