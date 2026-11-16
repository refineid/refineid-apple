// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The rows of one container's XAdES signatures.
extension AsicVerification {
  /// What every signature of one container is judged with.
  internal struct ContainerJudgement {
    /// The container's entries by name.
    internal let entries: [String: Data]

    /// The files outside `META-INF/` the signatures must cover.
    internal let carriedFileNames: Set<String>

    internal let anchors: TrustAnchors
    internal let now: Date
  }

  /// Every signature in the signature files as a row.
  ///
  /// A signature file that does not read, a counter-signature, and a
  /// signature without a carried signer are unsupported rows; the
  /// neighbours of an unsupported signature are still judged.
  internal static func signatureEntries(
    signatureFiles: [String],
    judgement: ContainerJudgement
  ) -> [DocumentVerification.SignatureEntry] {
    var rows: [DocumentVerification.SignatureEntry] = []
    for signatureFileName in signatureFiles {
      guard let signatureXmlData = judgement.entries[signatureFileName] else {
        rows.append(.unsupported)
        continue
      }
      let parser = XadesXmlParser()
      let parsedSignatures = parser.parse(data: signatureXmlData)
      guard parser.parsedWholeDocument, !parsedSignatures.isEmpty else {
        rows.append(.unsupported)
        continue
      }
      for parsed in parsedSignatures {
        guard !parsed.isCounterSignature,
          let report = Self.report(of: parsed, judgement: judgement)
        else {
          rows.append(.unsupported)
          continue
        }
        rows.append(.judged(report))
      }
    }
    return rows
  }

  /// The certificates, revocation values and signature timestamps one signature carries.
  private static func evidence(of parsed: ParsedSignature) -> ValidationEvidence {
    var evidence = ValidationEvidence()
    evidence.add(certificates: parsed.keyInfoCertificates + parsed.certificateValues)
    evidence.add(ocspResponses: parsed.ocspValues, revocationLists: parsed.crlValues)
    for token in parsed.signatureTimestampTokens {
      evidence.add(cms: token)
    }
    return evidence
  }

  /// The state of each `xades:SignatureTimeStamp` over its canonical `ds:SignatureValue`.
  private static func signatureTimestamps(
    of parsed: ParsedSignature,
    evidence: ValidationEvidence,
    judgement: ContainerJudgement
  ) -> [TimestampState] {
    parsed.signatureTimestamps.map { stamp in
      guard let input = stamp.imprintInput else { return .unsupported }
      return TimestampJudge.state(
        of: stamp.token,
        imprintMatches: { digest, imprint in
          digest.hash(input) == imprint
        },
        evidence: evidence,
        anchors: judgement.anchors,
        now: judgement.now
      )
    }
  }

  /// The report of one XAdES signature, or nil when it carries no readable signer.
  private static func report(
    of parsed: ParsedSignature,
    judgement: ContainerJudgement
  ) -> DocumentVerification.SignatureReport? {
    guard
      let binding = Self.signerBinding(of: parsed),
      XmlSignatureMethod.hasReadablePublicKey(binding.signer)
    else {
      return nil
    }
    let integrity = checkDocumentIntegrity(
      parsed: parsed,
      entries: judgement.entries,
      carriedFileNames: judgement.carriedFileNames
    )
    let signatureValid =
      !parsed.hasStructuralError
      && binding.bindsValidly
      && verifyCryptographicSignature(
        parsed: parsed,
        signerCertificate: binding.signer
      )
    let evidence = Self.evidence(of: parsed)
    let timestamps = Self.signatureTimestamps(of: parsed, evidence: evidence, judgement: judgement)
    let archiveTimestamps =
      parsed.signatureElement.map { signature in
        Self.archiveTimestamps(
          of: signature,
          parsed: parsed,
          evidence: evidence,
          judgement: judgement
        )
      } ?? []
    return DocumentVerification.report(
      DocumentVerification.SignatureFacts(
        signerCertificate: binding.signer,
        documentIntact: integrity.documentIntact,
        signatureValid: signatureValid,
        timestamps: timestamps,
        creditedProofs: [],
        coversWholeDocument: integrity.coversWholeDocument,
        changesAfterSigning: [],
        archiveTimestamps: archiveTimestamps,
        longTermValues: DocumentVerification.RevocationValues(
          ocspResponses: parsed.ocspValues, revocationLists: parsed.crlValues)
      ),
      evidence: evidence,
      anchors: judgement.anchors,
      now: judgement.now
    )
  }

  /// The signer of `parsed` and whether its signing-certificate property binds it validly.
  private static func signerBinding(
    of parsed: ParsedSignature
  ) -> (signer: Data, bindsValidly: Bool)? {
    if case .unsupported = parsed.references { return nil }
    guard case .complete(let stated) = parsed.signingCertificates else { return nil }
    guard let first = stated.first else {
      return parsed.signerCertificateDer.map { signer in (signer, false) }
    }
    let carried = parsed.keyInfoCertificates + parsed.certificateValues
    guard let signer = carried.first(where: { candidate in Self.names(candidate, first) }) else {
      return nil
    }
    let properties = Set(stated.map(\.property))
    return (signer, properties.count == 1)
  }

  /// Whether `reference` names `certificate` by digest and any stated issuer/serial.
  private static func names(
    _ certificate: Data,
    _ reference: SigningCertificateReference
  ) -> Bool {
    guard reference.method.hash(certificate) == reference.value else { return false }
    guard let issuerSerial = reference.issuerSerial else { return true }
    guard let facts = CertificateFacts(der: certificate) else { return false }
    switch issuerSerial {
    case .der(let encoded):
      return CmsSigningCertificate.matches(issuerSerial: encoded, certificate: facts)

    case .text(let issuerName, let serialNumber):
      // `xades:IssuerSerial` formats `X509IssuerName` as an RFC 4514 string whose spacing,
      // escaping, and attribute order vary across signers; `CertDigest` already binds the exact
      // DER certificate, so require non-empty issuer text and match the decimal serial number.
      return !issuerName.isEmpty && Self.decimal(facts.serialNumber) == serialNumber
    }
  }
}
