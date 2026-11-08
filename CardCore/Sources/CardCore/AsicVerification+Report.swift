// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

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
      guard
        let signatureXmlData = judgement.entries[signatureFileName],
        String(data: signatureXmlData, encoding: .utf8) != nil
      else {
        rows.append(.unsupported)
        continue
      }
      let parser = XadesXmlParser()
      let parsedSignatures = parser.parse(data: signatureXmlData)
      guard parser.parsedWholeDocument, !parsedSignatures.isEmpty else {
        rows.append(.unsupported)
        continue
      }
      // The same signatures in the same document order, as elements an
      // archive timestamp's input is rebuilt from.
      let elements = Self.signatureElements(in: signatureXmlData)
      for (index, parsed) in parsedSignatures.enumerated() {
        guard
          !parsed.isCounterSignature,
          let report = Self.report(
            of: parsed,
            element: elements.indices.contains(index) ? elements[index] : nil,
            judgement: judgement
          )
        else {
          rows.append(.unsupported)
          continue
        }
        rows.append(.judged(report))
      }
    }
    return rows
  }

  /// The certificates, revocation values and signature timestamps one
  /// signature carries.
  private static func evidence(of parsed: ParsedSignature) -> ValidationEvidence {
    var evidence = ValidationEvidence()
    evidence.add(certificates: parsed.keyInfoCertificates + parsed.certificateValues)
    evidence.add(ocspResponses: parsed.ocspValues, revocationLists: parsed.crlValues)
    for token in parsed.signatureTimestampTokens {
      evidence.add(cms: token)
    }
    return evidence
  }

  /// The state of each `xades:SignatureTimeStamp` over the signature
  /// value.
  private static func signatureTimestamps(
    of parsed: ParsedSignature,
    evidence: ValidationEvidence,
    judgement: ContainerJudgement
  ) -> [TimestampState] {
    parsed.signatureTimestampTokens.map { token in
      TimestampJudge.state(
        of: token,
        imprintMatches: { digest, imprint in
          matchesSignatureValue(parsed: parsed, digest: digest, imprint: imprint)
        },
        evidence: evidence,
        anchors: judgement.anchors,
        now: judgement.now
      )
    }
  }

  /// The report of one XAdES signature, or nil when it carries no
  /// readable signer.
  private static func report(
    of parsed: ParsedSignature,
    element: XmlElement?,
    judgement: ContainerJudgement
  ) -> DocumentVerification.SignatureReport? {
    guard
      let binding = Self.signerBinding(of: parsed),
      let secCertificate = SecCertificateCreateWithData(nil, binding.signer as CFData),
      let signerPublicKey = SecCertificateCopyKey(secCertificate)
    else {
      return nil
    }
    let integrity = checkDocumentIntegrity(
      parsed: parsed,
      entries: judgement.entries,
      carriedFileNames: judgement.carriedFileNames
    )
    let signatureValid =
      binding.bindsValidly
      && verifyCryptographicSignature(
        parsed: parsed,
        publicKey: signerPublicKey
      )
    let evidence = Self.evidence(of: parsed)
    let timestamps = Self.signatureTimestamps(of: parsed, evidence: evidence, judgement: judgement)
    let archiveTimestamps =
      element.map { signature in
        Self.archiveTimestamps(
          of: signature,
          signatureValue: parsed.signatureValueBytes,
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
        archiveTimestamps: archiveTimestamps,
        carriesValidationData: !parsed.ocspValues.isEmpty || !parsed.crlValues.isEmpty
      ),
      evidence: evidence,
      anchors: judgement.anchors,
      now: judgement.now
    )
  }

  /// The signer of `parsed` and whether its signing-certificate
  /// property binds it as EN 319 132-1 clause 5.2.2 requires, or nil
  /// when no signer is established.
  ///
  /// The first `xades:Cert` names the signing certificate; it must name
  /// a certificate the signature carries, or there is no signer. Without
  /// the property the first `ds:KeyInfo` certificate is the signer and
  /// the binding fails. Both SigningCertificate and SigningCertificateV2
  /// present fail the binding. A digest method this verifier does not
  /// know, in a reference or a Cert, makes the signature unsupported.
  private static func signerBinding(
    of parsed: ParsedSignature
  ) -> (signer: Data, bindsValidly: Bool)? {
    if case .unsupported = parsed.references { return nil }
    guard case .complete(let stated) = parsed.signingCertificates else { return nil }
    guard let first = stated.first else {
      return parsed.signerCertificateDer.map { signer in (signer, false) }
    }
    let carried = parsed.keyInfoCertificates + parsed.certificateValues
    guard
      let signer = carried.first(where: { candidate in Self.names(candidate, first) })
    else {
      return nil
    }
    let properties = Set(stated.map(\.property))
    return (signer, properties.count == 1)
  }

  /// Whether `reference` names `certificate`: the digest under its own
  /// method, and the issuer and serial when the Cert states them.
  ///
  /// `xades:IssuerSerialV2` is compared in full, issuer name and serial.
  /// Of `xades:IssuerSerial`, the decimal X509SerialNumber is compared
  /// with the certificate's serial; the X509IssuerName text is not.
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

    case .text(_, let serialNumber):
      return Self.decimal(facts.serialNumber) == serialNumber
    }
  }
}
