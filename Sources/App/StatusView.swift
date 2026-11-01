// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Mac window: whether the card can log you in, and signing a
  /// document with it.
  ///
  /// It stays small. The login row does zero card I/O - it reads only
  /// what `ctkd` has already published. Once that identity is ready, the
  /// health key starts one short retry-counter probe. It never polls and
  /// never delays identity presentation or signing controls.
  ///
  /// Signing lives here rather than in a window of its own: dropping a
  /// document on the app is the thing a holder will try, and the app
  /// they dropped it on should be the one that signs it.
  internal struct StatusView: View {
    private static let spacing: CGFloat = 14
    private static let padding: CGFloat = 24

    /// The narrowest the window may be, which grows with the text
    /// inside it so a larger size widens the window instead of
    /// wrapping every label in it.
    @ScaledMetric(relativeTo: .body)
    private var minimumWidth: CGFloat = 560

    internal let model = LoginIdentityModel.shared
    @ObservedObject internal var retryHealth = CredentialRetryHealth.shared
    @ObservedObject internal var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared
    internal let remoteRegistry = PersistentTokenRegistry.shared
    @State private var signing = SignDocumentModel()

    /// Notices a card waiting to be taken into use, and carries the
    /// model its activation form works through.
    private let activation = ActivationWatch.shared
    @State private var offeringNumber = false
    @State private var hasStoredNumber = false
    @State private var pin2 = ""
    @State private var accessNumber = ""
    @State private var format = SignatureFormat.pades

    /// The signing state, readable by the split-out outcome section.
    internal var signingModel: SignDocumentModel { signing }

    /// Ready when a document is waiting and PIN 2 has been entered for
    /// it: PIN 2 is asked for every signature or batch and kept no longer
    /// (RAPP v26.10.29 §11 item 2).
    private var canSign: Bool {
      availability == .ready
        && signing.pending != nil
        && (!asksLocalPin2 || Self.isEntryComplete(pin2))
        && !signing.working
        // Not while the card is being read for the stamp: it is one
        // card, and asking it to sign mid-read is asking it to be in
        // two places.
        && !signing.readingStamp
    }

    /// Whether an unready card is provably on a contactless
    /// interface, which is the one state that asks for an access
    /// number.
    private var awaitingAccessNumber: Bool {
      #if FEATURE_CONTACTLESS
        availability == .cardWithoutIdentity
          && cardPresence.isContactlessCardPresent
      #else
        false
      #endif
    }

    internal var body: some View {
      VStack(alignment: .leading, spacing: Self.spacing) {
        statusForm
        if demoMode.isActive {
          CardSetupFooter(isDemonstration: true)
        }
      }
      .padding(Self.padding)
      .frame(minWidth: minimumWidth, alignment: .leading)
      #if REFINEID_REMOTE_CARD
        .toolbar {
          // A card awaiting activation is set up here and nowhere else.
          if !activation.awaitsActivation {
            ToolbarItem(placement: .primaryAction) {
              RemoteUseButton()
            }
          }
        }
      #endif
      .task {
        #if FEATURE_CONTACTLESS
          SealedCardSection.withdrawOfferedNumber()
        #endif
      }
      .onAppear(perform: handleAppear)
      .onChange(of: availability) { _, now in
        react(to: now)
        observeActivation()
      }
      .onChange(of: demoMode.isActive) { _, active in
        if active {
          react(to: availability)
          observeActivation()
          seedVirtualRequestIfNeeded()
        }
      }
      .onChange(of: demoMode.revision) { _, _ in
        react(to: availability)
        observeActivation()
        seedVirtualRequestIfNeeded()
      }
      .onChange(of: offeringNumber || awaitingAccessNumber) { _, _ in
        observeActivation()
      }
      .onChange(of: cardPresence.isContactlessCardPresent) { _, _ in
        refreshStoredNumber()
      }
      .onChange(of: activation.defersRemoval) { wasDeferred, isDeferred in
        guard wasDeferred, !isDeferred, availability == .noCard else { return }
        react(to: .noCard)
      }
      .onDisappear { activation.stop() }
      .acknowledgesFailure(of: signing)
      .asksAboutUnsaved(for: signing)
      .announcesOutcome(signing.notice)
      .announcesOutcome(activation.management.failure)
      .announcesOutcome(activation.management.notice)
    }

    @ViewBuilder private var statusForm: some View {
      Form {
        formBody
      }
      .formStyle(.grouped)
      // A form is a scroll view; one that fits its window stays still.
      .scrollBounceBehavior(.basedOnSize)
      .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var formBody: some View {
      if offeringNumber || awaitingAccessNumber {
        SealedCardSection(offering: $offeringNumber, tryingStored: hasStoredNumber)
      } else if activation.awaitsActivation {
        activationSection
      } else if activation.isReading {
        readingSection
      } else if shouldShowPairingPrompt {
        pairingPromptSection
      } else {
        readySection
      }
    }

    @ViewBuilder private var readySection: some View {
      let stateView = IdentityStateView(
        availability: availability,
        warnsUnavailableCard: activation.warnsUnavailableCard
      )
      stateView
        .accessibilityIdentifier("loginIdentityStatus")
      if availability != .noCard || !signing.queued.isEmpty || signing.pending != nil {
        StatusDocumentSection(
          signing: signing,
          format: $format,
          onChoose: { choose() },
          onAccept: { urls in accept(urls) }
        )
        StatusSignatureSection(
          signing: signing,
          format: $format,
          pin2: $pin2,
          accessNumber: $accessNumber,
          asksLocalPin2: asksLocalPin2,
          canSign: canSign,
          onSign: { sign() }
        )
      }
      outcomeSection
    }

    private func handleAppear() {
      model.refresh()
      react(to: availability)
      observeActivation()
      if demoMode.isActive {
        seedVirtualRequestIfNeeded()
      }
      #if DEBUG
        let targets = DebugSampleDocuments.targetDocuments()
        if !targets.isEmpty, signing.queued.isEmpty {
          _ = accept(targets)
        } else if DebugSampleDocuments.isEnabled(), signing.queued.isEmpty {
          _ = accept(DebugSampleDocuments.seeded())
        }
      #endif
    }

    private func seedVirtualRequestIfNeeded() {
      guard DemoMode.shared.isActive,
        DemoMode.shared.state.device.pendingSigningRequest,
        signing.queued.isEmpty,
        signing.pending == nil
      else { return }
      _ = accept([Self.demoDocumentURL()])
    }

    private func observeActivation() {
      activation.observe(
        availability: availability,
        paused: offeringNumber || awaitingAccessNumber,
        identity: model
      )
    }

    /// Whether a stored number exists to try before asking for one.
    ///
    /// Refreshed whenever the card set changes: the entry must only
    /// appear when nothing is stored or the CAN in memory just failed.
    private func refreshStoredNumber() {
      #if FEATURE_CONTACTLESS
        hasStoredNumber = CardCredentialStore.hasStoredNumbers()
      #else
        hasStoredNumber = false
      #endif
    }

    /// Clears what a card took with it, and keeps the stored-number flag
    /// current.
    private func react(to availability: LoginIdentityModel.Availability) {
      refreshStoredNumber()
      switch availability {
      case .ready:
        offeringNumber = false
        retryHealth.refreshFromReader()

      case .cardWithoutIdentity:
        retryHealth.clear()

      case .noCard:
        // A CCID protocol reset can publish this between T=Any and its
        // successful T=0/T=1 fallback. Defer removal cleanup until the
        // card operation itself has ended.
        guard !activation.defersRemoval, !signing.working else { return }
        retryHealth.clear()
        signing.cardRemoved()
        pin2 = ""
        accessNumber = ""
      // The offered access number deliberately survives this state:
      // a contactless card leaves the field between taps, and the
      // offer exists to serve the next tap. Withdrawing it here once
      // deleted the number in the moment between lifting the card
      // and laying it back, so the mint it was typed for read
      // nothing. Launch and quit are where it is withdrawn.
      }
    }

    /// Takes a dropped document of any type: a PDF is signed in place
    /// by default, anything else travels in an ASiC-E container.
    ///
    /// The shape is decided by the whole pile and not by what just
    /// arrived. Dropping one PDF onto a spreadsheet already waiting
    /// would otherwise leave PAdES chosen for a set that cannot take
    /// it, and the card would be asked before the spreadsheet refused.
    private func accept(_ urls: [URL]) -> Bool {
      guard !urls.isEmpty else { return false }
      signing.accept(urls)
      format = Self.sharedFormat(for: signing.queued)
      pin2 = ""
      return true
    }

    /// Opens the chooser, which may pick several documents to pile.
    private func choose() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
      _ = accept(panel.urls)
    }

    /// Signs, then asks where the signature goes.
    ///
    /// The panel opens once the signature is finished in memory, so
    /// the name it proposes carries the best signature time.
    private func sign() {
      guard canSign, let source = signing.pending else { return }
      // Several documents take one container between them, so they ask
      // for one file. Several PDFs each keep their own signature
      // inside themselves, so those ask for a folder.
      let documents = signing.queued
      let several = documents.count > 1
      let separately = several && format == .pades
      let entry = Self.isEntryComplete(pin2) ? pin2 : ""
      if asksLocalPin2, entry.isEmpty { return }
      pin2 = ""
      let number = accessNumber
      let chosenFormat = format
      #if DEBUG
        // An unattended destination never asks, so one that is an
        // original is refused before the card is touched.
        if !separately, let unattended = SignedOutput.unattendedDestination(),
          SignDocumentModel.isOriginal(unattended, among: documents)
        {
          signing.report(String(localized: "The signed document cannot replace the original."))
          return
        }
      #endif
      let file: SignDocumentModel.DestinationChoice = { signed, typedName in
        await SignedOutput.chooseFile(
          for: documents, format: chosenFormat, signed: signed, typedName: typedName
        )
      }
      signing.beginAction()
      Task {
        if separately {
          await signing.signAll(
            pin2: entry, accessNumber: number, format: chosenFormat
          ) {
            await SignedOutput.chooseFolder(startingAt: source.deletingLastPathComponent())
          }
        } else if several {
          await signing.signTogether(pin2: entry, destination: file)
        } else {
          await signing.sign(
            pin2: entry, accessNumber: number, format: chosenFormat, destination: file
          )
        }
        if signing.lastActionSignedSomething {
          signing.clearQueue()
        }
      }
    }

    // PIN 2 for a paired phone is collected on that phone, not here, for
    // every signature or batch, and kept no longer. A local reader
    // collects PIN 2 in this window. The Mac does not send PIN 2.
  }

#endif
