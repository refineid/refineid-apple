// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
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
    /// The authority answered without granting a timestamp.
    case authorityDeclined

    /// The authority declined or failed.
    case authorityDidNotAnswer(String)

    /// The authority answered with a response that does not match the request.
    case invalidResponse(RfcTimestamp.TokenFailure)

    /// The authority returned a token that failed cryptographic or RFC 3161 verification.
    case invalidToken(TimestampTokenVerifier.Failure)

    /// The device had no usable network connection to ask with.
    case noNetworkConnection

    /// Secure random bytes for the request could not be made.
    case randomUnavailable

    /// The EU trusted lists could not be read to resolve time-stamping trust anchors.
    case trustedListsUnavailable

    /// The authority response did not chain to trusted time-stamping anchors.
    case untrustedAuthority

    /// The settings badge for a verified authority.
    internal static let verifiedBadgeSymbol = "clock.badge.checkmark"

    /// The settings badge for a failure no recorded badge names.
    internal static let unclearBadgeSymbol = "clock.badge.exclamationmark"

    /// The settings badge for a refused or silent authority.
    internal static let unansweredBadgeSymbol = "clock.badge.xmark"

    /// The settings badge without a network connection.
    internal static let offlineBadgeSymbol = "clock.badge.questionmark"

    /// The settings status line for this failure.
    internal var settingsReason: String {
      switch self {
      case .untrustedAuthority:
        String(localized: "Not on the EU trusted lists")
      case .trustedListsUnavailable:
        String(localized: "EU trusted lists unavailable")
      case .invalidResponse, .invalidToken:
        String(localized: "Invalid timestamp response")
      case .noNetworkConnection:
        String(localized: "No network connection")
      case .randomUnavailable:
        String(localized: "Secure random bytes unavailable")
      case .authorityDeclined:
        String(localized: "Timestamp declined")
      case .authorityDidNotAnswer:
        String(localized: "Service unreachable")
      }
    }

    /// The settings badge for this failure.
    ///
    /// A refusal or silence is a cross; a missing connection is a
    /// question; anything subtler is an exclamation.
    internal var badgeSymbol: String {
      switch self {
      case .authorityDeclined, .authorityDidNotAnswer:
        Self.unansweredBadgeSymbol
      case .noNetworkConnection:
        Self.offlineBadgeSymbol
      case .invalidResponse, .invalidToken, .randomUnavailable,
        .trustedListsUnavailable, .untrustedAuthority:
        Self.unclearBadgeSymbol
      }
    }
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
    /// Explicit trust anchor resolver injected for tests.
    @TaskLocal internal static var anchorResolver: (@Sendable (Date) async throws -> [Data])?
  #endif

  /// Resolves the trusted time-stamping anchors for a token acquired at `instant`.
  ///
  /// Absent or stale lists are fetched before the anchors are taken, so
  /// a withdrawn anchor is not used while the lists can be reached; a
  /// failed fetch keeps the cache usable.
  internal static func timeStampingAnchors(at instant: Date) async throws -> [Data] {
    #if DEBUG
      if let resolver = anchorResolver {
        let anchors = try await resolver(instant)
        guard !anchors.isEmpty else { throw Failure.untrustedAuthority }
        return anchors
      }
    #endif
    guard
      case .success(let trustAnchors) = await TrustedListStore.shared
        .signingAnchors()
    else {
      throw Failure.trustedListsUnavailable
    }
    let anchors = trustAnchors.certificates(for: .timeStamping, at: instant)
    guard !anchors.isEmpty else {
      throw Failure.untrustedAuthority
    }
    return anchors
  }

  /// Verifies a raw RFC 3161 token against time-stamping trust anchors resolved at `acquiredAt`.
  internal static func verifyToken(
    _ token: Data,
    acquiredAt: Date
  ) async throws -> TimestampTokenVerifier.VerifiedToken {
    let anchors = try await Self.timeStampingAnchors(at: acquiredAt)
    do {
      return try TimestampTokenVerifier.verify(token, trustedCertificates: anchors)
    } catch TimestampTokenVerifier.Failure.untrustedSigner {
      throw Failure.untrustedAuthority
    } catch let failure as TimestampTokenVerifier.Failure {
      throw Failure.invalidToken(failure)
    }
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
  internal static func compactToken(
    over digest: Data
  ) async throws -> Data {
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

  /// The token a response carries, bound to the request just sent.
  ///
  /// A response that is not a granted token for this request is the
  /// authority's answer, not a transport failure: a non-granted status
  /// is reported as the authority declining, and a response that does
  /// not match the request as an invalid answer.
  private static func checkedToken(
    from response: Data,
    digest: Data,
    nonce: Data
  ) throws -> Data {
    do {
      return try RfcTimestamp.token(
        fromResponse: response, digest: digest, nonceBytes: nonce
      )
    } catch let failure as RfcTimestamp.TokenFailure {
      switch failure {
      case .rejected:
        throw Failure.authorityDeclined
      default:
        throw Failure.invalidResponse(failure)
      }
    }
  }

  /// One token from one authority, checked before it is accepted.
  internal static func token(
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
    let token = try Self.checkedToken(
      from: response, digest: digest, nonce: nonce
    )
    return try await Self.verifyToken(token, acquiredAt: Date())
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
    let token = try Self.checkedToken(
      from: response, digest: digest, nonce: nonce
    )
    let verified = try await Self.verifyToken(token, acquiredAt: Date())
    guard
      let compact = CmsCertificates.removingCertificates(
        from: verified.token
      )
    else {
      throw Failure.invalidResponse(.malformed)
    }
    return compact
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
