// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CardOperations {
  /// Opens a CAN-authenticated PACE channel and selects the card's eID
  /// application inside secure messaging.
  ///
  /// - FINEID and EstEID 2025: runs PACE at the master file, then selects the
  ///   PKCS#15 eID application (`A000000063504B43532D3135`) inside SM.
  /// - EstEID 2018 / 2018 v2 (IDEMIA IAS-ECC): selects the IAS-ECC root AID
  ///   first so PACE runs in the PKI application rather than the default eMRTD
  ///   applet (ID1 Developer Guide 2025 sections 10.1 and 10.3), then stays in
  ///   that root inside SM with `.estonian2018` memoized.
  ///
  /// When `prefersEstonian2018` is false (the default for FINEID and EstEID
  /// 2025), zero extra APDUs are sent on the FINEID / EstEID 2025 path. If
  /// selecting the eID application inside SM fails because PACE ran against an
  /// EstEID 2018 eMRTD applet, falls back once to selecting the IAS-ECC root
  /// and running PACE there.
  @preconcurrency
  public static func openCanSecureChannel(
    over channel: any CardChannel,
    accessNumber: CardAccessNumber,
    prefersEstonian2018: Bool,
    diagnostic: (@Sendable (String) -> Void)?
  ) throws -> (keys: PaceSessionKeys, operations: CardOperations) {
    if prefersEstonian2018 {
      return try openEstonian2018CanSecureChannel(
        over: channel,
        accessNumber: accessNumber,
        diagnostic: diagnostic
      )
    }
    let keys = try PaceEstablishment(
      channel: channel,
      diagnostic: diagnostic
    ).establish(with: PacePassword(cardAccessNumber: accessNumber)).keys
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    let secureOperations = CardOperations(channel: secure)
    do {
      try secureOperations.selectCardApplication()
      return (keys, secureOperations)
    } catch CardOperationError.selectRejected(.securityNotSatisfied),
      CardOperationError.selectRejected(.smDataObjectsIncorrect),
      CardOperationError.selectRejected(.fileNotFound)
    {
      let plain = CardOperations(channel: channel)
      guard (try? plain.selectEstonian2018Application()) != nil else {
        throw CardOperationError.selectRejected(.fileNotFound)
      }
      return try openEstonian2018CanSecureChannel(
        over: channel,
        accessNumber: accessNumber,
        alreadySelectedAid: plain.referenceMemo.estonian2018Aid,
        diagnostic: diagnostic
      )
    }
  }

  /// Opens a CAN-authenticated PACE channel inside an EstEID 2018 IAS-ECC root.
  private static func openEstonian2018CanSecureChannel(
    over channel: any CardChannel,
    accessNumber: CardAccessNumber,
    alreadySelectedAid: ApplicationIdentifier? = nil,
    diagnostic: (@Sendable (String) -> Void)?
  ) throws -> (keys: PaceSessionKeys, operations: CardOperations) {
    let selectedAid: ApplicationIdentifier?
    if let alreadySelectedAid {
      selectedAid = alreadySelectedAid
    } else {
      let plain = CardOperations(channel: channel)
      try plain.selectEstonian2018Application()
      selectedAid = plain.referenceMemo.estonian2018Aid
    }
    let keys = try PaceEstablishment(
      channel: channel,
      diagnostic: diagnostic
    ).establish(with: PacePassword(cardAccessNumber: accessNumber)).keys
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    let secureOperations = CardOperations(channel: secure)
    secureOperations.referenceMemo.resolved = .estonian2018
    secureOperations.referenceMemo.estonian2018Aid = selectedAid
    return (keys, secureOperations)
  }
}
