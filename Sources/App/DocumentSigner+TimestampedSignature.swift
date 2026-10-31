// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The boundary after the card signature and its RFC 3161 timestamp.
extension DocumentSigner {
  /// Why a B-T stage could not be constructed.
  internal enum TimestampedSignatureFailure: Error, Equatable {
    /// B-T requires at least one authenticated signature timestamp.
    case timestampMissing
  }

  /// Values produced by the locally verified card-signature step.
  internal struct TimestampedSignatureInput {
    internal let placeholder: PdfSignaturePlaceholder
    internal let signedAttributes: Data
    internal let signatureValue: Data
    internal let signerProfile: CardKeyProfile
    internal let signerCertificate: Data
  }

  /// A PDF whose card CMS has been validated, timestamped, and filled.
  internal struct TimestampedSignature: Sendable {
    /// The exact PAdES-B-T bytes, before DSS or a document timestamp.
    internal let bytes: Data

    /// The earliest generation time among the signature timestamps.
    internal let signatureTimestampTime: Date

    /// Only the validating assembly boundary may create this stage.
    private init(bytes: Data, signatureTimestampTime: Date) {
      self.bytes = bytes
      self.signatureTimestampTime = signatureTimestampTime
    }

    /// Validates and embeds the card CMS plus its signature timestamps.
    internal static func verified(
      _ input: TimestampedSignatureInput,
      timestampTokens: [TimestampTokenVerifier.VerifiedToken]
    ) throws -> Self {
      guard let earliest = timestampTokens.map(\.generatedAt).min() else {
        throw TimestampedSignatureFailure.timestampMissing
      }
      let cms = try QualifiedDocumentCms.assemble(
        signedAttributesSet: input.signedAttributes,
        signatureValue: input.signatureValue,
        signerProfile: input.signerProfile,
        signerCertificate: input.signerCertificate,
        timestampTokens: timestampTokens.map(\.token)
      )
      return Self(
        bytes: try input.placeholder.filled(with: cms),
        signatureTimestampTime: earliest
      )
    }
  }
}
