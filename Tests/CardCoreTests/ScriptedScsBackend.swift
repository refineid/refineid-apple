// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// A canned SCS signing backend: fixed chain and signature, optional
/// scripted refusal, and a record of what was asked, so protocol
/// tests run without hardware.
internal final class ScriptedScsBackend: ScsSigningBackend {
  internal var chain: [Data]
  internal var algorithm: ScsKeyAlgorithm
  internal var signature: Data
  internal var refusal: ScsBackendFailure?
  internal private(set) var signedData: [Data] = []
  internal private(set) var signedHashes: [SigningHash] = []
  internal private(set) var signedPurposes: [ScsSignPurpose] = []
  internal private(set) var signedOrigins: [String?] = []

  internal init(
    chain: [Data],
    algorithm: ScsKeyAlgorithm,
    signature: Data
  ) {
    self.chain = chain
    self.algorithm = algorithm
    self.signature = signature
  }

  internal func certificateChain(for _: ScsSignPurpose) -> [Data] {
    chain
  }

  internal func keyAlgorithm(for _: ScsSignPurpose) -> ScsKeyAlgorithm {
    algorithm
  }

  internal func sign(_ request: ScsSignRequest) throws -> Data {
    if let refusal {
      throw refusal
    }
    signedData.append(request.data)
    signedHashes.append(request.hash)
    signedPurposes.append(request.purpose)
    signedOrigins.append(request.origin)
    return signature
  }
}
