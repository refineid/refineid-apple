// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import SwiftUI

  /// The two questions the window asks about text rather than about the
  /// card: what to say while it is busy, and whether an entry could yet
  /// be a PIN.
  ///
  /// Neither reads the window's own state, so both live here and leave
  /// the view itself to the parts that do.
  extension StatusView {
    /// What the identity row and the offered features key on.
    ///
    /// Reads two observed facts - the token's publication and the
    /// slot's physical answer - so the row moves the moment either
    /// does. Here rather than in the view body only for the view
    /// type's length; it reads shared state, no private field.
    internal var availability: LoginIdentityModel.Availability {
      if DemoMode.shared.isActive {
        return DemoMode.shared.state.card.cardPresent ? .ready : .noCard
      }
      return LoginIdentityModel.resolved(
        tokenPublished: model.isReady,
        cardPresent: cardPresence.isCardPresent,
        holderAdvertising: holderIsAdvertising,
        hasBorrowedCertificate: hasBorrowedIdentity
      )
    }

    /// Whether the paired phone is on the network and serving a card.
    private var holderIsAdvertising: Bool {
      #if REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT
        remoteRegistry.holderIsAdvertising
      #else
        false
      #endif
    }

    /// Whether to prompt the user to connect a card reader or phone.
    internal var shouldShowPairingPrompt: Bool {
      #if REFINEID_REMOTE_CARD
        !DemoMode.shared.isActive
          && !cardPresence.isReaderCardPresent
          && !holderIsAdvertising
          && availability == .noCard
          && signingModel.pending == nil
          && signingModel.queued.isEmpty
          && !signingModel.working
      #else
        false
      #endif
    }

    /// Whether a paired phone has already answered with a certificate.
    private var hasBorrowedIdentity: Bool {
      #if REFINEID_REMOTE_CARD
        remoteRegistry.holderIsAdvertising && remoteRegistry.holderLine != nil
      #else
        false
      #endif
    }

    /// Whether this window collects PIN 2, or the paired phone does.
    internal var asksLocalPin2: Bool {
      !DocumentSigner.usesRappSigning
    }

    @ViewBuilder internal var readingSection: some View {
      IdentityStateView(availability: .cardWithoutIdentity, warnsUnavailableCard: false)
        .accessibilityIdentifier("loginIdentityStatus")
    }

    @ViewBuilder internal var pairingPromptSection: some View {
      #if REFINEID_REMOTE_CARD
        RemotePairingPromptView()
      #endif
    }

    /// The signature style every dropped document can take.
    ///
    /// A container suits any file; a PAdES signature suits only a PDF.
    /// So a batch takes PAdES when every document is a PDF, and a
    /// container otherwise.
    internal static func sharedFormat(for urls: [URL]) -> SignatureFormat {
      let everyOneAPdf = urls.allSatisfy { url in
        SignatureFormat.available(for: url).contains(.pades)
      }
      return everyOneAPdf ? .pades : .asice
    }

    /// What the drop area reads as: the file when there is one, how
    /// many when there is a pile, and that it is empty when it is.
    ///
    /// The names themselves are read from the rows below, so this says
    /// the size rather than reciting a stack of file names into a
    /// value that cannot be navigated.
    internal static func pileValue(_ documents: [URL]) -> String {
      guard let first = documents.first else {
        return String(localized: "none chosen")
      }
      guard documents.count > 1 else { return first.lastPathComponent }
      return String(localized: "\(documents.count) documents")
    }

    /// What the card is busy with, or nothing when it is not.
    ///
    /// Both notes live on the action row rather than in boxes of
    /// their own: that row is already there and half empty, and a
    /// section that appears and disappears steps the window every
    /// time the card is touched.
    internal static func progressNote(_ signing: SignDocumentModel) -> String? {
      if signing.working {
        return signing.signsOnPhone
          ? String(localized: "Continue on your phone")
          : String(localized: "Signing document…")
      }
      if signing.readingStamp {
        return String(localized: "Reading the card…")
      }
      return nil
    }

    /// Whether an entry could be a PIN2 at all.
    internal static func isEntryComplete(_ entry: String) -> Bool {
      (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(entry.count)
    }

    /// Creates or returns the demonstration PDF document URL.
    internal static func demoDocumentURL() -> URL {
      let tempDir = FileManager.default.temporaryDirectory
      let demoDocURL = tempDir.appendingPathComponent("Review document.pdf")
      if !FileManager.default.fileExists(atPath: demoDocURL.path) {
        let pdfData = Data("%PDF-1.4\n% Virtual demonstration document\n%%EOF".utf8)
        try? pdfData.write(to: demoDocURL, options: .atomic)
      }
      return demoDocURL
    }
  }

#endif
