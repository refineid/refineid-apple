// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One step an operation on the phone's NFC sheet goes through.
///
/// The order a meter draws them in is the operation's
/// (``NearFieldOperation/steps``), not the order of these cases.
internal enum NearFieldStep: Sendable, Hashable {
  /// A certificate was read off the card.
  case certificate

  /// The card accepted a PIN, a PUK or an activation code.
  case credential

  /// The card is in the field.
  case found

  /// The card was registered so Safari can ask for it.
  case registered

  /// PACE ran and the secure channel is open.
  case secureChannel

  /// The card signed.
  case signature

  /// The card details were written to this iPhone.
  case stored

  /// How one step is going.
  internal enum State: Sendable, Equatable {
    /// Finished.
    case done

    /// Broke here.
    case failed

    /// Running now.
    case running

    /// Not reached yet.
    case waiting
  }
}
