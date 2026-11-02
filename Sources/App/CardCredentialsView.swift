// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Setting the card up: the access number and the hold that registers the
/// card for Safari.
///
/// A personal card's setup takes no PIN: PIN 1 is asked for when the
/// card first signs and is held only in memory (RAPP v26.10.29 §11 item
/// 2). An organization card has no printed access number, and its entry
/// under the same label is its PIN 1, which opens the setup hold's PACE
/// and is spent there.
///
/// This is the screen that matters, so it is the one the app opens on.
/// Development builds keep technical state behind the Diagnostics row.
///
/// The access number and the action it enables form one operation;
/// starting over is the explicit forget action below.
///
/// Every control a test drives carries an accessibility identifier, and
/// the register of them is `UITestIdentifiers` in `Tests/RefineIDUITests`.
/// Identifiers rather than labels, because a label is localized: a device
/// set to Finnish would otherwise fail every query for a reason that has
/// nothing to do with the card. They cost nothing at runtime and they are
/// what VoiceOver already wants.
internal struct CardCredentialsView: View {
  // MARK: Nested Types

  internal enum CardConnectionPurpose: Sendable {
    case pinManagement
  }

  /// The scanner button beside the printed digits.
  internal enum Layout {
    internal static let canButtonSize = 44.0
    internal static let canButtonOuterPadding = -10.0
    internal static let cacheButtonHorizontalPadding: CGFloat = 12
    internal static let cacheButtonVerticalPadding: CGFloat = 6
    internal static let cacheButtonCornerRadius: CGFloat = 8
    internal static let primaryActionButtonHeight: CGFloat = 50
    internal static let disabledActionOpacity = 0.3
    internal static let connectedBadgeHorizontalPadding: CGFloat = 8
    internal static let connectedBadgeVerticalPadding: CGFloat = 3
    internal static let connectedBadgeOpacity = 0.15
  }

  // MARK: Static Properties

  internal static let sectionSpacing: CGFloat = 24

  /// Between a borrowed person and the control that drops them.
  internal static let holderActionSpacing: CGFloat = 12

  // MARK: Static Computed Properties

  /// The seal drawn beside document verification.
  ///
  /// A symbol added after the system running this build resolves to
  /// nothing and leaves the row without its mark, so the newer name is
  /// used only where it exists.
  internal static var verificationSymbolName: String {
    #if os(iOS)
      UIImage(systemName: "checkmark.seal.text.page") != nil
        ? "checkmark.seal.text.page" : "checkmark.seal"
    #else
      "checkmark.seal.text.page"
    #endif
  }

  // MARK: SwiftUI Properties

  // swiftlint:disable private_swiftui_state
  @StateObject internal var model = CardCredentialsModel()
  @ObservedObject internal var retryHealth = CredentialRetryHealth.shared
  #if os(iOS)
    @ObservedObject internal var demoMode = DemoMode.shared
  #endif
  @State internal var cardAccessNumberEntry = ""

  /// The kind of card the setup entry is for, as the last hold on the
  /// antenna found it; a personal card's until a hold says otherwise.
  @State internal var antennaCardKind = ContactlessCardKind.personal

  /// An organization card's setup entry: its PIN 1.
  ///
  /// It stands under the same "Card Access Number (CAN)" label, is held
  /// only until the hold that spends it starts, and is never written
  /// anywhere.
  @State internal var organizationPinEntry = ""
  @State internal var isScanning = false
  @State internal var scannerTorchEnabled = false
  @State internal var registrationReset = false
  @State internal var isRegistered = false
  @State internal var activation: ActivationClassification?
  @State internal var activationNeeds: CardActivationNeeds?
  @State internal var activationPinLengths: CardPinLengths?
  @State internal var flowState = CardSetupStateMachine.initialState
  @FocusState internal var isCardAccessNumberFieldFocused: Bool

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// The priming model lives here, above everything a hold hides.
    @StateObject internal var primingModel = CardPrimingModel()
    @ObservedObject internal var phoneRelay = PhonePersistentTokenRelay.shared
  #endif

  #if os(iOS)
    /// The holder names read from the live reader tokens.
    @State internal var readerHolders: [String] = []

    /// Pairing model that drives inline pairing on both iPad and iPhone.
    @StateObject internal var pairingModel = RappPairingModel()

    /// The Remote Access toggle, synced with the persisted holder choice.
    @State internal var remoteAccessEnabled = false

    /// The enable flow in flight, abandoned when the toggle flips back.
    @State internal var remoteAccessFlowID: UUID?

    /// Whether the access-denied redirect is on screen.
    @State internal var showingLocalNetworkDenied = false

  #endif
  // swiftlint:enable private_swiftui_state

  // MARK: Properties

  #if os(iOS)
    /// Live reader identities, when an iOS root provides them.
    internal let readerModel: ReaderIdentityModeModel?

    /// The requester's view of the selected remote card.
    internal let remoteModel: RemoteCardModel
  #endif

  // MARK: Computed Properties

  /// The complete visible CAN handed to signing and PIN management.
  ///
  /// These routes can establish and verify their own card session, so they
  /// become available at a personal card's six digits without requiring
  /// an earlier NFC read.
  internal var managementCardAccessNumber: String? {
    isCardAccessNumberEntryComplete ? cardAccessNumberEntry : nil
  }

  /// The point at which operations using the printed card number can be
  /// offered: a personal card's six digits.
  internal var isCardAccessNumberEntryComplete: Bool {
    cardAccessNumberEntry.count == CardAccessNumber.digitCount
  }

  /// Whether the setup entry for the card on the antenna is complete: a
  /// personal card's six digits, or an organization card's PIN 1 of four
  /// to twelve.
  internal var isSetupEntryComplete: Bool {
    switch antennaCardKind {
    case .personal:
      isCardAccessNumberEntryComplete

    case .organization:
      (Pin1.minimumDigitCount...Pin1.maximumDigitCount).contains(organizationPinEntry.count)
    }
  }

  /// Whether the setup entry for the card on the antenna is empty, so a
  /// hold only learns which card is there.
  internal var isSetupEntryEmpty: Bool {
    switch antennaCardKind {
    case .personal:
      cardAccessNumberEntry.isEmpty

    case .organization:
      organizationPinEntry.isEmpty
    }
  }

  /// Disclosure follows a validated connection, never digit count alone.
  internal var hasConfiguredCard: Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasValidatedConnection
      }
    #endif
    return model.contents.hasCardAccessNumber
  }

  /// Whether this launch routes every card and device effect to a virtual card.
  ///
  /// Every branch below that reads it stays inside the process-scoped virtual
  /// environment and does not touch physical I/O, Keychain, or token state.
  internal var isDemonstration: Bool {
    #if os(iOS)
      return demoMode.isActive
    #else
      return false
    #endif
  }

  /// The holder of the complete identity to show instead of a setup form.
  ///
  /// A demonstration answers from ``DemoMode``, which holds its identity
  /// for the process and writes nothing; everything else answers from
  /// what the device actually registered. A registration that cannot name
  /// its holder is incomplete and must never render as a finished identity.
  internal var identityHolder: String? {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasIdentity ? demoMode.holderName : nil
      }
    #endif
    guard isRegistered else { return nil }
    #if REFINEID_LOCAL_CARD && os(iOS)
      return PhoneCardPrime.holderName
    #else
      return PrimeStore.primedHolderNames().first
    #endif
  }

  /// Whether there is a complete, displayable identity.
  internal var hasIdentity: Bool {
    identityHolder != nil
  }

  /// Whether a card is being held against the phone right now.
  ///
  /// Read from the model the parent owns, so it cannot be stranded by
  /// the very views a hold hides.
  internal var isHolding: Bool {
    #if REFINEID_LOCAL_CARD && os(iOS)
      return model.isConnecting || primingModel.isRunning || demoMode.isHolding
    #else
      return false
    #endif
  }

  /// Whether this device has an antenna to set an identity with.
  ///
  /// An iPad has none, and runs the same binary as an iPhone. Offering
  /// it a card setup it can never finish -- two fields to fill and a
  /// button that only ever stays grey -- describes the app as broken
  /// rather than the device as different. A demonstration fakes the
  /// antenna, never the device class.
  internal var offersNearField: Bool {
    #if REFINEID_LOCAL_CARD && os(iOS)
      return primingModel.allowsNearField
        || (isDemonstration && DemoMode.offersNearField)
    #elseif os(iOS)
      // A build without the local card path has no way to reach a card of
      // its own: an iPad has no antenna and no reader to attach one to.
      return false
    #else
      return true
    #endif
  }

  /// Whether a connected reader's card still requires activation.
  private var readerActivationRequired: Bool {
    #if os(iOS)
      return readerModel?.hasActivationRequiredCard ?? false
    #else
      return false
    #endif
  }

  /// Whether an activated reader-backed identity is live.
  internal var hasReaderIdentity: Bool {
    #if os(iOS)
      return (readerModel?.isActive ?? false) && !readerActivationRequired
    #else
      return false
    #endif
  }

  /// The access number must be proved before minting starts.
  internal var canPrepareIdentity: Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasValidatedConnection
      }
    #endif
    return model.contents.hasCardAccessNumber
  }

  #if os(iOS)
    /// Whether a qualified signature can start right now.
    internal var signingAvailable: Bool {
      hasIdentity || hasReaderIdentity || hasRemoteSigningIdentity
    }

    /// Whether a paired phone has already named a person to sign as.
    private var hasRemoteSigningIdentity: Bool {
      remoteModel.holder != nil
        && PersistentTokenRegistry.shared.holderLine != nil
    }

    /// Whether the credential management route can be taken right now.
    internal var managementAvailable: Bool {
      (isCardAccessNumberEntryComplete || hasReaderIdentity)
        && !model.isConnecting
    }

    /// Whether Read Identity Card can start the NFC hold that primes the card.
    ///
    /// An empty entry reads too: that hold sends nothing and only learns
    /// which card is on the antenna, so the screen can show its entry.
    internal var canReadIdentityCard: Bool {
      guard
        isSetupEntryComplete || isSetupEntryEmpty,
        !model.isConnecting
      else { return false }
      #if REFINEID_LOCAL_CARD
        if primingModel.isRunning { return false }
      #endif
      return true
    }

    /// Whether the remote card route can be taken right now.
    internal var remoteCardAvailable: Bool {
      if !offersNearField { return true }
      return hasIdentity || hasReaderIdentity
    }

    /// Changes whenever the identities rendered by the reader rows change.
    internal var readerHolderReadKey: [String] {
      readerModel?.holderReadKey ?? []
    }
  #endif

  /// SwiftUI navigation is a projection of the formal flow state.
  internal var flowDestination: Binding<CardSetupStateMachine.Destination?> {
    Binding(
      get: { flowState.destination },
      set: { destination in
        guard destination == nil, flowState.destination != nil else { return }
        transition(.destinationDismissed)
      }
    )
  }

  // MARK: Content Properties

  internal var body: some View {
    #if os(iOS)
      if readerActivationRequired {
        CardManagementView(
          readerCardIsPresent: true,
          activationRequired: true,
          cardAccessNumber: nil
        )
      } else {
        credentialsForm
      }
    #else
      credentialsForm
    #endif
  }

  // MARK: Lifecycle

  #if os(iOS)
    internal init(
      readerModel: ReaderIdentityModeModel?,
      remoteModel: RemoteCardModel
    ) {
      self.readerModel = readerModel
      self.remoteModel = remoteModel
    }
  #endif
}
