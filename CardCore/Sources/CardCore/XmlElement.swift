// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One element of a parsed `XmlDocument`.
internal struct XmlElement: Equatable {
  /// The document the element belongs to.
  internal let document: XmlDocument

  /// Its index in the document's elements.
  internal let index: Int

  /// The element's parsed data.
  internal var data: XmlDocument.Element { document.element(at: index) }

  /// The namespace the element is in, if any.
  internal var namespace: String? { data.namespace }

  /// The local part of the element's name.
  internal var localName: String { data.localName }

  /// The enclosing element.
  internal var parent: Self? {
    data.parent.map { parent in Self(document: document, index: parent) }
  }

  /// The child elements, in document order.
  internal var children: [Self] {
    data.children.compactMap { node in
      guard case .element(let child) = node else { return nil }
      return Self(document: document, index: child)
    }
  }

  /// The element and every element inside it, in document order.
  ///
  /// Elements are stored in document order, so a subtree is the
  /// contiguous run of elements that start inside its span.
  internal var descendants: [Self] {
    let end = data.span.upperBound
    var found = [self]
    var next = index + 1
    while next < document.elementCount, document.element(at: next).span.lowerBound < end {
      found.append(Self(document: document, index: next))
      next += 1
    }
    return found
  }

  /// The concatenated character data of the element's direct children.
  internal var text: String {
    var out = ""
    for node in data.children {
      if case .text(let text) = node { out += text }
    }
    return out
  }

  /// The bytes of the source the element occupies, from the `<` of its
  /// start tag through the `>` of its end tag.
  internal var span: Range<Int> { data.span }

  internal static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.document === rhs.document && lhs.index == rhs.index
  }

  /// Whether the element has this namespace and local name.
  internal func matches(_ namespace: String, _ localName: String) -> Bool {
    self.namespace == namespace && self.localName == localName
  }

  /// The value of the attribute with this local name and no namespace.
  internal func attribute(_ localName: String) -> String? {
    data.attributes.first { attribute in
      attribute.namespace == nil && attribute.localName == localName
    }?.value
  }

  /// The value of this element's own `xml:` attribute `localName`.
  internal func xmlAttribute(_ localName: String) -> String? {
    data.attributes.first { attribute in attribute.isXml(localName) }?.value
  }

  /// The child elements with this namespace and local name.
  internal func children(_ namespace: String, _ localName: String) -> [Self] {
    children.filter { child in child.matches(namespace, localName) }
  }

  /// The first child element with this namespace and local name.
  internal func child(_ namespace: String, _ localName: String) -> Self? {
    children.first { child in child.matches(namespace, localName) }
  }
}
