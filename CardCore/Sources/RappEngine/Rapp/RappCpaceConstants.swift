// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Domain separators, sizes and profile literals for the CPaceRistretto255
/// KC2 profile (draft-irtf-cfrg-cpace-21, RAPP v26.10.21 §6.1).
internal enum RappCpaceConstants {
  internal static let pointSize = 32
  internal static let offerIdSize = 32
  internal static let sha512InputBlockSize = 128
  internal static let dsi = Data("CPaceRistretto255".utf8)
  internal static let iskDsi = Data("CPaceRistretto255_ISK".utf8)

  /// Byte length of a mutual confirmation tag: FIRST32 of HMAC-SHA-512.
  internal static let tagSize = 32
  /// Byte length of each HKDF-Expand output the KC2 key schedule draws.
  internal static let expandedKeySize = 32
  /// Step 1 carries Y_A; step 2 carries Y_B and T_B; step 3 carries T_A.
  internal static let step1Size = pointSize
  internal static let step2Size = pointSize + tagSize
  internal static let step3Size = tagSize
  /// Random bytes reduced modulo the group order to sample one scalar (Option B).
  internal static let wideScalarSize = 64

  /// The suite literal the context, offer echo and pairing prologue bind.
  internal static let kc2Suite =
    "CPACE-RISTR255-SHA512-RAPP-KC2 + Noise_XXpsk3_25519_ChaChaPoly_SHA512"

  internal static let contextDomain = "rapp-pairing-context"
  internal static let initiatorRole = "requester"
  internal static let responderRole = "custodian"

  internal static let transcriptDomain = Data("rapp-cpace-transcript".utf8)
  internal static let pskInfo = Data("rapp-noise-psk".utf8)
  internal static let confirmAKeyInfo = Data("rapp-cpace-confirm-a-key".utf8)
  internal static let confirmBKeyInfo = Data("rapp-cpace-confirm-b-key".utf8)
  internal static let confirmATagDomain = Data("rapp-cpace-confirm-a".utf8)
  internal static let confirmBTagDomain = Data("rapp-cpace-confirm-b".utf8)

  /// RFC 5869 numbers HKDF-Expand blocks from one; one block covers 32 bytes.
  internal static let firstExpandBlock: UInt8 = 1
}
