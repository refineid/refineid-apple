// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Domain separators and framing constants for CPace (draft-irtf-cfrg-cpace-21).
internal enum RappCpaceConstants {
  internal static let pointSize = 32
  internal static let offerIdSize = 32
  internal static let pairingSecretSize = 32
  internal static let sha512InputBlockSize = 128
  internal static let frameDomain = "RAPP-cpace-v1"
  internal static let dsi = Data("CPaceRistretto255".utf8)
  internal static let iskDsi = Data("CPaceRistretto255_ISK".utf8)
}
