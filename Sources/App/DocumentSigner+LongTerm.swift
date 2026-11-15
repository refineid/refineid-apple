// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The stages above PAdES-B-T, and what a build keeps when they fail.
extension DocumentSigner {
  /// The validation material and the archive timestamp over a B-T
  /// document, which make it PAdES-B-LTA.
  internal static func longTerm(
    _ timestamped: TimestampedSignature,
    signerCertificate: Data,
    timestampTokens: [TimestampTokenVerifier.VerifiedToken],
    policy: SignatureLevelPolicy
  ) async throws -> Product {
    let evidence: PdfValidationStore.Material
    Self.report(.validation)
    do {
      evidence = try await ValidationMaterialCollector.collect(
        signerCertificate: signerCertificate,
        timestampTokens: timestampTokens
      )
    } catch {
      throw Failure.validation(error)
    }
    let withEvidence = try PdfValidationStore.appended(
      to: timestamped.bytes, material: evidence
    )
    Self.report(.timestamp)
    let archived: Data
    do {
      archived = try await Self.archiveTimestamped(withEvidence, coveredBy: evidence)
    } catch {
      #if DEBUG
        if policy.keepsBelowLongTerm, Self.missesArchiveTimestamp(error) {
          return Product(
            bytes: withEvidence,
            completion: .belowLongTerm(
              BelowLongTermSignature(
                format: .pades,
                level: .longTerm,
                cause: BelowLongTermSignature.Cause(afterTimestamp: error)
              )
            ),
            signature: timestamped
          )
        }
      #endif
      throw error
    }
    #if DEBUG
      Self.phaseTrace("archived")
    #endif
    return Product(bytes: archived, completion: .archival, signature: timestamped)
  }

  #if DEBUG
    /// Whether a failure above PAdES-B-T leaves the archive timestamp
    /// missing.
    ///
    /// Only a token that was not obtained or did not cover the evidence
    /// qualifies; a broken document is refused in every build.
    private static func missesArchiveTimestamp(_ error: Error) -> Bool {
      guard let failure = error as? Failure else { return false }
      switch failure {
      case .network, .archiveTimestampUncovered:
        return true
      default:
        return false
      }
    }

    /// The PAdES-B-T document, when a stage above it failed.
    internal static func timestampedOnly(
      _ timestamped: TimestampedSignature,
      after error: Error
    ) -> Product {
      Product(
        bytes: timestamped.bytes,
        completion: .belowLongTerm(
          BelowLongTermSignature(
            format: .pades,
            level: .timestamped,
            cause: BelowLongTermSignature.Cause(afterTimestamp: error)
          )
        ),
        signature: timestamped
      )
    }

    /// The card signature alone, PAdES-B-B, when its timestamp failed.
    internal static func basic(_ material: CardMaterial) throws -> Product {
      let cms = try QualifiedDocumentCms.assemble(
        signedAttributesSet: material.signedAttributes,
        signatureValue: material.signature,
        signerProfile: material.profile,
        signerCertificate: material.certificate,
        timestampTokens: []
      )
      return Product(
        basic: try material.placeholder.filled(with: cms),
        clock: Date(),
        shortfall: BelowLongTermSignature(
          format: .pades, level: .basic, cause: .signatureTimestamp
        )
      )
    }
  #endif

  /// The build's refusal of a signer certificate, judged before PIN 2
  /// is presented; nil when signing may go on.
  internal static func signerRefusal(
    _ certificate: Data
  ) -> ValidationMaterialCollector.Failure? {
    SignatureLevelPolicy.forBuild.signerRefusal(
      anchors: ValidationMaterialCollector.signerAnchors(for: certificate)
    )
  }

  /// The archive timestamp over the finished file, accepted only when
  /// the validation material written under it carries its signer's
  /// whole path.
  ///
  /// A validator reads that path from the `/DSS`; a document timestamp
  /// signed under a path the evidence walk never collected would leave
  /// the timestamp itself unverifiable, and nothing can be added under
  /// it after it is taken.
  private static func archiveTimestamped(
    _ document: Data,
    coveredBy evidence: PdfValidationStore.Material
  ) async throws -> Data {
    let prepared: PdfSignaturePlaceholder
    do {
      prepared = try PdfIncrementalSigner.prepare(
        document, revision: .documentTimestamp
      )
    } catch let error as PdfSigningError {
      throw Failure.document(error)
    }
    let token: TimestampTokenVerifier.VerifiedToken
    do {
      token = try await TimestampClient.token(over: prepared.digest(.sha384))
    } catch {
      throw Failure.network(error)
    }
    let chain = Set(token.verifiedCertificateChain)
    guard
      !chain.isEmpty,
      chain.isSubset(of: Set(evidence.certificates))
    else {
      throw Failure.archiveTimestampUncovered
    }
    do {
      return try prepared.filled(with: token.token)
    } catch let error as PdfSigningError {
      throw Failure.document(error)
    }
  }
}
