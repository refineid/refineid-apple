// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the omitted ancestors of an apex contribute to its rendering:
/// the namespace scope and the inherited `xml:` attributes.
extension XmlCanonicalizer {
  /// The ancestors of `element`, nearest first.
  internal static func ancestors(of element: XmlElement) -> [XmlElement] {
    var found: [XmlElement] = []
    var current = element.parent
    while let ancestor = current {
      found.append(ancestor)
      current = ancestor.parent
    }
    return found
  }

  /// Whether rendering `element` as the apex is refused: under
  /// Canonical XML 1.1 an omitted ancestor carries `xml:base`, whose
  /// fixup is not computed.
  internal static func refusesRendering(
    _ element: XmlElement,
    under algorithm: XmlCanonicalization.Algorithm
  ) -> Bool {
    guard algorithm == .canonical11 else { return false }
    return Self.ancestors(of: element).contains { ancestor in
      ancestor.xmlAttribute(Self.xmlBase) != nil
    }
  }

  /// The `xml:` attributes `element` renders from its omitted ancestors
  /// when it is the apex of the subset, beside its own.
  ///
  /// Canonical XML 1.0 section 2.4: every attribute in the XML
  /// namespace nearest along the ancestor axis that the element does
  /// not carry itself. Canonical XML 1.1 section 2.4: only `xml:lang`
  /// and `xml:space` that way, `xml:id` never. Exclusive XML
  /// Canonicalization 1.0 section 3: none.
  internal static func inheritedXmlAttributes(
    of element: XmlElement,
    under algorithm: XmlCanonicalization.Algorithm
  ) -> [XmlDocument.Attribute] {
    let ancestors = Self.ancestors(of: element)
    let own = element.data.attributes
    var inherited: [XmlDocument.Attribute] = []
    switch algorithm {
    case .exclusive:
      break

    case .canonical10:
      for attribute in ancestors.flatMap(\.data.attributes)
      where attribute.namespace == XmlDocument.namespaceXml {
        if !own.contains(where: { $0.isXml(attribute.localName) }),
          !inherited.contains(where: { $0.localName == attribute.localName })
        {
          inherited.append(attribute)
        }
      }

    case .canonical11:
      for localName in Self.simpleInheritable where !own.contains(where: { $0.isXml(localName) }) {
        let nearest = ancestors.lazy.compactMap { ancestor in
          ancestor.data.attributes.first { $0.isXml(localName) }
        }.first
        guard let attribute = nearest else { continue }
        if localName == Self.xmlLang, attribute.value.isEmpty { continue }
        inherited.append(attribute)
      }
    }
    return inherited
  }

  /// The namespace scope at `element`: `parentScope`, the scope of its
  /// parent, with the element's own declarations in effect.
  internal static func scope(of element: XmlElement, from parentScope: [Binding]) -> [Binding] {
    var scope = parentScope
    for declaration in element.data.declarations {
      let binding = Binding(prefix: declaration.prefix ?? "", uri: declaration.uri)
      if let existing = scope.firstIndex(where: { $0.prefix == binding.prefix }) {
        scope[existing] = binding
      } else {
        scope.append(binding)
      }
    }
    return scope
  }

  /// The namespace declarations in scope at `element`, the innermost
  /// for each prefix, an undeclared default as the empty URI.
  ///
  /// The `xml` prefix is never listed: Canonical XML 1.0 section 2.3
  /// omits its namespace node.
  internal static func inScope(_ element: XmlElement) -> [Binding] {
    var scope: [Binding] = []
    var current: XmlElement? = element
    while let ancestor = current {
      for declaration in ancestor.data.declarations {
        let prefix = declaration.prefix ?? ""
        if !scope.contains(where: { $0.prefix == prefix }) {
          scope.append(Binding(prefix: prefix, uri: declaration.uri))
        }
      }
      current = ancestor.parent
    }
    return scope
  }
}
