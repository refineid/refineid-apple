// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// A system-visible state event, not an identity.
///
/// The extension has already read the card and proved that a PIN on
/// it awaits activation. Returning an empty
/// token lets CryptoTokenKit serialize that answer with its own card
/// session and lets the app observe it without racing the extension.
internal final class ActivationRequiredToken: TKSmartCardToken, TKTokenDelegate {
  internal init(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) {
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: ActivationTokenIdentity.instanceID(forSlotNamed: smartCard.slot.name),
      tokenDriver: tokenDriver
    )
    delegate = self
    configuration.keychainItems = []
  }

  /// CryptoTokenKit asks every token for sessions while discovering its
  /// metadata, even when it has no keychain items.
  ///
  /// A benign empty session answers that query without pretending the
  /// card vanished. The @objc delegate requirement fixes the throwing
  /// signature even though this implementation cannot fail.
  internal func createSession(
    _: TKToken
  ) throws -> TKTokenSession {  // swiftlint:disable:this unneeded_throws_rethrows
    TKSmartCardTokenSession(token: self)
  }
}
