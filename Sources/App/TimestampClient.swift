// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

/// Asks its time-stamp authority for a timestamp.
///
/// The authority is retried after temporary failures. Every token is
/// cryptographically verified against the request digest and nonce,
/// and against the time-stamping trust anchors from the EU trusted lists.
internal enum TimestampClient {
  /// Why no token could be obtained.
  internal enum Failure: Error, Equatable {
    /// The authority declined or failed.
    case authorityDidNotAnswer(String)

    /// Secure random bytes for the request could not be made.
    case randomUnavailable

    /// The authority response did not chain to trusted time-stamping anchors.
    case untrustedAuthority
  }

  /// The RFC 3161 time-stamp service every signature asks.
  ///
  /// The configured one, or the shipped qualified service. Falling
  /// back from a configured but unusable address is reported, so a
  /// holder who mistyped the authority can see which service
  /// actually answered; the address itself is never logged.
  internal static var authority: String {
    let effective = TimestampAuthorityStore.load(from: .standard)
    #if DEBUG
      if let configured = TimestampAuthorityStore.configured(in: .standard),
        !TimestampAuthorityStore.isUsable(configured)
      {
        DevErrorLog.report(
          "timestamp: the configured authority is not usable; asking the shipped service",
          source: .app)
      }
    #endif
    return effective
  }

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

  #if DEBUG
    /// Explicit trust anchors injected for hermetic tests.
    nonisolated(unsafe) internal static var testTrustAnchors: (@Sendable (Date) -> [Data])?
  #endif

  /// Resolves the trusted time-stamping anchors for a token generated at `instant`.
  internal static func timeStampingAnchors(at instant: Date) async throws -> [Data] {
    #if DEBUG
      if let testAnchors = testTrustAnchors {
        let anchors = testAnchors(instant)
        guard !anchors.isEmpty else { throw Failure.untrustedAuthority }
        return anchors
      }
    #endif
    guard
      case .success(let trustAnchors) = await TrustedListStore.shared
        .verificationAnchors()
    else {
      throw Failure.authorityDidNotAnswer("trusted lists unavailable")
    }
    let anchors = trustAnchors.certificates(for: .timeStamping, at: instant)
    guard !anchors.isEmpty else {
      throw Failure.untrustedAuthority
    }
    return anchors
  }

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
    } catch let failure as Failure {
      throw failure
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
    } catch let failure as Failure {
      throw failure
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
  internal static func verifiedCompactEncoding(
    _ token: Data,
    trustedCertificates: [Data]
  ) throws -> Data {
    let verified = try TimestampTokenVerifier.verify(
      token, trustedCertificates: trustedCertificates
    )
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
    let generationTime = try RfcTimestamp.generationTime(in: token)
    let anchors = try await Self.timeStampingAnchors(at: generationTime)
    do {
      return try TimestampTokenVerifier.verify(token, trustedCertificates: anchors)
    } catch {
      throw Failure.untrustedAuthority
    }
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
    let generationTime = try RfcTimestamp.generationTime(in: token)
    let anchors = try await Self.timeStampingAnchors(at: generationTime)
    do {
      return try Self.verifiedCompactEncoding(token, trustedCertificates: anchors)
    } catch {
      throw Failure.untrustedAuthority
    }
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
