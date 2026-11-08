// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit

/// What the running device can actually do, independent of what the
/// holder has chosen.
///
/// This is the ceiling every stored preference is clamped to, and it is
/// a fact about the hardware rather than a setting. Three things have to
/// agree before a near-field transport is offered: the platform has the
/// API at all (macOS does not -- `createNFCSlot` is
/// `API_UNAVAILABLE(macos)`), the OS is new enough (the NFC smart-card
/// slot arrived in version 26), and the device in hand has an antenna.
///
/// The last of those is why this is not a compile-time answer. iPadOS
/// imports CoreNFC and reports version 26 exactly like an iPhone, and no
/// iPad has NFC hardware: taking the build-time answer offered an iPad
/// holder a card setup that could never complete, with a button that
/// could only ever be disabled. `isNFCSupported` is the device asking
/// itself, and it is the only one of the three that can change between
/// two devices running the same binary.
public enum SupportedCardTransports {
  /// The transports this device can offer.
  public static var current: CardTransportSelection {
    #if canImport(CoreNFC)
      if Self.deviceHasNearFieldSlot {
        return .all
      }
      return .readerOnly
    #else
      return .readerOnly
    #endif
  }

  #if canImport(CoreNFC)
    /// Whether this particular device has a contactless slot to open.
    private static var deviceHasNearFieldSlot: Bool {
      TKSmartCardSlotManager.default?.isNFCSupported() ?? false
    }
  #endif

  /// Whether the holder can be offered a near-field choice at all.
  ///
  /// When false the settings UI hides the near-field control rather than
  /// showing a disabled one: a Mac has no antenna to switch on.
  public static var offersNearField: Bool {
    current.permits(.nearField)
  }

  /// Whether this device serves its card to computers over RAPP: only a phone with NFC is a
  /// custodian.
  ///
  /// An iPad, like a computer, is a requester only and never serves a card (RAPP v26.11.8 §1).
  public static var servesRemoteCards: Bool {
    offersNearField && !DeviceModel.machineIdentifier.hasPrefix(tabletFamily)
  }

  /// The machine identifier prefix of every iPad.
  private static let tabletFamily = "iPad"
}
