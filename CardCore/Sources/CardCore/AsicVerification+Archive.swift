// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The XAdES archive timestamps of one signature (EN 319 132-1 V1.3.1
/// clause 5.5.2).
///
/// The input is rebuilt from the signature file's own elements, each
/// canonicalised on its own (clause 5.5.2.3): every `ds:Reference`
/// processed in `ds:SignedInfo` order, then `ds:SignedInfo`,
/// `ds:SignatureValue` and `ds:KeyInfo`, then each unsigned signature
/// property that precedes the timestamp, then every `ds:Object` except
/// the one holding `QualifyingProperties`. A reference this verifier
/// cannot process makes the timestamp unsupported, so it proves
/// nothing.
extension AsicVerification {
  /// Element names the archive input reads beyond the parser's.
  private enum ArchiveElement {
    static let archiveTimeStamp = "ArchiveTimeStamp"
  }

  /// The signature elements of one signature file, in document order;
  /// none when the file does not read as a document.
  internal static func signatureElements(in file: Data) -> [XmlElement] {
    guard let document = try? XmlDocument(file) else { return [] }
    return document.allElements().filter { element in
      element.matches(XadesSignature.namespaceDsig, XadesXmlParser.Element.signature)
    }
  }

  /// The state of every archive timestamp of `signature`, whose
  /// `ds:SignatureValue` must carry `signatureValue`; none when it is
  /// another signature.
  internal static func archiveTimestamps(
    of signature: XmlElement,
    signatureValue: Data?,
    evidence: ValidationEvidence,
    judgement: ContainerJudgement
  ) -> [TimestampJudge.Judged] {
    let dsig = XadesSignature.namespaceDsig
    guard
      let value = signature.child(dsig, XadesXmlParser.Element.signatureValue),
      let signatureValue,
      XadesXmlParser.base64(value.text) == signatureValue
    else {
      return []
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
      return []
    }
    let otherObjects = objects.filter { object in object != qualifying.parent }
    var preceding: [XmlElement] = []
    var states: [TimestampJudge.Judged] = []
    for property in properties.children {
      guard property.matches(XadesSignature.namespaceXades141, ArchiveElement.archiveTimeStamp)
      else {
        preceding.append(property)
        continue
      }
      states.append(
        Self.archiveState(
          property,
          input: Self.archiveInput(
            signature: signature,
            method: Self.method(of: property),
            preceding: preceding,
            otherObjects: otherObjects,
            entries: judgement.entries
          ),
          evidence: evidence,
          judgement: judgement
        ))
      preceding.append(property)
    }
    return states
  }

  /// The canonicalisation an archive timestamp names; absent, Canonical
  /// XML 1.0 (EN 319 132-1 clause 5.5.2.2); nil for one not computed.
  private static func method(of stamp: XmlElement) -> XmlCanonicalization? {
    guard
      let element = stamp.child(
        XadesSignature.namespaceDsig, XadesXmlParser.Element.canonicalizationMethod)
    else {
      return .inclusive
    }
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

  /// The octets an archive timestamp imprints, or nil when one part
  /// cannot be rebuilt.
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
          reference, document: signature.document, method: method, entries: entries)
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

  /// One reference processed (W3C XML Signature 1.1 section 4.4.3.2).
  ///
  /// A carried file without transforms dereferences to its octets; a
  /// same-document reference yields its element under its one
  /// canonicalisation transform, or under `method` when it names none.
  /// Nil for every other reference.
  private static func processed(
    _ reference: XmlElement,
    document: XmlDocument,
    method: XmlCanonicalization,
    entries: [String: Data]
  ) -> Data? {
    let uri = reference.attribute(XadesXmlParser.Attribute.uri) ?? ""
    let transforms =
      reference.child(XadesSignature.namespaceDsig, XadesXmlParser.Element.transforms)?
      .children ?? []
    guard uri.hasPrefix(Self.sameDocumentUriPrefix) else {
      guard transforms.isEmpty, !uri.isEmpty else { return nil }
      return entries[uri.removingPercentEncoding ?? uri]
    }
    let identifier = String(uri.dropFirst(Self.sameDocumentUriPrefix.count))
    guard let target = document.element(withId: identifier) else { return nil }
    guard let transform = transforms.first else {
      return XmlCanonicalizer.canonicalize(target, method: method, omitting: nil)
    }
    guard
      transforms.count == 1,
      transform.matches(XadesSignature.namespaceDsig, XadesXmlParser.Element.transform),
      let named = XmlCanonicalization(method: transform)
    else {
      return nil
    }
    return XmlCanonicalizer.canonicalize(target, method: named, omitting: nil)
  }
}
