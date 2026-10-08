// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A pairing attempt that failed before any pairing was stored.
internal struct PairingAttemptFailure: Error {
  internal let error: PairingError
  internal let offer: PairingOffer
}
