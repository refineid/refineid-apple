// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension SigningNetwork {
  /// A URL origin, including its effective default port.
  private struct Origin: Equatable {
    let scheme: String
    let host: String
    let port: Int
  }

  /// One redirect gate for one URLSession task.
  internal final class RedirectGate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
  {
    private let initial: URLRequest
    private let endpoint: Endpoint
    private let lock = NSLock()
    private var redirectsFollowed = 0
    private var rejection: Failure?

    /// The reason a redirect was refused, if one was refused.
    internal var redirectFailure: Failure? {
      lock.lock()
      defer { lock.unlock() }
      return rejection
    }

    /// Remembers the invariant that applies to this one exchange.
    internal init(
      initial: URLRequest,
      endpoint: Endpoint
    ) {
      self.initial = initial
      self.endpoint = endpoint
    }

    /// Allows only the policy-approved replacement request.
    internal func urlSession(
      _ _: URLSession,
      task _: URLSessionTask,
      willPerformHTTPRedirection _: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(approvedRedirect(request))
    }

    /// Protects the mutable redirect count from URLSession's delegate queue.
    private func approvedRedirect(_ request: URLRequest) -> URLRequest? {
      lock.lock()
      defer { lock.unlock() }
      guard
        let initialUrl = initial.url,
        let target = request.url
      else {
        return self.reject(.unsafeRedirect)
      }
      if redirectsFollowed
        >= SigningNetwork.maximumRedirects(for: endpoint)
      {
        return self.reject(.redirectLimitExceeded)
      }
      guard
        SigningNetwork.redirectDecision(
          from: initialUrl,
          to: target,
          endpoint: endpoint,
          redirectsFollowed: redirectsFollowed
        ) == .follow
      else {
        return self.reject(.unsafeRedirect)
      }
      let protected: URLRequest
      do {
        protected = try SigningNetwork.protectedRequest(
          of: request,
          for: endpoint
        )
      } catch {
        return self.reject(.unsafeRedirect)
      }
      redirectsFollowed += 1
      var approved = protected
      if endpoint == .certificateMaterial {
        approved = SigningNetwork.retainingPinnedHostHeader(
          in: approved,
          from: initial,
          originalTarget: target
        )
      }
      return approved
    }

    /// Records one redirect-policy rejection.
    private func reject(_ failure: Failure) -> URLRequest? {
      rejection = failure
      return nil
    }
  }

  /// Canonical-host plus media/CDN hops allowed for public material.
  private static let maximumCertificateMaterialRedirects = 2

  /// The time-stamp authority is limited to one tightly constrained hop.
  private static let maximumAuthorityRedirects = 1

  /// The default port for an HTTP URL.
  private static let httpPort = 80

  /// The default port for an HTTPS URL.
  private static let httpsPort = 443

  /// Decides whether one URLSession redirect may be followed.
  ///
  /// This remains a direct test boundary: no request is made and no
  /// hostname is resolved here. The redirect delegate preflights each
  /// certificate-material hostname and IP-pins its HTTP form before follow.
  internal static func redirectDecision(
    from initial: URL,
    to target: URL,
    endpoint: Endpoint,
    redirectsFollowed: Int
  ) -> RedirectDecision {
    guard
      redirectsFollowed < Self.maximumRedirects(for: endpoint),
      Self.isHttpUrl(target)
    else { return .refuse }
    if endpoint == .certificateMaterial {
      guard Self.certificateMaterialUrlIsAllowed(target)
      else { return .refuse }
    }
    guard endpoint == .authority else { return .follow }
    return Self.authorityRedirectIsAllowed(from: initial, to: target)
      ? .follow : .refuse
  }

  /// The endpoint-specific redirect budget.
  private static func maximumRedirects(for endpoint: Endpoint) -> Int {
    endpoint == .certificateMaterial
      ? Self.maximumCertificateMaterialRedirects
      : Self.maximumAuthorityRedirects
  }

  /// The time-stamp authority may change paths on its own origin.
  ///
  /// It may also upgrade its own HTTP name to HTTPS. It may not turn the authority into a
  /// cross-host POST relay or downgrade a protected request.
  private static func authorityRedirectIsAllowed(
    from initial: URL,
    to target: URL
  ) -> Bool {
    if Self.origin(of: initial) == Self.origin(of: target) { return true }
    guard
      initial.scheme?.lowercased() == "http",
      target.scheme?.lowercased() == "https",
      let initialHost = initial.host,
      let targetHost = target.host,
      Self.normalizedHost(initialHost) == Self.normalizedHost(targetHost)
    else { return false }
    return true
  }

  /// Normalizes Host after a redirect from an IP-pinned HTTP request.
  ///
  /// Relative targets retain the initial logical host; a newly pinned HTTP
  /// hostname keeps its derived host; other targets lose any stale value.
  internal static func retainingPinnedHostHeader(
    in request: URLRequest,
    from initial: URLRequest,
    originalTarget: URL
  ) -> URLRequest {
    guard let targetHost = originalTarget.host else { return request }
    if Self.numericAddress(targetHost) != nil {
      guard
        let initialUrl = initial.url,
        Self.origin(of: initialUrl) == Self.origin(of: originalTarget),
        let host = initial.value(forHTTPHeaderField: "Host")
      else {
        var cleared = request
        cleared.setValue(nil, forHTTPHeaderField: "Host")
        return cleared
      }
      var retained = request
      retained.setValue(host, forHTTPHeaderField: "Host")
      return retained
    }
    if originalTarget.scheme?.lowercased() == "http" { return request }
    var cleared = request
    cleared.setValue(nil, forHTTPHeaderField: "Host")
    return cleared
  }

  /// The origin for a URL that has already passed HTTP syntax checks.
  private static func origin(of url: URL) -> Origin? {
    guard
      let scheme = url.scheme?.lowercased(),
      let host = url.host
    else { return nil }
    let port = url.port ?? (scheme == "https" ? Self.httpsPort : Self.httpPort)
    return Origin(scheme: scheme, host: Self.normalizedHost(host), port: port)
  }
}
