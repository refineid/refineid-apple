// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Observation

  /// State for signing one document: the file chosen, the PIN2 entry,
  /// and what happened.
  ///
  /// The signed file lands beside the original, named for the instant
  /// it was signed, so signing twice never overwrites and the order is
  /// readable from the directory listing.
  @MainActor
  @Observable
  internal final class SignDocumentModel {
    /// The document waiting to be signed.
    internal private(set) var pending: URL?

    /// Everything dropped in one go, in the order it will be signed.
    ///
    /// A day's work arrives together, and signing it one file at a
    /// time means one drop, one panel and one PIN for each.
    internal private(set) var queued: [URL] = []

    /// What became of each document of a batch, as sentences.
    internal private(set) var batchOutcomes: [String] = []

    /// Whether a signature is in flight.
    internal private(set) var working = false

    /// Whether the signature in flight is authorized on the paired phone.
    internal private(set) var signsOnPhone = false

    /// Whether a pile is being signed one document after another.
    internal private(set) var signingPile = false

    /// What went wrong, as one user-facing sentence.
    internal private(set) var failure: String?

    /// The failure the holder has yet to acknowledge.
    ///
    /// Held back while a pile is signed, so one alert reports the pile.
    internal var unacknowledgedFailure: String? {
      signingPile ? nil : failure
    }

    /// Where the signed file landed.
    internal private(set) var signed: URL?

    /// The complete visible statement read from the card, with
    /// handwriting when the card carries it and identity alone otherwise.
    internal private(set) var stampState: DocumentStampState?

    /// Changes whenever the card leaves, invalidating card work already
    /// awaiting an answer without cancelling work that may still complete.
    @ObservationIgnored internal private(set) var cardAppearance = 0

    /// A non-fatal note about what the visible stamp could contain.
    internal private(set) var stampFailure: String?

    /// A non-fatal fact the holder must see beside the signed output.
    internal private(set) var notice: String?

    /// Whether the card is being read for the signature right now.
    internal private(set) var readingStamp = false

    /// Whether the last sign action produced at least one signature.
    ///
    /// The one thing the PIN 2 cache needs to know: a PIN it should
    /// remember is one a signature accepted. Reset when an action
    /// begins, set as each document completes.
    internal private(set) var lastActionSignedSomething = false

    /// Adds documents to the pile, ignoring ones already in it.
    ///
    /// Dropping again piles onto what is there rather than replacing
    /// it, so a stack of documents is built up and signed in one pass.
    /// The newest addition is the one whose options are shown; the
    /// rest are signed with the same choices.
    internal func accept(_ urls: [URL]) {
      let present = Set(queued.map(\.standardizedFileURL))
      let additions = urls.filter { !present.contains($0.standardizedFileURL) }
      queued.append(contentsOf: additions)
      batchOutcomes = []
      guard let focus = additions.first ?? urls.first else { return }
      accept(focus)
    }

    /// Marks the start of one sign action, so acceptance is judged
    /// over the whole action rather than the last document alone.
    internal func beginAction() {
      lastActionSignedSomething = false
    }

    /// Empties the pile once its documents are signed, keeping the
    /// outcome on screen.
    internal func clearQueue() {
      queued = []
      pending = nil
    }

    /// Takes one document out of the pile.
    ///
    /// A pile is built by dropping, and a wrong file dropped into it
    /// has to come out again without emptying the pile and starting
    /// over. Removing the document the options are shown for moves
    /// them to the next one, and removing the last leaves the window
    /// as it was before anything was dropped.
    internal func remove(_ url: URL) {
      let target = url.standardizedFileURL
      queued.removeAll { $0.standardizedFileURL == target }
      batchOutcomes = []
      guard !queued.isEmpty else {
        clear()
        return
      }
      if pending?.standardizedFileURL == target {
        pending = queued.first
      }
    }

    /// Points the model at one document of a batch.
    internal func focus(on url: URL) {
      pending = url
    }

    /// Records what became of each document of a batch.
    internal func record(batch outcomes: [String]) {
      batchOutcomes = outcomes
    }

    /// Accepts a dropped or chosen file.
    internal func accept(_ url: URL) {
      if queued.isEmpty {
        queued = [url]
      }
      pending = url
      failure = nil
      signed = nil
      stampState = nil
      stampFailure = nil
      notice = nil
    }

    /// The page mark built from the identity the card supplied.
    internal func stampMark() -> StampMark? {
      stampState.map { StampRenderer.mark($0.statement) }
    }

    /// Reads the stamp identity and any handwritten signature off the card.
    ///
    /// Only a complete access number is taken to the card. A number
    /// is six digits, so anything shorter is not a wrong number, it
    /// is a number still being typed - reading it would refuse the
    /// holder's own card and say so while they were mid-entry.
    /// Reads only the data groups the chosen style needs.
    internal func readStamp(
      accessNumber digits: String,
      style: DocumentStampStyle
    ) async {
      guard digits.count == CardAccessNumber.digitCount else {
        stampState = nil
        stampFailure = nil
        return
      }
      guard !readingStamp else { return }
      readingStamp = true
      stampState = nil
      stampFailure = nil
      let appearance = cardAppearance
      defer { readingStamp = false }
      let outcome = await CardMaintenance.displayedSignature(
        accessNumber: digits,
        includePortrait: style.readsPortrait
      )
      guard appearance == cardAppearance else { return }
      applyStampOutcome(outcome)
    }

    /// Applies one card read atomically, so a failure can never retain
    /// another card holder's visible identity.
    internal func applyStampOutcome(
      _ outcome: CardMaintenance.SignatureOutcome
    ) {
      stampState = nil
      stampFailure = nil
      switch outcome {
      case .mark(let mark):
        let artwork: SignatureArtwork.Artwork?
        if let bytes = mark.bytes {
          guard let traced = SignatureArtwork.traced(bytes) else {
            stampFailure = String(
              localized: "The signature image could not be read."
            )
            return
          }
          artwork = traced
        } else {
          artwork = nil
          stampFailure = String(
            localized:
              "No handwritten signature; the stamp will show the certificate identity."
          )
        }
        stampState = DocumentStampState(
          statement: StampRenderer.Statement(
            name: mark.name,
            identifier: mark.identifier,
            signature: artwork,
            givenName: mark.givenName,
            surname: mark.surname
          ),
          signerCertificate: mark.certificate,
          portrait: mark.portrait
        )

      case .absent:
        stampFailure = String(
          localized: "The certificate identity could not be read."
        )

      case .imageUnreadable:
        stampFailure = String(
          localized:
            "The handwritten signature could not be read; no visible stamp was added."
        )

      case .wrongAccessNumber:
        stampFailure = String(
          localized: "That card access number was refused."
        )

      case .noCard:
        stampFailure = String(localized: "No readable card.")
      }
    }

    /// Forgets the pending file and any outcome.
    internal func clear() {
      pending = nil
      queued = []
      batchOutcomes = []
      failure = nil
      signed = nil
      stampState = nil
      stampFailure = nil
      notice = nil
    }

    /// Starts one signing attempt and captures its card appearance.
    ///
    /// Internal, not private: the container signing in
    /// SignDocumentModel+Batch.swift runs the same lifecycle.
    internal func beginSigning() -> Int {
      working = true
      signsOnPhone = DocumentSigner.usesRappSigning
      failure = nil
      signed = nil
      notice = nil
      return cardAppearance
    }

    /// Ends one signing attempt, whatever became of it.
    internal func endSigning() {
      working = false
      signsOnPhone = false
    }

    /// Holds failures back until the whole pile is signed.
    internal func beginPile() {
      signingPile = true
    }

    /// Ends a pile, leaving its one combined failure, if any, to acknowledge.
    internal func endPile(failing message: String?) {
      signingPile = false
      if let message {
        fail(message: message)
      }
    }

    /// Dismisses the failure once the holder has read it.
    internal func acknowledgeFailure() {
      failure = nil
    }

    /// Signs the pending document into `destination`.
    ///
    /// Where it goes is decided by the caller, before this is called
    /// and before the card is touched: the sandbox the App Store
    /// requires hands this app a dropped file and not the folder
    /// around it, so the write has to be granted through a save panel,
    /// and a panel raised after signing could be cancelled with a PIN2
    /// signature already spent.
    internal func sign(
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      to destination: URL
    ) async {
      guard let source = pending, !working else { return }
      // Replacing the original is refused rather than confirmed. It
      // destroys the only unsigned copy, and the signature is taken
      // over bytes already read into memory - so the file that
      // vanished would be the one the signature attests.
      guard destination.standardizedFileURL != source.standardizedFileURL else {
        failure = String(
          localized: "The signed document cannot replace the original."
        )
        return
      }
      let appearance = beginSigning()
      defer { endSigning() }
      if DemoMode.shared.isActive {
        await signWithVirtualCard(
          pin2: pin2,
          from: source,
          to: destination,
          appearance: appearance
        )
        return
      }
      do {
        switch format {
        case .asice:
          try await signContainer([source], pin2: pin2, to: destination)

        case .pades:
          try await signPdf(
            source, pin2: pin2, accessNumber: accessNumber, to: destination
          )
        }
        complete(with: destination)
      } catch {
        report(error, from: appearance)
      }
    }

    /// Records a completed write and releases the card identity state.
    internal func complete(with destination: URL) {
      signed = destination
      pending = nil
      stampState = nil
      stampFailure = nil
      lastActionSignedSomething = true
    }

    /// Fails the current signing operation with an error message.
    internal func fail(message: String) {
      failure = message
      signed = nil
      notice = nil
    }

    /// Removes outcomes and identity tied to a card that is no longer there.
    ///
    /// The chosen document remains ready for the next insertion.
    internal func cardRemoved() {
      cardAppearance &+= 1
      failure = nil
      stampState = nil
      stampFailure = nil
    }

    /// Sets the informational notice for the current document.
    internal func setNotice(_ value: String?) {
      notice = value
    }
  }

#endif
