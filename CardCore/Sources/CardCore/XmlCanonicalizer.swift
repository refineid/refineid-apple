// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Renders one element and its descendants under Canonical XML 1.0,
/// Canonical XML 1.1 or Exclusive XML Canonicalization 1.0.
///
/// The element is the apex of the node set and its ancestors are
/// omitted, as each of the three algorithms renders a subset, with or
/// without comments: the inclusive ones with every namespace in scope
/// and the inherited `xml:` attributes on the apex, the exclusive one
/// with the prefixes each element visibly utilises and those of an
/// `InclusiveNamespaces PrefixList`.
///
/// Conformance: W3C Canonical XML 1.0 sections 2.2, 2.3 and 2.4; W3C
/// Canonical XML 1.1 section 2.4, except that an `xml:base` on an
/// omitted ancestor, whose fixup joins URI references, is not computed
/// and refuses the rendering; W3C Exclusive XML Canonicalization 1.0
/// sections 3 and 4.
internal struct XmlCanonicalizer {
  /// A namespace declaration in scope or rendered.
  internal struct Binding: Equatable {
    /// The prefix; empty for the default namespace.
    internal let prefix: String

    /// The namespace name; empty for an undeclared default.
    internal let uri: String
  }

  /// The local name of `xml:base` (W3C XML Base section 3).
  internal static let xmlBase = "base"

  /// The local name of `xml:lang` (XML 1.0 section 2.12), whose empty
  /// value is not inherited under Canonical XML 1.1.
  internal static let xmlLang = "lang"

  /// The simple inheritable attributes of Canonical XML 1.1 section
  /// 2.4, `xml:lang` and `xml:space`, by local name.
  internal static let simpleInheritable = [Self.xmlLang, "space"]

  /// The method rendered under.
  private let method: XmlCanonicalization

  /// The element left out with its subtree, if any.
  private let omitted: Int?

  /// The output so far.
  private var out = Data()

  /// The namespace declarations in effect from output ancestors,
  /// innermost last.
  private var rendered: [Binding] = []

  private init(method: XmlCanonicalization, omitted: Int?) {
    self.method = method
    self.omitted = omitted
  }

  /// `element` and its descendants under `method`, as the node set of
  /// this subtree.
  ///
  /// That is the form a same-document reference yields, and the form
  /// `ds:SignedInfo` is canonicalised in (W3C XML Signature 1.1
  /// sections 4.4.3.3 and 4.4.1). With `omitting`, the subtree of that
  /// element, one inside `element`, is left out: the
  /// enveloped-signature transform (section 6.6.4). Nil when the
  /// rendering is refused.
  internal static func canonicalize(
    _ element: XmlElement,
    method: XmlCanonicalization,
    omitting: XmlElement?
  ) -> Data? {
    guard !Self.refusesRendering(element, under: method.algorithm) else { return nil }
    var canonicalizer = Self(method: method, omitted: omitting?.index)
    let outerScope = element.parent.map(Self.inScope) ?? []
    canonicalizer.render(
      element,
      inherited: Self.inheritedXmlAttributes(of: element, under: method.algorithm),
      parentScope: outerScope
    )
    return canonicalizer.out
  }

  /// Whether `lhs` sorts before `rhs` in code point order, the order
  /// Canonical XML 1.0 section 2.2 sorts namespace and attribute nodes
  /// in.
  internal static func precedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }

  /// Whether `lhs` sorts before `rhs` as attribute nodes sort: by
  /// namespace URI, then local name; an attribute in no namespace has
  /// the empty URI and sorts first.
  private static func precedes(_ lhs: XmlDocument.Attribute, _ rhs: XmlDocument.Attribute) -> Bool {
    let leftNamespace = lhs.namespace ?? ""
    let rightNamespace = rhs.namespace ?? ""
    guard leftNamespace == rightNamespace else {
      return Self.precedes(leftNamespace, rightNamespace)
    }
    return Self.precedes(lhs.localName, rhs.localName)
  }

  /// Renders `element`.
  ///
  /// `inherited` holds the `xml:` attributes the apex takes from its
  /// omitted ancestors; it is empty below the apex, whose parent is
  /// always in the output.
  private mutating func render(
    _ element: XmlElement,
    inherited: [XmlDocument.Attribute],
    parentScope: [Binding]
  ) {
    let data = element.data
    let scopeDepth = rendered.count
    let scope = Self.scope(of: element, from: parentScope)
    let declarations = declarationsToRender(element, scope: scope)
    append("<")
    appendQualifiedName(prefix: data.prefix, localName: data.localName)
    for declaration in declarations {
      append(" ")
      append(XmlDocument.prefixXmlns)
      if !declaration.prefix.isEmpty {
        append(":")
        append(declaration.prefix)
      }
      append("=\"")
      appendAttributeValue(declaration.uri)
      append("\"")
    }
    for attribute in (data.attributes + inherited).sorted(by: Self.precedes) {
      append(" ")
      appendQualifiedName(prefix: attribute.prefix, localName: attribute.localName)
      append("=\"")
      appendAttributeValue(attribute.value)
      append("\"")
    }
    append(">")
    rendered.append(contentsOf: declarations)
    for node in data.children {
      renderChild(node, of: element, scope: scope)
    }
    append("</")
    appendQualifiedName(prefix: data.prefix, localName: data.localName)
    append(">")
    rendered.removeLast(rendered.count - scopeDepth)
  }

  /// Renders one child node of `element`.
  private mutating func renderChild(
    _ node: XmlDocument.Node,
    of element: XmlElement,
    scope: [Binding]
  ) {
    switch node {
    case .element(let index):
      guard index != omitted else { return }
      render(
        XmlElement(document: element.document, index: index), inherited: [], parentScope: scope)

    case .text(let text):
      appendText(text)

    case .comment(let text):
      guard method.comments == .retained else { return }
      append("<!--")
      append(text)
      append("-->")

    case .processingInstruction(let target, let data):
      append("<?")
      append(target)
      if !data.isEmpty {
        append(" ")
        append(data)
      }
      append("?>")
    }
  }

  /// The prefixes `element` must consider rendering.
  ///
  /// Under exclusive canonicalisation the ones it visibly utilises, its
  /// own and those of its prefixed attributes (an unprefixed attribute
  /// is in no namespace and uses none), and the `PrefixList` prefixes
  /// (xml-exc-c14n sections 3 and 4); under inclusive canonicalisation
  /// the default and every prefix in scope (xml-c14n section 2.3).
  private func candidatePrefixes(of element: XmlElement, scope: [Binding]) -> [String] {
    var candidates: [String] = []
    func add(_ prefix: String) {
      if !candidates.contains(prefix) { candidates.append(prefix) }
    }
    switch method.algorithm {
    case .exclusive(let inclusive):
      add(element.data.prefix ?? "")
      for attribute in element.data.attributes {
        if let prefix = attribute.prefix { add(prefix) }
      }
      for prefix in inclusive.prefixes { add(prefix) }

    case .canonical10, .canonical11:
      add("")
      for binding in scope { add(binding.prefix) }
    }
    return candidates.filter { prefix in prefix != XmlDocument.prefixXml }
  }

  /// The namespace declarations `element` renders.
  ///
  /// For each candidate prefix, the URI in scope here when it differs
  /// from the one in effect from the nearest output ancestor;
  /// `xmlns=""` when the output parent has a default and this element
  /// has none. Sorted as namespace nodes sort, the default first.
  private func declarationsToRender(_ element: XmlElement, scope: [Binding]) -> [Binding] {
    var declarations: [Binding] = []
    for prefix in candidatePrefixes(of: element, scope: scope) {
      let uri = scope.first { $0.prefix == prefix }?.uri ?? ""
      let inEffect = rendered.last { $0.prefix == prefix }?.uri ?? ""
      if uri != inEffect {
        declarations.append(Binding(prefix: prefix, uri: uri))
      }
    }
    return declarations.sorted { lhs, rhs in Self.precedes(lhs.prefix, rhs.prefix) }
  }

  private mutating func append(_ text: String) {
    out.append(contentsOf: text.utf8)
  }

  private mutating func appendQualifiedName(prefix: String?, localName: String) {
    if let prefix {
      append(prefix)
      append(":")
    }
    append(localName)
  }

  /// Escapes an attribute value as Canonical XML 1.0 section 2.3 writes
  /// it: `&`, `<`, `"`, TAB, LF and CR.
  private mutating func appendAttributeValue(_ value: String) {
    for scalar in value.unicodeScalars {
      switch scalar {
      case "&":
        append("&amp;")

      case "<":
        append("&lt;")

      case "\"":
        append("&quot;")

      case "\t":
        append("&#x9;")

      case "\n":
        append("&#xA;")

      case "\r":
        append("&#xD;")

      default:
        out.append(contentsOf: String(scalar).utf8)
      }
    }
  }

  /// Escapes character data as Canonical XML 1.0 section 2.3 writes it:
  /// `&`, `<`, `>` and CR.
  private mutating func appendText(_ text: String) {
    for scalar in text.unicodeScalars {
      switch scalar {
      case "&":
        append("&amp;")

      case "<":
        append("&lt;")

      case ">":
        append("&gt;")

      case "\r":
        append("&#xD;")

      default:
        out.append(contentsOf: String(scalar).utf8)
      }
    }
  }
}
