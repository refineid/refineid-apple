// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The two references of a list signature: to the list and to the
/// signed properties.
extension TrustedListSignature {
  /// What one reference covers.
  private enum Covered {
    /// The list, without its signature.
    case list

    /// The signature's own signed properties.
    case signedProperties
  }

  /// Recomputes both references; each must match, and together they
  /// must cover the list and the signed properties.
  internal static func checkReferences(
    _ references: [XmlElement],
    document: XmlDocument,
    root: XmlElement,
    signature: XmlElement,
    signedProperties: XmlElement
  ) throws {
    var covered: Set<Covered> = []
    for reference in references {
      let digest = try XmlDigestValue(
        parent: reference, what: "Reference without a readable DigestValue")
      let uri = reference.attribute(XadesXmlParser.Attribute.uri) ?? ""
      let transforms =
        reference.child(XadesSignature.namespaceDsig, XadesXmlParser.Element.transforms)?.children
        ?? []
      let octets: Data
      let covers: Covered
      if Self.namesList(uri, root: root), Self.isEnveloped(transforms.first) {
        covers = .list
        let method = try Self.method(ofTransforms: Array(transforms.dropFirst()), "list reference")
        guard
          let rendered = XmlCanonicalizer.canonicalize(root, method: method, omitting: signature)
        else {
          throw TrustedListError.unverifiable("list canonicalisation")
        }
        octets = rendered
      } else if uri.hasPrefix(AsicVerification.sameDocumentUriPrefix),
        reference.attribute(XadesXmlParser.Attribute.type) == XadesSignature.signedPropertiesType
      {
        covers = .signedProperties
        let method = try Self.method(ofTransforms: transforms, "reference")
        let identifier = String(uri.dropFirst(AsicVerification.sameDocumentUriPrefix.count))
        guard
          document.element(withId: identifier) == signedProperties,
          let rendered = XmlCanonicalizer.canonicalize(
            signedProperties, method: method, omitting: nil)
        else {
          throw TrustedListError.signatureInvalid
        }
        octets = rendered
      } else {
        throw TrustedListError.unverifiable("reference outside the list")
      }
      guard covered.insert(covers).inserted else {
        throw TrustedListError.malformed("two references to one target")
      }
      guard digest.matches(octets) else { throw TrustedListError.signatureInvalid }
    }
    guard covered.contains(.list) else {
      throw TrustedListError.malformed("no reference to the list")
    }
    guard covered.contains(.signedProperties) else {
      throw TrustedListError.malformed("no reference to the SignedProperties")
    }
  }

  /// Whether `uri` names the list: empty, or the fragment of the
  /// document element's `Id`.
  private static func namesList(_ uri: String, root: XmlElement) -> Bool {
    guard !uri.isEmpty else { return true }
    guard uri.hasPrefix(AsicVerification.sameDocumentUriPrefix) else { return false }
    let identifier = String(uri.dropFirst(AsicVerification.sameDocumentUriPrefix.count))
    return root.attribute(XmlDocument.attributeId) == identifier
  }

  /// Whether `transform` is the enveloped-signature transform.
  private static func isEnveloped(_ transform: XmlElement?) -> Bool {
    guard let transform else { return false }
    return transform.matches(XadesSignature.namespaceDsig, XadesXmlParser.Element.transform)
      && transform.attribute(XadesXmlParser.Attribute.algorithm) == Self.envelopedSignatureTransform
  }

  /// The canonicalisation `transforms` name: none means Canonical XML
  /// 1.0 (XML Signature 1.1 section 4.4.3.2), one must be a
  /// canonicalisation the canonicaliser computes, more are not
  /// computed.
  private static func method(
    ofTransforms transforms: [XmlElement],
    _ what: String
  ) throws -> XmlCanonicalization {
    guard let transform = transforms.first else { return .inclusive }
    guard
      transforms.count == 1,
      transform.matches(XadesSignature.namespaceDsig, XadesXmlParser.Element.transform),
      let method = XmlCanonicalization(method: transform)
    else {
      throw TrustedListError.unverifiable("\(what) transform")
    }
    return method
  }
}
