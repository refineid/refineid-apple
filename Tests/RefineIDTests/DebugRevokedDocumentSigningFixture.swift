// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import Security

  @testable import CardCore
  @testable import RefineID

  /// Builds and inspects the exact post-card PAdES-B-T test stage.
  internal enum DebugRevokedDocumentSigningFixture {
    /// One fully built stage and the values that prove it.
    internal struct Result {
      internal let placeholder: PdfSignaturePlaceholder
      internal let timestamped: DocumentSigner.TimestampedSignature
      internal let cms: Data
      internal let signedAttributes: Data
      internal let cardSignature: Data
      internal let cardCertificate: Data
      internal let timestampToken: Data
      internal let timestampResponse: Data
      internal let timestampNonce: Data
      internal let timestampImprint: Data
      internal let timestampCertificate: Data
    }

    /// Intermediate card-signature values.
    private struct CardStage {
      let placeholder: PdfSignaturePlaceholder
      let signedAttributes: Data
      let signature: Data
      let certificate: Data
    }

    /// Intermediate signature-timestamp values.
    private struct TimestampStage {
      let verified: TimestampTokenVerifier.VerifiedToken
      let response: Data
      let nonce: Data
      let imprint: Data
      let certificate: Data
    }

    /// Failures mean the test fixture itself could not be constructed.
    private enum Failure: Error {
      case certificate
      case signature
    }

    private static let catalogObjectNumber = 1
    private static let pagesObjectNumber = 2
    private static let pageObjectNumber = 3
    private static let crossReferenceEntryCount = 4
    private static let hexadecimalCharactersPerByte = 2
    private static let hexadecimalNibbleBitCount = 4
    private static let hexadecimalAlphabeticOffset: UInt8 = 10

    /// A minimal structurally complete PDF.
    private static var minimalPdf: Data {
      var text = "%PDF-1.7\n"
      var offsets: [Int] = []
      for (number, body) in [
        (
          Self.catalogObjectNumber,
          "<< /Type /Catalog /Pages 2 0 R >>"
        ),
        (
          Self.pagesObjectNumber,
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
        ),
        (
          Self.pageObjectNumber,
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"
        ),
      ] {
        offsets.append(text.utf8.count)
        text += "\(number) 0 obj\n\(body)\nendobj\n"
      }
      let crossReferenceOffset = text.utf8.count
      text += "xref\n0 \(Self.crossReferenceEntryCount)\n"
      text += "0000000000 65535 f \n"
      for offset in offsets {
        text += String(format: "%010d 00000 n \n", offset)
      }
      text += "trailer\n"
      text += "<< /Size \(Self.crossReferenceEntryCount) /Root 1 0 R >>\n"
      text += "startxref\n\(crossReferenceOffset)\n%%EOF\n"
      return Data(text.utf8)
    }

    /// Builds the exact post-card, post-signature-timestamp stage.
    internal static func make() throws -> Result {
      let card = try Self.cardStage()
      let timestamp = try Self.timestampStage(signature: card.signature)
      let timestamped = try DocumentSigner.TimestampedSignature.verified(
        DocumentSigner.TimestampedSignatureInput(
          placeholder: card.placeholder,
          signedAttributes: card.signedAttributes,
          signatureValue: card.signature,
          signerProfile: .rsa2048,
          signerCertificate: card.certificate
        ),
        timestampTokens: [timestamp.verified]
      )
      let cms = try QualifiedDocumentCms.assemble(
        signedAttributesSet: card.signedAttributes,
        signatureValue: card.signature,
        signerProfile: .rsa2048,
        signerCertificate: card.certificate,
        timestampTokens: [timestamp.verified.token]
      )
      return Result(
        placeholder: card.placeholder,
        timestamped: timestamped,
        cms: cms,
        signedAttributes: card.signedAttributes,
        cardSignature: card.signature,
        cardCertificate: card.certificate,
        timestampToken: timestamp.verified.token,
        timestampResponse: timestamp.response,
        timestampNonce: timestamp.nonce,
        timestampImprint: timestamp.imprint,
        timestampCertificate: timestamp.certificate
      )
    }

    /// Verifies the generated card signature independently of CMS assembly.
    internal static func cardSignatureIsValid(_ fixture: Result) throws -> Bool {
      guard
        let certificate = SecCertificateCreateWithData(
          nil,
          fixture.cardCertificate as CFData
        ),
        let publicKey = SecCertificateCopyKey(certificate)
      else {
        throw Failure.certificate
      }
      let digest = Data(SHA384.hash(data: fixture.signedAttributes))
      var error: Unmanaged<CFError>?
      return SecKeyVerifySignature(
        publicKey,
        .rsaSignatureDigestPKCS1v15SHA384,
        digest as CFData,
        fixture.cardSignature as CFData,
        &error
      )
    }

    /// Decodes the fixed-size PDF Contents hole, including zero padding.
    internal static func embeddedContents(in document: Data) -> Data? {
      let marker = Data("/Contents <".utf8)
      guard let found = document.range(of: marker) else { return nil }
      let start = found.upperBound
      guard
        let end = document[start...].firstIndex(of: UInt8(ascii: ">"))
      else {
        return nil
      }
      let digits = Array(document[start..<end])
      guard digits.count.isMultiple(of: Self.hexadecimalCharactersPerByte)
      else {
        return nil
      }
      var decoded = Data()
      decoded.reserveCapacity(
        digits.count / Self.hexadecimalCharactersPerByte
      )
      for offset in stride(
        from: 0,
        to: digits.count,
        by: Self.hexadecimalCharactersPerByte
      ) {
        guard
          let high = Self.hexNibble(digits[offset]),
          let low = Self.hexNibble(digits[offset + 1])
        else {
          return nil
        }
        decoded.append(high << Self.hexadecimalNibbleBitCount | low)
      }
      return decoded
    }

    /// Creates the card-bound PDF attributes and a valid RSA signature.
    private static func cardStage() throws -> CardStage {
      let card = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256
      )
      let placeholder = try PdfIncrementalSigner.prepare(
        Self.minimalPdf,
        revision: .signature(
          PdfIncrementalSigner.SignatureClaim(
            signedAt: Date(timeIntervalSince1970: 0),
            reason: DebugRevokedDocumentSigning.reason,
            location: nil
          )
        )
      )
      let attributes = QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: placeholder.digest,
        signerCertificate: card.certificate
      )
      return CardStage(
        placeholder: placeholder,
        signedAttributes: attributes,
        signature: try Self.cardSignature(attributes: attributes, key: card.key),
        certificate: card.certificate
      )
    }

    /// Generates and production-verifies the signature timestamp.
    private static func timestampStage(signature: Data) throws -> TimestampStage {
      let imprint = try QualifiedDocumentCms.signatureTimestampDigest(
        signatureValue: signature
      )
      let nonce = Data("debug timestamp nonce".utf8)
      let authority = try DebugTimestampAuthority.make()
      let timestamp = try authority.response(imprint: imprint, nonce: nonce)
      let token = try RfcTimestamp.token(
        fromResponse: timestamp.response,
        digest: imprint,
        nonceBytes: nonce
      )
      return TimestampStage(
        verified: try TimestampTokenVerifier.verify(
          token,
          trustedCertificates: [authority.certificate]
        ),
        response: timestamp.response,
        nonce: nonce,
        imprint: imprint,
        certificate: authority.certificate
      )
    }

    /// One SHA-384 RSA signature over the card's CMS attributes.
    private static func cardSignature(
      attributes: Data,
      key: SecKey
    ) throws -> Data {
      let digest = Data(SHA384.hash(data: attributes))
      var error: Unmanaged<CFError>?
      guard
        let signature = SecKeyCreateSignature(
          key,
          .rsaSignatureDigestPKCS1v15SHA384,
          digest as CFData,
          &error
        )
      else {
        _ = error?.takeRetainedValue()
        throw Failure.signature
      }
      return signature as Data
    }

    /// One ASCII hexadecimal digit.
    private static func hexNibble(_ byte: UInt8) -> UInt8? {
      switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"):
        byte - UInt8(ascii: "0")

      case UInt8(ascii: "A")...UInt8(ascii: "F"):
        byte - UInt8(ascii: "A") + Self.hexadecimalAlphabeticOffset

      default:
        nil
      }
    }
  }

#endif
