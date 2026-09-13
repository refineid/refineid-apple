// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

/// Collects and authenticates every certificate and revocation answer
/// needed before the archive timestamp is issued.
///
/// Partial evidence is not an LT signature. Every non-root certificate
/// in the card signer and verified TSA signer paths must have a proven
/// issuer and one current, signed status answer. The card path must cross
/// a shipped FINEID issuing certificate, the TSA path must cross the
/// anchor authenticated during timestamp verification, and only that
/// explicit anchor may terminate the walk. Otherwise
/// collection throws and the document is never labelled or timestamped as
/// LTA.
internal enum ValidationMaterialCollector {
  /// Which authenticated certificate path produced a terminal status.
  internal enum PathRole: Equatable {
    /// The certificate whose private key signed the document.
    case documentSigner

    /// The certificate whose private key signed an RFC 3161 token.
    case timestampAuthority
  }

  /// Why complete validation material could not be collected.
  internal enum Failure: Error, Equatable {
    /// One certificate did not expose the fields chain building needs.
    case certificateMalformed

    /// A certificate path returned to a certificate already visited.
    case chainCycle

    /// A path did not reach its explicit anchor within the bounded walk.
    case chainTooDeep

    /// No embedded or published certificate actually issued the child.
    case issuerUnavailable

    /// Secure random bytes for an OCSP request could not be made.
    case randomUnavailable

    /// No authenticated current status answer was available.
    case revocationUnavailable

    /// An authenticated status answer says a path certificate is revoked.
    case revoked(PathRole)

    /// No policy-approved anchor was supplied for the path.
    case trustAnchorUnavailable
  }

  /// Injected I/O, clock, and random source for direct deterministic tests.
  internal struct Dependencies: Sendable {
    /// The app's actual network, clock, and secure random source.
    internal static let live = Self(
      get: Self.liveGet,
      post: Self.livePost,
      now: Date.init,
      random: Self.secureRandom
    )

    /// GETs one published certificate or revocation object.
    internal let get: @Sendable (String, Bool) async throws -> Data

    /// POSTs one OCSP request.
    internal let post: @Sendable (Data, String, String) async throws -> Data

    /// The time against which newly fetched status is checked.
    internal let now: @Sendable () -> Date

    /// Cryptographically random bytes of the requested count.
    internal let random: @Sendable (Int) throws -> Data

    /// Groups one collector environment.
    internal init(
      get: @escaping @Sendable (String, Bool) async throws -> Data,
      post: @escaping @Sendable (Data, String, String) async throws -> Data,
      now: @escaping @Sendable () -> Date,
      random: @escaping @Sendable (Int) throws -> Data
    ) {
      self.get = get
      self.post = post
      self.now = now
      self.random = random
    }

    /// The live certificate/CRL GET implementation.
    private static func liveGet(
      _ address: String,
      _ allowingListSize: Bool
    ) async throws -> Data {
      try await SigningNetwork.get(
        address, allowingListSize: allowingListSize
      )
    }

    /// The live OCSP POST implementation.
    private static func livePost(
      _ body: Data,
      _ address: String,
      _ contentType: String
    ) async throws -> Data {
      try await SigningNetwork.post(
        body,
        to: address,
        contentType: contentType,
        credentials: nil,
        endpoint: .certificateMaterial
      )
    }

    /// Cryptographically secure bytes from the operating system.
    private static func secureRandom(_ count: Int) throws -> Data {
      var bytes = Data(count: count)
      let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
        guard let base = buffer.baseAddress else { return errSecAllocate }
        return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
      }
      guard status == errSecSuccess else { throw Failure.randomUnavailable }
      return bytes
    }
  }

  /// One leaf and the signed time at which its path must have been valid.
  internal struct ChainStart {
    /// The leaf certificate.
    internal let certificate: Data

    /// The purpose of this certificate path.
    internal let role: PathRole

    /// The certificate-validation time.
    internal let referenceDate: Date

    /// A certificate explicitly approved by the policy that authenticated
    /// this leaf.
    ///
    /// A self-issued name is never an implicit trust decision.
    internal let trustedCertificates: Set<Data>
  }

  /// One authenticated status object selected for a certificate.
  internal enum StatusEvidence {
    /// A BasicOCSPResponse.
    case ocsp(Data)

    /// A canonical DER certificate revocation list.
    case revocationList(Data)
  }

  /// Mutable, ordered, deduplicated output and candidate pool.
  internal struct Collection {
    /// Certificates written to DSS.
    internal var certificates: [Data] = []

    /// Certificates available while constructing paths.
    internal var candidates: [Data] = []

    /// Certificates whose status has already been authenticated.
    internal var checked: Set<Data> = []

    /// Authenticated OCSP answers written to DSS.
    internal var ocspResponses: [Data] = []

    /// Authenticated full CRLs written to DSS.
    internal var revocationLists: [Data] = []

    /// Adds one certificate to the path pool.
    internal mutating func addCandidate(_ certificate: Data) {
      if !candidates.contains(certificate) {
        candidates.append(certificate)
      }
    }

    /// Adds one path certificate to the DSS output and candidate pool.
    internal mutating func addCertificate(_ certificate: Data) {
      addCandidate(certificate)
      if !certificates.contains(certificate) {
        certificates.append(certificate)
      }
    }

    /// Adds one signed OCSP answer once.
    internal mutating func addOcsp(_ response: Data) {
      if !ocspResponses.contains(response) {
        ocspResponses.append(response)
      }
    }

    /// Adds one authenticated full CRL once.
    internal mutating func addRevocationList(_ list: Data) {
      if !revocationLists.contains(list) {
        revocationLists.append(list)
      }
    }
  }

  /// How many certificates one path may contain, including its leaf.
  internal static let maximumDepth = 12

  /// How many distinct locations one certificate extension may make us try.
  ///
  /// Certificate extensions are untrusted input. This leaves room for
  /// redundant public responders without turning one signing operation into
  /// an unbounded series of thirty-second exchanges.
  internal static let maximumCertificateAddresses = 3

  /// Keeps a certificate's advertised locations distinct and bounded.
  internal static func boundedCertificateAddresses(
    _ addresses: [String]
  ) -> [String] {
    var selected: [String] = []
    var seen: Set<String> = []
    for address in addresses where seen.insert(address).inserted {
      selected.append(address)
      if selected.count == Self.maximumCertificateAddresses { break }
    }
    return selected
  }

  /// Collects complete evidence using the live signing environment.
  internal static func collect(
    signerCertificate: Data,
    timestampTokens: [TimestampTokenVerifier.VerifiedToken]
  ) async throws -> PdfValidationStore.Material {
    let issuer = IssuerCertificate.der(matching: signerCertificate)
    let signerTrust = issuer.map { Set([$0]) } ?? []
    return try await Self.collect(
      signerCertificate: signerCertificate,
      timestampTokens: timestampTokens,
      dependencies: .live,
      signerTrustCertificates: signerTrust
    )
  }

  /// Collects complete evidence for the card signer and each verified TSA.
  internal static func collect(
    signerCertificate: Data,
    timestampTokens: [TimestampTokenVerifier.VerifiedToken],
    dependencies: Dependencies,
    signerTrustCertificates: Set<Data>
  ) async throws -> PdfValidationStore.Material {
    let evidenceTime = dependencies.now()
    let starts = Self.orderedChainStarts(
      signerCertificate: signerCertificate,
      timestampTokens: timestampTokens,
      signerTrustCertificates: signerTrustCertificates,
      evidenceTime: evidenceTime
    )
    var collection = Collection()
    collection.addCandidate(signerCertificate)
    if let issuer = IssuerCertificate.der(matching: signerCertificate) {
      collection.addCandidate(issuer)
    }
    for token in timestampTokens {
      for certificate in token.verifiedCertificateChain {
        collection.addCandidate(certificate)
      }
      for certificate in token.embeddedCertificates {
        collection.addCandidate(certificate)
      }
      // The token already carries its signer, but DSS also indexes the
      // complete TSA path explicitly for validators that begin there.
      collection.addCertificate(token.signerCertificate)
    }
    for start in starts {
      do {
        try await Self.walk(
          start,
          evidenceTime: evidenceTime,
          collection: &collection,
          dependencies: dependencies
        )
      } catch is AuthenticatedRevocation {
        throw Failure.revoked(start.role)
      }
    }
    return PdfValidationStore.Material(
      certificates: collection.certificates.filter { certificate in
        certificate != signerCertificate
      },
      ocspResponses: collection.ocspResponses,
      revocationLists: collection.revocationLists
    )
  }

  /// Walks one verified leaf to its explicit policy-approved anchor.
  private static func walk(
    _ start: ChainStart,
    evidenceTime: Date,
    collection: inout Collection,
    dependencies: Dependencies
  ) async throws {
    var current = start.certificate
    var visited: Set<Data> = []
    for _ in 0..<Self.maximumDepth {
      guard visited.insert(current).inserted else {
        throw Failure.chainCycle
      }
      guard let facts = CertificateFacts(der: current) else {
        throw Failure.certificateMalformed
      }
      guard !start.trustedCertificates.isEmpty else {
        throw Failure.trustAnchorUnavailable
      }
      if start.trustedCertificates.contains(current) {
        collection.addCertificate(current)
        await Self.enrichAboveAnchor(
          current,
          at: start.referenceDate,
          evidenceTime: evidenceTime,
          collection: &collection,
          dependencies: dependencies
        )
        return
      }
      let issuer = try await Self.issuer(
        of: current,
        facts: facts,
        at: start.referenceDate,
        collection: &collection,
        dependencies: dependencies
      )
      collection.addCertificate(issuer)
      if collection.checked.insert(current).inserted {
        let evidence = try await Self.status(
          of: current,
          facts: facts,
          under: issuer,
          at: evidenceTime,
          dependencies: dependencies
        )
        switch evidence {
        case .ocsp(let response):
          collection.addOcsp(response)

        case .revocationList(let list):
          collection.addRevocationList(list)
        }
      }
      current = issuer
    }
    throw Failure.chainTooDeep
  }
}
