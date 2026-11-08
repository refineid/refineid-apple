// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The signature timestamp, the evidence and the archive timestamp
/// that make a container XAdES-B-LTA, and what a build keeps when they
/// fail.
extension AsicSigner {
  /// Where the timestamps and the validation material come from.
  internal struct EvidenceSources: Sendable {
    /// The qualified authority and the live evidence collector.
    internal static let live = Self(
      timestamp: { digest in try await TimestampClient.token(over: digest) },
      collect: { certificate, tokens in
        try await ValidationMaterialCollector.collect(
          signerCertificate: certificate, timestampTokens: tokens
        )
      }
    )

    /// One verified RFC 3161 token over a SHA-384 digest.
    internal let timestamp: @Sendable (Data) async throws -> TimestampTokenVerifier.VerifiedToken

    /// The validation material for the signer and the verified tokens.
    internal let collect:
      @Sendable (Data, [TimestampTokenVerifier.VerifiedToken]) async throws ->
        PdfValidationStore.Material
  }

  /// How a build completes a container: from which sources, and what
  /// it keeps when a stage fails.
  internal struct Completion: Sendable {
    /// The live sources under the build's own policy.
    internal static let forBuild = Self(sources: .live, policy: .forBuild)

    /// Where the timestamps and the evidence come from.
    internal let sources: EvidenceSources

    /// What a failed stage leaves.
    internal let policy: SignatureLevelPolicy
  }

  /// Where one stage left the signing: its result, or a development
  /// container kept at the level reached before it.
  private enum Stage<Value> {
    case reached(Value)
    case kept(Product)
  }

  /// A verified card signature waiting for its unsigned properties.
  private struct Draft {
    #if DEBUG
      /// The evidence of a development container that stopped before it.
      private static let noMaterial = PdfValidationStore.Material(
        certificates: [], ocspResponses: [], revocationLists: []
      )
    #endif

    let plan: XadesSignature.Plan
    let xmlSignature: Data
    let objects: [AsicContainer.DataObject]
    let sources: EvidenceSources
    let policy: SignatureLevelPolicy

    /// The container with its unsigned properties, named by `instant`.
    func container(
      timestampTokens: [Data],
      material: PdfValidationStore.Material,
      archiveTimestampToken: Data?,
      at instant: Date
    ) throws -> Product {
      let signatureXml = plan.document(
        xmlSignature: xmlSignature,
        timestampTokens: timestampTokens,
        material: material,
        archiveTimestampToken: archiveTimestampToken
      )
      guard
        let archive = AsicContainer.container(
          objects: objects, signatureXml: signatureXml
        )
      else {
        throw Failure.container
      }
      return Product(bytes: archive, signatureTimestampTime: instant)
    }

    /// The signature timestamp; without it, B-B in a development build.
    func signatureTimestamp() async throws -> Stage<TimestampTokenVerifier.VerifiedToken> {
      do {
        return .reached(try await sources.timestamp(XadesSignature.timestampDigest(xmlSignature)))
      } catch {
        #if DEBUG
          if policy.keepsBelowLongTerm {
            return .kept(
              try kept(
                timestampTokens: [],
                material: Self.noMaterial,
                at: Date(),
                shortfall: BelowLongTermSignature(
                  format: .asice, level: .basic, cause: .signatureTimestamp
                )
              )
            )
          }
        #endif
        throw DocumentSigner.Failure.network(error)
      }
    }

    /// The validation material; without it, B-T in a development build.
    func evidence(
      signerCertificate: Data,
      signatureTimestamp token: TimestampTokenVerifier.VerifiedToken
    ) async throws -> Stage<PdfValidationStore.Material> {
      do {
        return .reached(try await sources.collect(signerCertificate, [token]))
      } catch {
        let failure = DocumentSigner.Failure.validation(error)
        #if DEBUG
          if policy.keepsBelowLongTerm {
            return .kept(
              try kept(
                timestampTokens: [token.token],
                material: Self.noMaterial,
                at: token.generatedAt,
                shortfall: BelowLongTermSignature(
                  format: .asice,
                  level: .timestamped,
                  cause: BelowLongTermSignature.Cause(afterTimestamp: failure)
                )
              )
            )
          }
        #endif
        throw failure
      }
    }

    /// The archive timestamp; without it, B-LT in a development build.
    func archiveTimestamp(
      signatureTimestamp token: TimestampTokenVerifier.VerifiedToken,
      evidence: PdfValidationStore.Material
    ) async throws -> Stage<Data> {
      do {
        return .reached(
          try await coveredArchiveTimestamp(signatureToken: token.token, evidence: evidence))
      } catch {
        #if DEBUG
          if policy.keepsBelowLongTerm {
            return .kept(
              try kept(
                timestampTokens: [token.token],
                material: evidence,
                at: token.generatedAt,
                shortfall: BelowLongTermSignature(
                  format: .asice, level: .longTerm, cause: .archiveTimestamp
                )
              )
            )
          }
        #endif
        throw error
      }
    }

    /// The archive timestamp over the B-LT signature, accepted only
    /// when the container already carries its signer's whole path.
    ///
    /// A validator reads the authority's certificates from
    /// `CertificateValues`; a token signed under a path the evidence
    /// walk never collected would leave the archive timestamp itself
    /// unverifiable.
    private func coveredArchiveTimestamp(
      signatureToken: Data,
      evidence: PdfValidationStore.Material
    ) async throws -> Data {
      let digest = plan.archiveTimestampDigest(
        xmlSignature: xmlSignature,
        timestampTokens: [signatureToken],
        material: evidence
      )
      let archive: TimestampTokenVerifier.VerifiedToken
      do {
        archive = try await sources.timestamp(digest)
      } catch {
        throw DocumentSigner.Failure.network(error)
      }
      guard Set(archive.verifiedCertificateChain).isSubset(of: Set(evidence.certificates))
      else {
        throw Failure.archiveTimestampUncovered
      }
      return archive.token
    }

    #if DEBUG
      /// A development container below XAdES-B-LTA, carrying its level.
      private func kept(
        timestampTokens: [Data],
        material: PdfValidationStore.Material,
        at instant: Date,
        shortfall: BelowLongTermSignature
      ) throws -> Product {
        var product = try container(
          timestampTokens: timestampTokens,
          material: material,
          archiveTimestampToken: nil,
          at: instant
        )
        product.belowLongTerm = shortfall
        return product
      }
    #endif
  }

  /// Timestamps the signature, collects the evidence, takes the
  /// archive timestamp over all of it, and writes the container.
  ///
  /// `completion.policy` decides what a failed stage leaves: under
  /// `longTermOnly` it throws and nothing is written.
  internal static func evidenced(
    plan: XadesSignature.Plan,
    xmlSignature: Data,
    certificate: Data,
    objects: [AsicContainer.DataObject],
    completion: Completion
  ) async throws -> Product {
    let draft = Draft(
      plan: plan,
      xmlSignature: xmlSignature,
      objects: objects,
      sources: completion.sources,
      policy: completion.policy
    )
    DocumentSigner.report(.timestamp)
    let token: TimestampTokenVerifier.VerifiedToken
    switch try await draft.signatureTimestamp() {
    case .kept(let product):
      return product

    case .reached(let reached):
      token = reached
    }
    DocumentSigner.report(.validation)
    let evidence: PdfValidationStore.Material
    switch try await draft.evidence(signerCertificate: certificate, signatureTimestamp: token) {
    case .kept(let product):
      return product

    case .reached(let reached):
      evidence = reached
    }
    DocumentSigner.report(.timestamp)
    switch try await draft.archiveTimestamp(signatureTimestamp: token, evidence: evidence) {
    case .kept(let product):
      return product

    case .reached(let archiveToken):
      return try draft.container(
        timestampTokens: [token.token],
        material: evidence,
        archiveTimestampToken: archiveToken,
        at: token.generatedAt
      )
    }
  }
}
