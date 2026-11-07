// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The signature timestamp and the evidence that make a container
/// XAdES-LT, and what a build keeps when they fail.
extension AsicSigner {
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

    /// The container with `timestampTokens` and `material`, named by
    /// `instant`.
    func container(
      timestampTokens: [Data],
      material: PdfValidationStore.Material,
      at instant: Date
    ) throws -> Product {
      let signatureXml = plan.document(
        xmlSignature: xmlSignature,
        timestampTokens: timestampTokens,
        material: material
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

    #if DEBUG
      /// A development container below XAdES-LT, carrying its level.
      func belowLongTerm(
        timestampTokens: [Data],
        at instant: Date,
        shortfall: BelowLongTermSignature
      ) throws -> Product {
        var product = try container(
          timestampTokens: timestampTokens, material: Self.noMaterial, at: instant
        )
        product.belowLongTerm = shortfall
        return product
      }
    #endif
  }

  /// Timestamps the signature, collects the evidence, and writes the
  /// container.
  internal static func evidenced(
    plan: XadesSignature.Plan,
    xmlSignature: Data,
    certificate: Data,
    objects: [AsicContainer.DataObject]
  ) async throws -> Product {
    let draft = Draft(plan: plan, xmlSignature: xmlSignature, objects: objects)
    let token: TimestampTokenVerifier.VerifiedToken
    DocumentSigner.report(.timestamp)
    do {
      token = try await TimestampClient.token(
        over: XadesSignature.timestampDigest(xmlSignature)
      )
    } catch {
      #if DEBUG
        if SignatureLevelPolicy.forBuild.keepsBelowLongTerm {
          return try draft.belowLongTerm(
            timestampTokens: [],
            at: Date(),
            shortfall: BelowLongTermSignature(
              format: .asice, level: .basic, cause: .signatureTimestamp
            )
          )
        }
      #endif
      throw DocumentSigner.Failure.network(error)
    }
    let evidence: PdfValidationStore.Material
    DocumentSigner.report(.validation)
    do {
      evidence = try await ValidationMaterialCollector.collect(
        signerCertificate: certificate,
        timestampTokens: [token]
      )
    } catch {
      let failure = DocumentSigner.Failure.validation(error)
      #if DEBUG
        if SignatureLevelPolicy.forBuild.keepsBelowLongTerm {
          return try draft.belowLongTerm(
            timestampTokens: [token.token],
            at: token.generatedAt,
            shortfall: BelowLongTermSignature(
              format: .asice,
              level: .timestamped,
              cause: BelowLongTermSignature.Cause(afterTimestamp: failure)
            )
          )
        }
      #endif
      throw failure
    }
    return try draft.container(
      timestampTokens: [token.token], material: evidence, at: token.generatedAt
    )
  }
}
