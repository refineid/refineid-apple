// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Sizes fixed by the 25519, ChaChaPoly and SHA256 Noise suites.
internal enum NoiseSizes {
  internal static let hashLength = 64
  internal static let keyLength = 32
  internal static let nonceZeroPrefixLength = 4
  internal static let publicKeyLength = 32
  internal static let tagLength = 16
  internal static let mlkem768PublicKeyLength = 1_184
  internal static let mlkem768CiphertextLength = 1_088
  internal static let mlkem768SharedSecretLength = 32
}
