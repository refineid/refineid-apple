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
    @State private var activation = ActivationWatch()
    @State private var pin2Cache = Pin2Cache()
    @State private var offeringNumber = false
    @State private var hasStoredNumber = false
    @State private var pin2 = ""
    @State private var accessNumber = ""
    @State private var format = SignatureFormat.pades

    #if FEATURE_CONTACTLESS
      /// Whether the holder has enabled contactless card reading.
      @AppStorage(AppSettings.contactlessEnabled)
      private var contactlessEnabled = true
    #endif

    /// The signing state, readable by the split-out outcome section.
    internal var signingModel: SignDocumentModel { signing }

    /// Ready when a document is waiting and a PIN 2 is available -
    /// either freshly entered, or remembered from a signature within
    /// the last minute.
    private var canSign: Bool {
      availability == .ready
        && signing.pending != nil
        && (!asksLocalPin2 || Self.isEntryComplete(pin2) || pin2Cache.isWarm)
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
        contactlessEnabled
          && availability == .cardWithoutIdentity
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
      .announcesOutcome(signing.failure)
      .announcesOutcome(signing.notice)
      .announcesOutcome(activation.management.failure)
      .announcesOutcome(activation.management.notice)
    }

    @ViewBuilder private var statusForm: some View {
      Form {
        formBody
      }
      .formStyle(.grouped)
      .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var formBody: some View {
      if offeringNumber || awaitingAccessNumber {
        SealedCardSection(offering: $offeringNumber, tryingStored: hasStoredNumber)
      } else if activation.awaitsActivation {
        CardActivationSection(model: activation.management) { model.refresh() }
        CardOutcomeSection(model: activation.management)
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
      if availability == .ready {
        LabeledContent("Person") {
          stateView
        }
        .accessibilityIdentifier("loginIdentityStatus")
      } else {
        stateView
          .accessibilityIdentifier("loginIdentityStatus")
      }
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
          pin2Cache: $pin2Cache,
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
    /// appear when nothing is stored or the stored numbers just failed.
    private func refreshStoredNumber() {
      #if FEATURE_CONTACTLESS
        hasStoredNumber = CardCredentialStore.hasStoredNumbers()
      #else
        hasStoredNumber = false
      #endif
    }

    /// Ready stands recovery down and a removed card resets its budget.
    ///
    /// The activation watch owns the unready path so inspection and
    /// recovery remain serialized.
    private func react(to availability: LoginIdentityModel.Availability) {
      refreshStoredNumber()
      switch availability {
      case .ready:
        model.cancelRecovery(cardLeft: false)
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
        model.cancelRecovery(cardLeft: true)
        signing.cardRemoved()
        pin2 = ""
        accessNumber = ""
        // A card that left takes the remembered PIN with it: the next
        // card, even the same one re-inserted, re-earns the memory.
        pin2Cache.clear()
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

    /// Asks where the signature goes, then signs.
    ///
    /// The panel runs here, from the button, and not inside the signing
    /// task: a modal panel raised from an async function blocks the
    /// main actor SwiftUI draws on, and a panel that never appears
    /// looks exactly like a button that does nothing.
    private func sign() {
      guard canSign, let source = signing.pending else { return }
      // Several documents take one container between them, so they ask
      // for one file. Several PDFs each keep their own signature
      // inside themselves, so those still ask for a folder.
      let several = signing.queued.count > 1
      let separately = several && format == .pades
      let folder =
        separately
        ? SignedOutput.chooseFolder(startingAt: source.deletingLastPathComponent())
        : nil
      let destination =
        separately ? nil : SignedOutput.chooseFile(for: signing.queued, format: format)
      guard separately ? folder != nil : destination != nil else { return }
      let entry = Self.isEntryComplete(pin2) ? pin2 : (pin2Cache.current() ?? "")
      if asksLocalPin2, entry.isEmpty { return }
      pin2 = ""
      let number = accessNumber
      let chosenFormat = format
      signing.beginAction()
      Task {
        if let folder {
          await signing.signAll(
            pin2: entry, accessNumber: number, format: chosenFormat, intoDirectory: folder
          )
        } else if let destination {
          if several {
            await signing.signTogether(pin2: entry, to: destination)
          } else {
            await signing.sign(
              pin2: entry, accessNumber: number, format: chosenFormat, to: destination
            )
          }
        }
        // Remember only a PIN a signature accepted, so a remembered
        // value is always known good and never spends an attempt; any
        // failure forgets it and asks for the PIN again.
        if signing.lastActionSignedSomething {
          if asksLocalPin2 { pin2Cache.remember(entry) }
          signing.clearQueue()
        } else if asksLocalPin2 {
          pin2Cache.clear()
        }
      }
    }

    // PIN 2 for a paired phone is collected on that phone, not here.
    // It is not stored in the iPhone app. The phone holds it in memory
    // for at most one minute so a pile of documents is one prompt.
    // A local reader still collects PIN 2 in this window.
    // The Mac does not send PIN 2.
  }

#endif
