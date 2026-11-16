// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The XAdES archive timestamps of one signature (EN 319 132-1 V1.3.1 clause 5.5.2).
extension AsicVerification {
  /// Element names read when judging archive timestamps.
  private enum ArchiveElement {
    static let archiveTimeStamp = "ArchiveTimeStamp"
    static let include = "Include"
  }

  /// Validation material accumulated from unsigned properties preceding an archive timestamp.
  private struct CoveredMaterial {
    var certificates: [Data]
    var ocspResponses: [Data] = []
    var revocationLists: [Data] = []

    var revocationValues: DocumentVerification.RevocationValues {
      DocumentVerification.RevocationValues(
        ocspResponses: ocspResponses,
        revocationLists: revocationLists
      )
    }
  }

  /// Evaluates every `xadesv141:ArchiveTimeStamp` of `signature` with the material preceding it.
  internal static func archiveTimestamps(
    of signature: XmlElement,
    parsed: ParsedSignature,
    evidence: ValidationEvidence,
    judgement: ContainerJudgement
  ) -> [DocumentVerification.ArchiveCandidate] {
    guard let context = Self.unsignedContext(of: signature, parsed: parsed) else { return [] }
    var preceding: [XmlElement] = []
    var covered = CoveredMaterial(certificates: parsed.keyInfoCertificates)
    var candidates: [DocumentVerification.ArchiveCandidate] = []
    for property in context.properties.children {
      if property.matches(XadesSignature.namespaceXades141, ArchiveElement.archiveTimeStamp) {
        let input =
          Self.hasDistributedInclude(property)
          ? nil
          : Self.archiveInput(
            signature: signature,
            method: Self.method(of: property),
            preceding: preceding,
            otherObjects: context.otherObjects,
            entries: judgement.entries
          )
        let judged = Self.archiveState(
          property, input: input, evidence: evidence, judgement: judgement)
        candidates.append(
          DocumentVerification.ArchiveCandidate(
            state: judged.state,
            covered: covered.revocationValues,
            coveredCertificates: covered.certificates,
            validUntil: judged.validUntil
          ))
      } else if property.matches(XadesSignature.namespaceXades, ArchiveElement.archiveTimeStamp) {
        candidates.append(
          DocumentVerification.ArchiveCandidate(
            state: .unsupported,
            covered: covered.revocationValues,
            coveredCertificates: covered.certificates,
            validUntil: nil
          ))
      } else {
        Self.accumulateMaterial(from: property, into: &covered)
      }
      preceding.append(property)
    }
    return candidates
  }

  /// Unsigned signature properties element and sibling `ds:Object`s for archive imprint construction.
  private static func unsignedContext(
    of signature: XmlElement,
    parsed: ParsedSignature
  ) -> (properties: XmlElement, otherObjects: [XmlElement])? {
    guard !parsed.hasStructuralError else { return nil }
    let dsig = XadesSignature.namespaceDsig
    guard
      let value = signature.child(dsig, XadesXmlParser.Element.signatureValue),
      let signatureValue = parsed.signatureValueBytes,
      XadesXmlParser.base64(value.text) == signatureValue
    else {
      return nil
    }
    let objects = signature.children(dsig, XadesXmlParser.Element.object)
    guard
      let qualifying = objects.lazy.compactMap({ object in
        object.child(XadesSignature.namespaceXades, XadesXmlParser.Element.qualifyingProperties)
      }).first,
      let properties = qualifying.child(
        XadesSignature.namespaceXades, XadesXmlParser.Element.unsignedProperties)?
        .child(XadesSignature.namespaceXades, XadesXmlParser.Element.unsignedSignatureProperties)
    else {
      return nil
    }
    let otherObjects = objects.filter { object in object != qualifying.parent }
    return (properties, otherObjects)
  }

  /// Whether `stamp` carries `Include` children requiring distributed property resolution.
  private static func hasDistributedInclude(_ stamp: XmlElement) -> Bool {
    stamp.children.contains { child in
      child.matches(XadesSignature.namespaceXades, ArchiveElement.include)
        || child.matches(XadesSignature.namespaceXades141, ArchiveElement.include)
    }
  }

  /// Adds certificates, CRLs, and OCSP responses from one unsigned property into `covered`.
  private static func accumulateMaterial(
    from property: XmlElement, into covered: inout CoveredMaterial
  ) {
    let extracted = XadesXmlParser.validationMaterial(in: property)
    covered.certificates.append(contentsOf: extracted.certificates)
    covered.ocspResponses.append(contentsOf: extracted.ocspResponses)
    covered.revocationLists.append(contentsOf: extracted.revocationLists)
  }

  /// The canonicalisation an archive timestamp names; absent means Canonical XML 1.0.
  private static func method(of stamp: XmlElement) -> XmlCanonicalization? {
    let elements = stamp.children(
      XadesSignature.namespaceDsig, XadesXmlParser.Element.canonicalizationMethod)
    guard let element = elements.first else {
      return .inclusive
    }
    guard elements.count == 1 else { return nil }
    return XmlCanonicalization(method: element)
  }

  /// The judged state of one archive timestamp over `input`.
  private static func archiveState(
    _ stamp: XmlElement,
    input: Data?,
    evidence: ValidationEvidence,
    judgement: ContainerJudgement
  ) -> TimestampJudge.Judged {
    let tokens = stamp.children(
      XadesSignature.namespaceXades, XadesXmlParser.Element.encapsulatedTimeStamp)
    guard
      let input,
      let only = tokens.first,
      tokens.count == 1,
      only.children.isEmpty,
      let token = XadesXmlParser.base64(only.text)
    else {
      return TimestampJudge.Judged(state: .unsupported, validUntil: nil)
    }
    return TimestampJudge.judged(
      token,
      imprintMatches: { digest, imprint in digest.hash(input) == imprint },
      evidence: evidence,
      anchors: judgement.anchors,
      now: judgement.now
    )
  }

  /// The octets an archive timestamp imprints, or nil when one part cannot be rebuilt.
  private static func archiveInput(
    signature: XmlElement,
    method: XmlCanonicalization?,
    preceding: [XmlElement],
    otherObjects: [XmlElement],
    entries: [String: Data]
  ) -> Data? {
    let dsig = XadesSignature.namespaceDsig
    guard
      let method,
      let signedInfo = signature.child(dsig, XadesXmlParser.Element.signedInfo),
      let signatureValue = signature.child(dsig, XadesXmlParser.Element.signatureValue)
    else {
      return nil
    }
    var input = Data()
    for reference in signedInfo.children(dsig, XadesXmlParser.Element.reference) {
      guard
        let octets = Self.processed(
          reference, document: signature.document, entries: entries)
      else {
        return nil
      }
      input.append(octets)
    }
    var elements = [signedInfo, signatureValue]
    elements += signature.children(dsig, XadesXmlParser.Element.keyInfo)
    elements += preceding
    elements += otherObjects
    for element in elements {
      guard let rendered = XmlCanonicalizer.canonicalize(element, method: method, omitting: nil)
      else {
        return nil
      }
      input.append(rendered)
    }
    return input
  }

  /// Processes one `ds:Reference` for an archive timestamp imprint (W3C XML Signature 1.1 §4.4.3.2).
  private static func processed(
    _ reference: XmlElement,
    document: XmlDocument,
    entries: [String: Data]
  ) -> Data? {
    let uri = reference.attribute(XadesXmlParser.Attribute.uri) ?? ""
    let transforms =
      reference.child(XadesSignature.namespaceDsig, XadesXmlParser.Element.transforms)?
      .children ?? []
    guard uri.hasPrefix(Self.sameDocumentUriPrefix) else {
      guard transforms.isEmpty, !uri.isEmpty else { return nil }
      if let content = entries[uri],
        uri != AsicContainer.mimetypeEntryName, !uri.hasPrefix(Self.metaInfPrefix)
      {
        return content
      }
      guard let decoded = uri.removingPercentEncoding,
        decoded != AsicContainer.mimetypeEntryName, !decoded.hasPrefix(Self.metaInfPrefix)
      else {
        return nil
      }
      return entries[decoded]
    }
    let identifier = String(uri.dropFirst(Self.sameDocumentUriPrefix.count))
    guard let target = document.element(withId: identifier) else { return nil }
    guard let transform = transforms.first else {
      return XmlCanonicalizer.canonicalize(target, method: .inclusive, omitting: nil)
    }
    guard
      transforms.count == 1,
      transform.matches(XadesSignature.namespaceDsig, XadesXmlParser.Element.transform),
      let named = XmlCanonicalization(method: transform)
    else {
      return nil
    }
    let stripped = XmlCanonicalization(algorithm: named.algorithm, comments: .omitted)
    return XmlCanonicalizer.canonicalize(target, method: stripped, omitting: nil)
  }
}
