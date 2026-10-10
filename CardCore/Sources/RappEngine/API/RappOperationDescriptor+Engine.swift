// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Translations between the public vocabulary and the engine's own.
///
/// The public names are the ones callers already wrote against, so they are
/// kept even where the engine spells a value differently.
extension RappOperationDescriptor {
  /// Describes one operation for the holder, carrying only its digest.
  internal init(_ operation: CardOperation) {
    switch operation {
    case .inspectCard, .readIdentity, .readCertificate:
      self.init(
        kind: RappOperationKind(operation), displayContext: nil, keyProfile: nil,
        algorithm: nil, digest: Data())

    case .browserAuthenticate(let origin, let profile, let algorithm, let digest):
      self.init(
        kind: .browserAuthenticate, displayContext: origin,
        keyProfile: RappCardKeyProfile(profile),
        algorithm: RappSignatureAlgorithm(algorithm), digest: digest)

    case .signDocument(let name, let profile, let algorithm, let digest):
      self.init(
        kind: .signDocument, displayContext: name, keyProfile: RappCardKeyProfile(profile),
        algorithm: RappSignatureAlgorithm(algorithm), digest: digest)

    case .batchSignDocuments(let names, let profile, let algorithm, let digests):
      self.init(
        kind: .batchSignDocuments, displayContext: nil,
        keyProfile: RappCardKeyProfile(profile), algorithm: RappSignatureAlgorithm(algorithm),
        digest: Data(), documentNames: names, digests: digests)
    }
  }
}
