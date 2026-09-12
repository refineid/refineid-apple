// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Setting the card up: the access number, PIN1, and the hold that
/// registers the card for Safari.
///
/// This is the screen that matters, so it is the one the app opens on.
/// Development builds keep technical state behind the Diagnostics row.
///
/// The two credentials and the action they enable form one operation.
/// Individual replacement controls would imply that they are independent;
/// starting over is instead the explicit forget action below.
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
  @State internal var pin1Entry = ""
  @State internal var isScanning = false
  @State internal var scannerTorchEnabled = false
  @State internal var showsForgetConfirmation = false
  @State internal var registrationReset = false
  @State internal var isRegistered = false
  @State internal var activationScheme: ActivationScheme?
  @State internal var activationNeeds: CardActivationNeeds?
  @State internal var flowState = CardSetupStateMachine.initialState
  @FocusState internal var isCardAccessNumberFieldFocused: Bool
  @FocusState internal var isPin1FieldFocused: Bool

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// The priming model lives here, above everything a hold hides.
    @StateObject internal var primingModel = CardPrimingModel()
    @ObservedObject internal var phoneRelay = PhonePersistentTokenRelay.shared
  #endif

  #if os(iOS)
    /// The holder names read from the live reader tokens.
    @State internal var readerHolders: [String] = []

    /// Whether the document verification screen is pushed.
    @State internal var showsDocumentVerify = false

    /// Pairing model that drives inline pairing on both iPad and iPhone.
    @StateObject internal var pairingModel = RappPairingModel()

    /// Whether the inline 6-digit pairing code field is expanded on iPhone.
    @State internal var isPairingInputActive = false

    /// The 6-digit numeric pairing code typed on iPhone.
    @State internal var pairingCodeDigits = ""

    @FocusState internal var isPairingFieldFocused: Bool
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
  /// become available at six digits without requiring an earlier NFC read.
  internal var managementCardAccessNumber: String? {
    isCardAccessNumberEntryComplete ? cardAccessNumberEntry : nil
  }

  /// The PIN is valid for storage only inside the card's documented range.
  internal var isPin1EntryComplete: Bool {
    pin1Entry.count >= Pin1.minimumDigitCount
      && pin1Entry.count <= Pin1.maximumDigitCount
  }

  /// The point at which operations using the printed card number can be
  /// offered.
  ///
  /// Until all six digits exist, PIN1 has no card to belong to.
  internal var isCardAccessNumberEntryComplete: Bool {
    cardAccessNumberEntry.count == CardAccessNumber.digitCount
  }

  /// CAN receives initial focus as the first input of an unconfigured card.
  internal var shouldFocusCardAccessNumber: Bool {
    !hasIdentity
      && offersNearField
      && !isHolding
      && !isCardAccessNumberEntryComplete
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
    return PrimeStore.primedHolderNames().first
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

  /// Both credentials must be usable before minting starts.
  internal var canPrepareIdentity: Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasValidatedConnection && isPin1EntryComplete
      }
    #endif
    return model.contents.hasCardAccessNumber && isPin1EntryComplete
  }

  #if os(iOS)
    /// Whether a qualified signature can start right now.
    internal var signingAvailable: Bool {
      hasIdentity || hasReaderIdentity || isCardAccessNumberEntryComplete
        || hasRemoteSigningIdentity
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

    /// Whether PIN 1 has been stored on this device.
    internal var isPin1Cached: Bool {
      if isDemonstration {
        return demoMode.hasValidatedConnection
      }
      return model.contents.hasPin1
    }

    /// Whether Cache can start the NFC hold that stores PIN 1.
    internal var canCachePin1: Bool {
      guard
        isCardAccessNumberEntryComplete,
        isPin1EntryComplete,
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
          cardAccessNumber: nil,
          activationScheme: nil,
          activationNeeds: nil,
          onActivationSucceeded: {
            // optional hook; default is a no-op
          }
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
