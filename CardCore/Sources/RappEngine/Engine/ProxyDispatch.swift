// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The bounded step a custodian adapter performs next.
///
/// Every outcome is data. The engine decides what must happen and the adapter
/// performs it, so nothing here touches a card, a transport, or a screen.
internal enum ProxyDispatch: Equatable {
  /// Take the PIN, prompting the holder when it is not held.
  case awaitConsent(operationIdentifier: RappOperationIdentifier)
  /// Execute the one card command.
  case executeCardCommand(
    operationIdentifier: RappOperationIdentifier, command: AuthorizedCardCommand)
  /// Execute the read; no private key, no PIN.
  case executeSafeRead(operationIdentifier: RappOperationIdentifier, read: AuthorizedSafeRead)
  /// Take the operation's turn on the card in arrival order and perform the
  /// reads that precede the PIN (RAPP v26.10.22 §8.2 item 2).
  case inspectPrerequisites(operationIdentifier: RappOperationIdentifier)
  /// Not an operation message; the operation layer is unaffected.
  case notOperation(TypedMessage)
  /// Send this message on the session.
  case send(TypedMessage)
}
