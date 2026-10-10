// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Fetches a timestamp and the public certificate-status material an
/// archival signature needs.
///
/// What travels is a digest, certificate identifier, or public
/// certificate material - never a key, PIN, or document byte. TLS is
/// supplied by the operating system.
internal enum SigningNetwork {
  /// Why a fetch could not be used.
  internal enum Failure: Error, Equatable {
    /// The address did not parse.
    case badAddress

    /// The service answered with an error status.
    case httpStatus(Int)

    /// Basic credentials would cross an unauthenticated connection.
    case insecureCredentials

    /// One exchange tried to follow too many redirects.
    case redirectLimitExceeded

    /// A certificate-published address does not name the public Internet.
    case unsafeAddress

    /// A redirect changed a protected endpoint or left HTTP(S).
    case unsafeRedirect

    /// The answer was empty or beyond the accepted size.
    case unusableBody
  }

  /// Bytes accepted from a timestamp or revocation service.
  private static let maximumResponseBytes = 65_536

  /// Bytes accepted from a certificate revocation list, which is a
  /// published document rather than a per-request answer.
  private static let maximumListBytes = 1_048_576

  /// Seconds any one exchange may take.
  private static let timeout: TimeInterval = 30

  /// Seconds the DNSSEC-validated attempt may take.
  ///
  /// A validated lookup that is going to work answers as fast as an
  /// unvalidated one - a few tenths of a second against the EU list
  /// of lists - so the unvalidated attempt runs beside it after
  /// ``validatedHeadStart`` rather than after this.
  private static let validatedAttemptTimeout: TimeInterval = 8

  /// HTTP statuses that carry a usable body.
  internal static let successStatuses = 200..<300

  /// HTTP statuses for which repeating an unchanged authority request may
  /// recover without changing credentials, policy, or payload.
  private static let requestTimeoutStatus = 408
  private static let tooEarlyStatus = 425
  private static let tooManyRequestsStatus = 429
  private static let internalServerErrorStatus = 500
  private static let badGatewayStatus = 502
  private static let serviceUnavailableStatus = 503
  private static let gatewayTimeoutStatus = 504
  private static let transientAuthorityStatuses: Set<Int> = [
    Self.requestTimeoutStatus,
    Self.tooEarlyStatus,
    Self.tooManyRequestsStatus,
    Self.internalServerErrorStatus,
    Self.badGatewayStatus,
    Self.serviceUnavailableStatus,
    Self.gatewayTimeoutStatus,
  ]

  /// URL loading failures caused by temporary reachability rather than a
  /// rejected certificate, malformed response, or caller configuration.
  private static let transientAuthorityUrlErrors: Set<Int> = [
    NSURLErrorTimedOut,
    NSURLErrorCannotFindHost,
    NSURLErrorDNSLookupFailed,
    NSURLErrorCannotConnectToHost,
    NSURLErrorNetworkConnectionLost,
    NSURLErrorNotConnectedToInternet,
    NSURLErrorResourceUnavailable,
  ]

  /// An ephemeral session whose DNS answers are validated by the
  /// system when `validating`.
  ///
  /// DNSSEC is asked for first on every exchange, and is worth
  /// asking for - but it is not what makes any of this safe. Every
  /// payload here proves itself: timestamp tokens are verified
  /// against the chain they carry, OCSP responses and CRLs are
  /// signed by the issuer they speak for. A forged DNS answer
  /// cannot produce any of them, so DNS validation is depth, not
  /// the foundation.
  ///
  /// That is why a validation failure is not the end of the
  /// exchange: requiring it has made live, correct services
  /// unreachable while plain HTTPS answered the same URLs in half
  /// a second. A requirement that turns correct infrastructure
  /// into "cannot sign" is not defending anything.
  internal static func validatedSessionConfiguration(
    validating: Bool
  ) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requiresDNSSECValidation = validating
    return configuration
  }

  /// Whether a failure is the kind a DNSSEC-validated lookup
  /// produces when the resolver cannot complete it.
  ///
  /// Anything else - a refusal, a bad status, a body over the limit
  /// - is the service's own answer and is never retried.
  internal static func isResolutionFailure(_ error: Error) -> Bool {
    let codes: Set<Int> = [
      NSURLErrorTimedOut,
      NSURLErrorCannotFindHost,
      NSURLErrorDNSLookupFailed,
      NSURLErrorSecureConnectionFailed,
      NSURLErrorCannotConnectToHost,
    ]
    let failure = error as NSError
    return failure.domain == NSURLErrorDomain && codes.contains(failure.code)
  }

  /// Whether an unchanged timestamp-authority request may succeed later.
  ///
  /// Certificate, TLS, redirect, request, response-shape and credential
  /// failures are deliberately absent: waiting cannot repair them.
  internal static func isTransientAuthorityFailure(_ error: Error) -> Bool {
    if case Failure.httpStatus(let status) = error {
      return Self.transientAuthorityStatuses.contains(status)
    }
    let failure = error as NSError
    return failure.domain == NSURLErrorDomain
      && Self.transientAuthorityUrlErrors.contains(failure.code)
  }

  /// POSTs a DER request and answers the DER response.
  ///
  /// `credentials`, when present, become an HTTP Basic header - the
  /// only shape commercial authorities ask for.
  internal static func post(
    _ body: Data,
    to address: String,
    contentType: String,
    credentials: (username: String, password: String)?,
    endpoint: Endpoint
  ) async throws -> Data {
    let request = try Self.postRequest(
      body,
      to: address,
      contentType: contentType,
      credentials: credentials,
      endpoint: endpoint
    )
    let protected = try Self.protectedRequest(of: request, for: endpoint)
    return try await Self.perform(
      protected,
      limit: Self.maximumResponseBytes,
      endpoint: endpoint,
      carriesCredentials: credentials != nil
    )
  }

  /// Builds one timestamp or OCSP request without sending it.
  ///
  /// Kept as a direct test boundary for the scheme and credential
  /// rules that must hold before URLSession sees the request.
  internal static func postRequest(
    _ body: Data,
    to address: String,
    contentType: String,
    credentials: (username: String, password: String)?,
    endpoint: Endpoint
  ) throws -> URLRequest {
    let url = try Self.httpUrl(address, for: endpoint)
    if credentials != nil, url.scheme?.lowercased() != "https" {
      throw Failure.insecureCredentials
    }
    var request = URLRequest(url: url, timeoutInterval: Self.timeout)
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    if let credentials {
      let pair = "\(credentials.username):\(credentials.password)"
      let encoded = Data(pair.utf8).base64EncodedString()
      request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  /// GETs one public endpoint with a caller-defined body cap.
  ///
  /// Two public redirects are followed for certificate material. This covers
  /// the official Danish TSL's canonical-host hop and media-host hop; longer
  /// chains are refused because an untrusted URL should not be a tour.
  internal static func get(
    _ address: String,
    maximumBytes: Int,
    endpoint: Endpoint
  ) async throws -> Data {
    guard maximumBytes > 0 else { throw Failure.unusableBody }
    let url = try Self.httpUrl(address, for: endpoint)
    let request = URLRequest(url: url, timeoutInterval: Self.timeout)
    let protected = try Self.protectedRequest(
      of: request,
      for: endpoint
    )
    return try await Self.perform(
      protected,
      limit: maximumBytes,
      endpoint: endpoint,
      carriesCredentials: false
    )
  }

  /// GETs certificate or revocation material with its existing size cap.
  internal static func get(
    _ address: String,
    allowingListSize: Bool
  ) async throws -> Data {
    let limit = allowingListSize ? Self.maximumListBytes : Self.maximumResponseBytes
    return try await Self.get(
      address,
      maximumBytes: limit,
      endpoint: .certificateMaterial
    )
  }

  /// Runs one exchange, validated if the resolver can manage it.
  ///
  /// The validated exchange starts first and the unvalidated one
  /// joins it after a short head start, so a resolver that cannot
  /// validate costs that head start rather than the validated
  /// timeout. A host whose validation failed is asked unvalidated
  /// for a while.
  private static func perform(
    _ request: URLRequest,
    limit: Int,
    endpoint: Endpoint,
    carriesCredentials: Bool
  ) async throws -> Data {
    let host = request.url?.host?.lowercased() ?? ""
    let attempt: @Sendable (Bool) async throws -> Data = { validating in
      try await Self.perform(
        request,
        limit: limit,
        endpoint: endpoint,
        carriesCredentials: carriesCredentials,
        validating: validating
      )
    }
    if Self.validationMemory.skipsValidation(for: host, at: .now) {
      return try await attempt(false)
    }
    let answer = try await Self.firstAnswer(
      headStart: Self.validatedHeadStart,
      validated: { try await attempt(true) },
      plain: { try await attempt(false) }
    )
    if answer.outcome == .plain {
      Self.validationMemory.recordFailure(for: host, at: .now)
    }
    return answer.data
  }

  /// One exchange, with the status and size checks.
  private static func perform(
    _ request: URLRequest,
    limit: Int,
    endpoint: Endpoint,
    carriesCredentials: Bool,
    validating: Bool
  ) async throws -> Data {
    let configuration = Self.validatedSessionConfiguration(
      validating: validating
    )
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = ["Accept": "*/*"]
    let allowance = validating ? Self.validatedAttemptTimeout : Self.timeout
    configuration.timeoutIntervalForRequest = allowance
    configuration.timeoutIntervalForResource = allowance
    let collector = BoundedResponseCollector(
      initial: request,
      endpoint: endpoint,
      carriesCredentials: carriesCredentials,
      limit: limit
    )
    let session = URLSession(
      configuration: configuration,
      delegate: collector,
      delegateQueue: nil
    )
    defer { session.finishTasksAndInvalidate() }
    let data = try await collector.response(using: session, request: request)
    guard !data.isEmpty, data.count <= limit else {
      throw Failure.unusableBody
    }
    return data
  }
}
