#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Automates testing of CryptoTokenKit client-certificate authentication against
// Finnish identification and test sites (card.refineid.fi, suomi.fi, etc.).
//
// Usage:
//   Scripts/test-card-logins.swift [--site <card|suomi|all|url>] [--verbose]

import Foundation
import Security

struct TestTarget {
  let name: String
  let url: URL
}

final class ClientCertificateDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
  let identity: SecIdentity
  let certificate: SecCertificate
  let verbose: Bool
  var challengeReceived = false

  init(identity: SecIdentity, certificate: SecCertificate, verbose: Bool = false) {
    self.identity = identity
    self.certificate = certificate
    self.verbose = verbose
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let method = challenge.protectionSpace.authenticationMethod
    let host = challenge.protectionSpace.host
    let port = challenge.protectionSpace.port
    if method == NSURLAuthenticationMethodClientCertificate {
      challengeReceived = true
      print("  [mTLS] Server '\(host):\(port)' requested client certificate")
      var certs: [SecCertificate] = [certificate]
      var trust: SecTrust?
      let policy = SecPolicyCreateBasicX509()
      if SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess, let trust = trust {
        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
          certs = chain
        }
      }
      let credential = URLCredential(
        identity: identity,
        certificates: certs,
        persistence: .forSession
      )
      completionHandler(.useCredential, credential)
      return
    }
    completionHandler(.performDefaultHandling, nil)
  }
}

func findCardIdentity() -> (SecIdentity, SecCertificate, String)? {
  let query: [String: Any] = [
    kSecClass as String: kSecClassIdentity,
    kSecReturnRef as String: true,
    kSecMatchLimit as String: kSecMatchLimitAll,
  ]

  var result: CFTypeRef?
  let status = SecItemCopyMatching(query as CFDictionary, &result)
  guard status == errSecSuccess, let list = result as? [SecIdentity] else {
    return nil
  }

  for id in list {
    var cert: SecCertificate?
    SecIdentityCopyCertificate(id, &cert)
    guard let cert else { continue }
    let subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
    if !subject.contains("Developer")
      && !subject.contains("Distribution")
      && !subject.contains("Apple")
      && !subject.contains("localhost")
      && !subject.contains("127.0.0.1")
      && !subject.isEmpty
    {
      return (id, cert, subject)
    }
  }

  return nil
}

func runTest(target: TestTarget, identity: SecIdentity, certificate: SecCertificate, verbose: Bool) async -> Bool {
  print("\n------------------------------------------------------------")
  print("Testing: \(target.name) (\(target.url))")
  print("------------------------------------------------------------")

  let delegate = ClientCertificateDelegate(identity: identity, certificate: certificate, verbose: verbose)
  let config = URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest = 30
  config.timeoutIntervalForResource = 60
  config.httpShouldSetCookies = true
  let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

  var request = URLRequest(url: target.url)
  request.httpMethod = "GET"
  request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

  let startTime = Date()
  do {
    let (data, response) = try await session.data(for: request)
    let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
    if let httpResponse = response as? HTTPURLResponse {
      print("  Status Code: \(httpResponse.statusCode)")
      print("  Challenge Handshake: \(delegate.challengeReceived ? "YES (mTLS executed)" : "No challenge requested")")
      print("  Response Size: \(data.count) bytes")
      print("  Elapsed Time: \(elapsed)s")
      if verbose {
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
        print("  Body Preview: \(preview.replacingOccurrences(of: "\n", with: " "))")
      }
      let success = (200...399).contains(httpResponse.statusCode)
      print("  Result: \(success ? "SUCCESS" : "UNEXPECTED STATUS")")
      return success
    }
    return false
  } catch {
    let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
    print("  Failed after \(elapsed)s: \(error.localizedDescription)")
    print("  Challenge Handshake: \(delegate.challengeReceived ? "YES (failed during sign)" : "No challenge requested")")
    print("  Result: FAILED")
    return false
  }
}

func main() async {
  print("============================================================")
  print("RefineID Automated CryptoTokenKit Login Test Tool")
  print("============================================================")

  guard let (identity, cert, subject) = findCardIdentity() else {
    print("Error: No CryptoTokenKit card identity found in system Keychain.")
    print("Ensure the card is paired/primed and published to CryptoTokenKit.")
    exit(1)
  }

  print("Found Card Identity: \(subject)")

  var targets: [TestTarget] = []
  let args = CommandLine.arguments

  var verbose = false
  if args.contains("--verbose") || args.contains("-v") {
    verbose = true
  }

  if let siteIndex = args.firstIndex(of: "--site"), siteIndex + 1 < args.count {
    let site = args[siteIndex + 1]
    switch site {
    case "card":
      targets.append(TestTarget(name: "RefineID Card Auth", url: URL(string: "https://card.refineid.fi")!))
    case "suomi":
      targets.append(TestTarget(name: "Suomi.fi Identification", url: URL(string: "https://tunnistus.suomi.fi")!))
    case "all":
      targets.append(TestTarget(name: "RefineID Card Auth", url: URL(string: "https://card.refineid.fi")!))
      targets.append(TestTarget(name: "Suomi.fi Identification", url: URL(string: "https://tunnistus.suomi.fi")!))
    default:
      if let customURL = URL(string: site) {
        targets.append(TestTarget(name: "Custom Target", url: customURL))
      }
    }
  } else {
    targets.append(TestTarget(name: "RefineID Card Auth", url: URL(string: "https://card.refineid.fi")!))
    targets.append(TestTarget(name: "Suomi.fi Identification", url: URL(string: "https://tunnistus.suomi.fi")!))
  }

  var passCount = 0
  for target in targets {
    let success = await runTest(target: target, identity: identity, certificate: cert, verbose: verbose)
    if success { passCount += 1 }
  }

  print("\n============================================================")
  print("Summary: \(passCount)/\(targets.count) targets passed.")
  print("============================================================")
}

Task {
  await main()
  exit(0)
}

RunLoop.main.run()
