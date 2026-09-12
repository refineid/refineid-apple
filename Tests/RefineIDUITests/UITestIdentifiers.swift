// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The accessibility identifiers these tests drive the app by.
///
/// Identifiers rather than labels, and that is not a preference. A label
/// is localized: on a phone set to Finnish every label query in this
/// bundle would miss, and the run would report a broken card path when the
/// only thing wrong was the device language. An identifier is the same
/// string in every language.
///
/// Each constant must match the `.accessibilityIdentifier(...)` of the
/// same spelling in `Sources/App/CardCredentialsView.swift`,
/// `Sources/App/CardRegistrationSections.swift`,
/// `Sources/App/DiagnosticsView.swift`, and the card-management
/// sections under `Sources/App/`.
/// A UI test drives a separate process and cannot share a constant with
/// it, so this is the register that keeps the two sides honest.

internal enum UITestIdentifiers {
  /// The six-digit entry field, present until an identity is set.
  internal static let cardAccessNumberField = "cardAccessNumberField"

  /// The document drop area in the status window.
  internal static let documentDropArea = "documentDropArea"

  /// The standing notice under a demonstration run.
  internal static let demoModeNotice = "demoModeNotice"

  /// The row that opens the diagnostics capture from setup.
  internal static let diagnosticsButton = "diagnosticsButton"

  /// The PIN1 entry field, present until an identity is set.
  internal static let pin1Field = "pin1Field"

  /// The destructive action, present only while card state exists.
  internal static let forgetCardIdentityButton = "forgetCardIdentityButton"

  /// The line saying the identity is set, present once registered.
  internal static let identityStatus = "identityStatus"

  /// The button that starts one priming hold.
  internal static let primeStartButton = "primeStartButton"

  /// The minting action after its last attempt failed.
  internal static let primeFailed = "primeFailed"

  /// The main window's route into credential management.
  internal static let pinManagementButton = "manageCard"

  /// The button that commits an irreversible card operation, inside
  /// the confirmation put to the holder first.
  internal static let managementConfirm = "managementConfirm"

  /// The button that abandons that operation without sending it.
  internal static let managementCancel = "managementCancel"

  /// The management window's task tabs: change or reset, PIN 1 or PIN 2.
  internal static let managementTask = "managementTask"

  /// The management window's toolbar refresh.
  internal static let managementRefresh = "managementRefresh"

  /// The PIN1 change action; fields are Current/New/Repeat suffixed.
  internal static let managementChangePin1 = "managementChangePIN1"

  /// The PIN2 change action; fields are Current/New/Repeat suffixed.
  internal static let managementChangePin2 = "managementChangePIN2"

  /// The PIN 1 reset action; Puk/New/Repeat sit beside it.
  internal static let managementResetPin1 = "managementResetPIN1"

  /// The PIN 2 reset action; Puk/New/Repeat sit beside it.
  internal static let managementResetPin2 = "managementResetPIN2"

  /// The activation action; Entry/Pin1/Pin2 fields sit beside it.
  internal static let managementActivate = "managementActivate"

  /// The floating entry into the editable virtual card.
  internal static let virtualCardOverlay = "virtualCardOverlay"

  /// The virtual card editor.
  internal static let virtualCardEditor = "virtualCardEditor"

  /// Applies a virtual card state and fault plan.
  internal static let virtualCardApply = "virtualCardApply"

  /// The preset and deterministic-fault menus in the virtual-card editor.
  internal static let virtualCardScenario = "virtualCardScenario"
  internal static let virtualCardFault = "virtualCardFault"

  /// Editable retry counters in the virtual-card editor.
  internal static let virtualCardPIN1Attempts = "virtualCardPIN1Attempts"
  internal static let virtualCardPIN2Attempts = "virtualCardPIN2Attempts"
  internal static let virtualCardPUKAttempts = "virtualCardPUKAttempts"

  /// The holder published by a reader-backed virtual card.
  internal static let readerCardHolder = "readerCardHolder"

  /// The reader/NFC identity route into qualified document signing.
  internal static let signDocuments = "signDocuments"

  /// The document verification route, which needs no card at all.
  internal static let verifyDocuments = "verifyDocuments"

  /// The requester's action that borrows a card from a paired phone.
  internal static let connectRemoteReader = "connectRemoteReader"

  /// The holder named by a borrowed card, once it has answered.
  internal static let remoteCardHolder = "remoteCardHolder"

  /// Drops that borrowed holder, and the pairing it arrived through.
  internal static let forgetRemoteIdentity = "forgetRemoteIdentity"

  /// The row that opens the card-serving route, absent where no card can
  /// be reached.
  internal static let remoteCard = "remoteCard"

  /// The code a requesting device shows for a phone to scan.
  internal static let pairingCode = "pairingCode"

  /// The step that starts a pairing.
  ///
  /// Offered only where a device can also serve a card; a borrowing device
  /// shows the code instead.
  internal static let pairPhone = "pairPhone"

  /// Leaves the pairing sheet without having paired.
  internal static let closePairing = "closePairing"

  /// Document-signing controls shared by reader and NFC routes.
  internal static let signingPIN2 = "signingPIN2"
  internal static let signingCommit = "signingCommit"
  internal static let signingSuccess = "signingSuccess"
  internal static let signingMessage = "signingMessage"
}
