// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One correlated request or response on the encrypted local relay.
public enum PersistentRelayMessage: Codable, Equatable, Sendable {
  case failure(requestID: UUID, reason: PersistentRelayFailure)
  case identityRequest(requestID: UUID)
  case identityResponse(requestID: UUID, certificateDER: Data)
  case signatureRequest(
    requestID: UUID,
    profile: PersistentRelayCardProfile,
    algorithm: PersistentRelaySigningAlgorithm,
    digest: Data
  )
  case signatureResponse(requestID: UUID, signature: Data)

  /// The correlation UUID shared by a request and its answer.
  public var requestID: UUID {
    switch self {
    case .identityRequest(let requestID), .identityResponse(let requestID, _),
      .signatureRequest(let requestID, _, _, _), .signatureResponse(let requestID, _),
      .failure(let requestID, _):
      requestID
    }
  }

  /// Decodes the application message carried above the opaque transport.
  public static func decoded(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }

  /// Encodes the temporary application message above the opaque transport.
  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }
}
