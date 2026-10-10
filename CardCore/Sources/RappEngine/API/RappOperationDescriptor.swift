// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the holder is being asked to allow.
///
/// The digest is already hashed, so no document or challenge content reaches
/// the engine.
public struct RappOperationDescriptor: Equatable, Sendable {
  /// Which operation is being asked for.
  public var kind: RappOperationKind
  /// The origin or document name to show the holder.
  public var displayContext: String?
  /// The key the operation uses, when it uses one.
  public var keyProfile: RappCardKeyProfile?
  /// The signature algorithm, when the operation signs.
  public var algorithm: RappSignatureAlgorithm?
  /// The already-hashed value to be signed.
  public var digest: Data
  /// A batch's document names, in signing order; empty otherwise.
  public var documentNames: [String]
  /// A batch's digests, paired with `documentNames`; empty otherwise.
  public var digests: [Data]

  /// Describes one operation for the holder.
  public init(
    kind: RappOperationKind,
    displayContext: String?,
    keyProfile: RappCardKeyProfile?,
    algorithm: RappSignatureAlgorithm?,
    digest: Data,
    documentNames: [String] = [],
    digests: [Data] = []
  ) {
    self.kind = kind
    self.displayContext = displayContext
    self.keyProfile = keyProfile
    self.algorithm = algorithm
    self.digest = digest
    self.documentNames = documentNames
    self.digests = digests
  }
}
