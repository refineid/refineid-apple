// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Offline verification for ASiC-E / BDOC containers and embedded XAdES signatures.
public enum AsicVerification {
  /// One parsed reference inside ds:SignedInfo.
  internal struct ParsedReference: Sendable {
    internal let identifier: String?
    internal let uri: String
    internal let type: String?
    /// The `Algorithm` of each `ds:Transform`, in document order.
    internal let transforms: [String]
    internal let digestMethod: String
    internal let digestValue: Data
  }

  /// All extracted fields from one ds:Signature element.
  internal struct ParsedSignature: Sendable {
    internal var signatureMethod: String?
    internal var canonicalizationMethod: String?
    internal var references: [ParsedReference] = []
    /// False when a `ds:Reference` in `ds:SignedInfo` lacked its URI,
    /// digest method or digest value.
    internal var allReferencesRead = true
    internal var signedInfoRawXml: String?
    internal var signatureValueId: String?
    internal var signatureValueBytes: Data?
    internal var signatureValueRawXml: String?
    internal var signerCertificateDer: Data?
    internal var signedPropertiesId: String?
    internal var signedPropertiesRawXml: String?
    /// Tokens from `xades:SignatureTimeStamp` elements only.
    internal var signatureTimestampTokens: [Data] = []
  }

  /// Prefix of a same-document reference URI, a fragment identifier
  /// (W3C XML-Signature 1.1 section 4.4.3.2).
  internal static let sameDocumentUriPrefix = "#"

  private static let bdocMimeType = "application/vnd.bdoc-1.0"

  /// Whether the data matches an ASiC-E or BDOC archive structure.
  public static func isAsicContainer(_ data: Data) -> Bool {
    guard ZipReader.hasZipSignature(data) else { return false }
    let entries = ZipReader.read(archive: data)
    guard !entries.isEmpty else { return false }

    if hasAsicMimetype(in: entries) {
      return true
    }
    return entries.keys.contains { key in
      key.hasPrefix("META-INF/") && key.hasSuffix(".xml")
        && (key.contains("signature") || key.contains("signatures"))
    }
  }

  private static func hasAsicMimetype(in entries: [String: Data]) -> Bool {
    guard let mimetypeData = entries[AsicContainer.mimetypeEntryName],
      let mimetype = String(data: mimetypeData, encoding: .utf8)
        ?? String(data: mimetypeData, encoding: .ascii)
    else {
      return false
    }
    let trimmed = mimetype.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == AsicContainer.mimeType || trimmed == bdocMimeType
  }

  /// Verifies an ASiC-E or BDOC container, returning a complete DocumentReport.
  public static func verify(
    container: Data
  ) throws -> DocumentVerification.DocumentReport {
    let entries = ZipReader.read(archive: container)
    guard !entries.isEmpty else {
      throw DocumentVerification.Failure.unreadable
    }

    let signatureFiles =
      entries.keys
      .filter { key in
        key.hasPrefix("META-INF/") && key.hasSuffix(".xml")
          && (key.contains("signature") || key.contains("signatures"))
      }
      .sorted()

    guard !signatureFiles.isEmpty else {
      throw DocumentVerification.Failure.noSignatures
    }

    let carriedFileNames = Set(
      entries.keys.filter { name in
        name != AsicContainer.mimetypeEntryName && !name.hasPrefix("META-INF/")
      }
    )

    let reports = parseAndVerifyReports(
      signatureFiles: signatureFiles,
      entries: entries,
      carriedFileNames: carriedFileNames
    )

    guard !reports.isEmpty else {
      throw DocumentVerification.Failure.unsupportedProfile
    }

    return DocumentVerification.DocumentReport(
      signatures: reports,
      documentTimestampedAt: []
    )
  }

  private static func parseAndVerifyReports(
    signatureFiles: [String],
    entries: [String: Data],
    carriedFileNames: Set<String>
  ) -> [DocumentVerification.SignatureReport] {
    var signatureReports: [DocumentVerification.SignatureReport] = []

    for signatureFileName in signatureFiles {
      guard let signatureXmlData = entries[signatureFileName],
        let signatureXml = String(data: signatureXmlData, encoding: .utf8)
      else {
        continue
      }

      let parsedSignatures = XadesXmlParser(xmlString: signatureXml).parse(data: signatureXmlData)
      for parsed in parsedSignatures {
        if let report = verifySignature(
          parsed: parsed,
          entries: entries,
          carriedFileNames: carriedFileNames
        ) {
          signatureReports.append(report)
        }
      }
    }

    return signatureReports
  }

  private static func verifySignature(
    parsed: ParsedSignature,
    entries: [String: Data],
    carriedFileNames: Set<String>
  ) -> DocumentVerification.SignatureReport? {
    guard let signerCertDer = parsed.signerCertificateDer,
      let secCert = SecCertificateCreateWithData(nil, signerCertDer as CFData),
      let signerPublicKey = SecCertificateCopyKey(secCert),
      let facts = CertificateFacts(der: signerCertDer)
    else {
      return nil
    }

    let integrity = checkDocumentIntegrity(
      parsed: parsed,
      entries: entries,
      carriedFileNames: carriedFileNames
    )
    let signatureValid = verifyCryptographicSignature(
      parsed: parsed,
      publicKey: signerPublicKey
    )
    let (timestampsValid, timestampedAt) = verifyTimestamps(parsed: parsed)
    let issuer = chainIssuer(
      of: signerCertDer,
      at: timestampedAt ?? Date()
    )

    return DocumentVerification.SignatureReport(
      signerName: DistinguishedName.personalName(inName: facts.subjectName)
        ?? DistinguishedName.commonName(inName: facts.subjectName)
        ?? "",
      signerIdentifier: DistinguishedName.identifier(inName: facts.subjectName) ?? "",
      signerCertificate: signerCertDer,
      issuerCertificate: issuer,
      documentIntact: integrity.documentIntact,
      signatureValid: signatureValid,
      chainVerified: issuer != nil,
      timestampedAt: timestampedAt,
      timestampsValid: timestampsValid,
      coversWholeDocument: integrity.coversWholeDocument
    )
  }

  /// Recomputes every reference in `ds:SignedInfo`
  /// (W3C XML-Signature 1.1 section 3.2.1).
  ///
  /// Fails closed: a reference this verifier cannot recompute counts
  /// as a mismatch, never as a match. A data object reference must
  /// name a carried file and declare no transform; the one
  /// same-document reference must cover the signature's own
  /// `xades:SignedProperties` (EN 319 132-1 clause 4.4.2). Every file
  /// outside `META-INF/` must be referenced (EN 319 162-1
  /// clause 4.4.3.2).
  private static func checkDocumentIntegrity(
    parsed: ParsedSignature,
    entries: [String: Data],
    carriedFileNames: Set<String>
  ) -> (documentIntact: Bool, coversWholeDocument: Bool) {
    var referencedFiles: Set<String> = []
    var allDigestsMatch = parsed.allReferencesRead
    var signedPropertiesCovered = false

    for ref in parsed.references {
      if ref.uri.hasPrefix(sameDocumentUriPrefix) || ref.type == XadesSignature.signedPropertiesType
      {
        if !signedPropertiesCovered, isSignedPropertiesValid(parsed: parsed, ref: ref) {
          signedPropertiesCovered = true
        } else {
          allDigestsMatch = false
        }
        continue
      }

      let entryName = ref.uri.removingPercentEncoding ?? ref.uri
      referencedFiles.insert(entryName)

      guard ref.transforms.isEmpty,
        let fileContent = entries[entryName],
        let calculatedDigest = digest(of: fileContent, algorithm: ref.digestMethod),
        calculatedDigest == ref.digestValue
      else {
        allDigestsMatch = false
        continue
      }
    }

    let allCarriedFilesCovered =
      carriedFileNames.isSubset(of: referencedFiles) && !carriedFileNames.isEmpty
    let documentIntact = allDigestsMatch && signedPropertiesCovered && allCarriedFilesCovered
    return (documentIntact, allCarriedFilesCovered && documentIntact)
  }

  /// Whether `ref` covers this signature's `xades:SignedProperties`
  /// and its digest matches.
  ///
  /// The reference must carry the SignedProperties `Type`, name the
  /// element's `Id`, and declare exclusive canonicalisation as its
  /// one transform, the form `XadesSignature` writes. The element is
  /// digested as it stands in the document, which equals its
  /// exclusive canonical form only when it was written in that form;
  /// any other spelling digests differently and fails. A missing
  /// element or an unsupported digest method fails too.
  private static func isSignedPropertiesValid(
    parsed: ParsedSignature,
    ref: ParsedReference
  ) -> Bool {
    guard ref.type == XadesSignature.signedPropertiesType,
      ref.transforms == [XadesSignature.canonicalizationExclusive],
      let propertiesId = parsed.signedPropertiesId,
      ref.uri == sameDocumentUriPrefix + propertiesId,
      let propertiesRaw = parsed.signedPropertiesRawXml,
      let computedDigest = digest(of: Data(propertiesRaw.utf8), algorithm: ref.digestMethod)
    else {
      return false
    }
    return computedDigest == ref.digestValue
  }

  private static func chainIssuer(
    of signer: Data,
    at referenceTime: Date
  ) -> Data? {
    guard
      let issuer = IssuerCertificate.der(matching: signer),
      CertificateIssuer.isDirectlyIssued(signer, by: issuer, at: referenceTime)
    else {
      return nil
    }
    return issuer
  }
}
