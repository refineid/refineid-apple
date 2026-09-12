// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// Direct checks for bounded and safe redirect behavior.
@Suite
internal struct SigningNetworkRedirectTests {
  /// Certificate-material redirects retain legitimate public CDN routing,
  /// but never accept a special address, a non-HTTP(S) scheme, or a third hop.
  @Test
  internal func certificateMaterialRedirectPolicyIsBoundedAndPublic() {
    guard
      let initial = URL(string: "http://8.8.8.8/issuer"),
      let publicCdn = URL(string: "https://1.1.1.1/issuer"),
      let loopback = URL(string: "http://127.0.0.1/issuer"),
      let httpsHostname = URL(string: "https://issuer.example/issuer"),
      let nonHttp = URL(string: "ftp://8.8.8.8/issuer")
    else {
      Issue.record("Test URL did not parse")
      return
    }
    let initialRedirectCases: [(URL, SigningNetwork.RedirectDecision)] = [
      (publicCdn, .follow),
      (loopback, .refuse),
      (httpsHostname, .follow),
      (nonHttp, .refuse),
    ]
    for (target, expected) in initialRedirectCases {
      #expect(
        SigningNetwork.redirectDecision(
          from: initial,
          to: target,
          endpoint: .certificateMaterial,
          carriesCredentials: false,
          redirectsFollowed: 0
        ) == expected
      )
    }
    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: publicCdn,
        endpoint: .certificateMaterial,
        carriesCredentials: false,
        redirectsFollowed: 1
      ) == .follow
    )
    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: publicCdn,
        endpoint: .certificateMaterial,
        carriesCredentials: false,
        redirectsFollowed: 2
      ) == .refuse
    )
  }

  /// A relative redirect from an HTTP-pinned request must retain its logical
  /// Host, while an absolute CDN hostname uses the newly protected Host.
  @Test
  internal func pinnedHttpRedirectsUseTheCorrectHostHeader() {
    guard
      let initialUrl = URL(string: "http://8.8.8.8/issuer"),
      let relativeTarget = URL(string: "http://8.8.8.8/next"),
      let cdnTarget = URL(string: "http://cdn.example/next"),
      let pinnedCdnUrl = URL(string: "http://1.1.1.1/next"),
      let httpsTarget = URL(string: "https://cdn.example/next")
    else {
      Issue.record("Test URL did not parse")
      return
    }
    var initial = URLRequest(url: initialUrl)
    initial.setValue("issuer.example", forHTTPHeaderField: "Host")
    var relative = URLRequest(url: relativeTarget)
    relative.setValue(nil, forHTTPHeaderField: "Host")
    let retained = SigningNetwork.retainingPinnedHostHeader(
      in: relative,
      from: initial,
      originalTarget: relativeTarget
    )
    #expect(retained.value(forHTTPHeaderField: "Host") == "issuer.example")

    var protectedCdn = URLRequest(url: pinnedCdnUrl)
    protectedCdn.setValue("cdn.example", forHTTPHeaderField: "Host")
    let cdn = SigningNetwork.retainingPinnedHostHeader(
      in: protectedCdn,
      from: initial,
      originalTarget: cdnTarget
    )
    #expect(cdn.value(forHTTPHeaderField: "Host") == "cdn.example")

    var https = URLRequest(url: httpsTarget)
    https.setValue("issuer.example", forHTTPHeaderField: "Host")
    let normalizedHttps = SigningNetwork.retainingPinnedHostHeader(
      in: https,
      from: initial,
      originalTarget: httpsTarget
    )
    #expect(normalizedHttps.value(forHTTPHeaderField: "Host") == nil)
  }
}
