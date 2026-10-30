// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

/// Asks the qualified time-stamp authority for a timestamp.
///
/// The authority is retried after temporary failures. It is trusted
/// as named: every token is still cryptographically verified against
/// the request digest and nonce, and against the certificate chain the
/// token itself carries.
internal enum TimestampClient {
  /// Why no token could be obtained.
  internal enum Failure: Error, Equatable {
    /// The authority declined or failed.
    case authorityDidNotAnswer(String)

    /// Secure random bytes for the request could not be made.
    case randomUnavailable
  }

  /// The qualified RFC 3161 time-stamp service every signature asks.
  internal static let authority = "http://timestamp.sectigo.com/qualified"

  /// The content type RFC 3161 defines for a request.
  private static let requestContentType = "application/timestamp-query"

  /// Entropy carried by each request nonce.
  private static let nonceByteCount = 32

  /// First wait after a temporary authority failure.
  private static let initialRetrySeconds = 1

  /// Longest wait between repeated attempts.
  private static let maximumRetrySeconds = 60

  /// Exponent at which the one-second progression reaches its cap.
  private static let maximumRetryExponent = 6

  /// One token over `digest` from the authority.
  internal static func token(
    over digest: Data
  ) async throws -> TimestampTokenVerifier.VerifiedToken {
    do {
      return try await Self.withTransientRetry {
        try await Self.token(over: digest, from: Self.authority)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Failure.authorityDidNotAnswer("\(error)")
    }
  }

  /// A compact token over `digest`, without the authority's
  /// certificate, for somewhere too small to carry one.
  ///
  /// The authority first returns its certificate, so the same
  /// signature, certificate profile and chain as an archival token
  /// are verified. Only then is the unsigned CertificateSet removed.
  internal static func compactToken(over digest: Data) async throws -> Data {
    do {
      return try await Self.withTransientRetry {
        try await Self.compactToken(over: digest, from: Self.authority)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Failure.authorityDidNotAnswer("\(error)")
    }
  }

  /// The compact exchange still asks the authority for its certificate.
  internal static func compactRequest(
    digest: Data,
    nonceBytes: Data
  ) -> Data {
    RfcTimestamp.request(digest: digest, nonceBytes: nonceBytes)
  }

  /// Verifies a full token before removing only its CertificateSet.
  internal static func verifiedCompactEncoding(_ token: Data) throws -> Data {
    let verified = try TimestampTokenVerifier.verify(token)
    guard
      let compact = CmsCertificates.removingCertificates(
        from: verified.token
      )
    else {
      throw RfcTimestamp.TokenFailure.malformed
    }
    return compact
  }

  /// One token from one authority, checked before it is accepted.
  private static func token(
    over digest: Data,
    from authority: String
  ) async throws -> TimestampTokenVerifier.VerifiedToken {
    let nonce = try Self.randomBytes()
    let request = RfcTimestamp.request(digest: digest, nonceBytes: nonce)
    let response = try await SigningNetwork.post(
      request,
      to: authority,
      contentType: Self.requestContentType,
      endpoint: .authority
    )
    let token = try RfcTimestamp.token(
      fromResponse: response, digest: digest, nonceBytes: nonce
    )
    return try TimestampTokenVerifier.verify(token)
  }

  /// One compact token from one authority, verified before stripping.
  private static func compactToken(
    over digest: Data,
    from authority: String
  ) async throws -> Data {
    let nonce = try Self.randomBytes()
    let response = try await SigningNetwork.post(
      Self.compactRequest(digest: digest, nonceBytes: nonce),
      to: authority,
      contentType: Self.requestContentType,
      endpoint: .authority
    )
    let token = try RfcTimestamp.token(
      fromResponse: response, digest: digest, nonceBytes: nonce
    )
    return try Self.verifiedCompactEncoding(token)
  }

  /// Repeats the authority after temporary failures until it answers.
  private static func withTransientRetry<T>(
    operation: () async throws -> T
  ) async throws -> T {
    try await Self.withTransientRetry(operation: operation) { delay in
      try await Task.sleep(for: delay)
    }
  }

  /// The retry loop with an injectable wait for direct tests.
  internal static func withTransientRetry<T>(
    operation: () async throws -> T,
    wait: (Duration) async throws -> Void
  ) async throws -> T {
    var failureCount = 0
    while true {
      do {
        return try await operation()
      } catch {
        guard SigningNetwork.isTransientAuthorityFailure(error) else {
          throw error
        }
        failureCount += 1
        try await wait(Self.retryDelay(after: failureCount))
      }
    }
  }

  /// Capped exponential delay after the given consecutive failure count.
  internal static func retryDelay(after failureCount: Int) -> Duration {
    let exponent = min(
      max(failureCount - 1, 0),
      Self.maximumRetryExponent
    )
    let seconds = min(
      Self.initialRetrySeconds << exponent,
      Self.maximumRetrySeconds
    )
    return .seconds(seconds)
  }

  /// A fresh nonce, failing rather than sending zeros when the
  /// operating system's random source fails.
  private static func randomBytes() throws -> Data {
    var bytes = Data(count: Self.nonceByteCount)
    let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let base = buffer.baseAddress else { return errSecAllocate }
      return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
    }
    guard status == errSecSuccess else { throw Failure.randomUnavailable }
    return bytes
  }
}
