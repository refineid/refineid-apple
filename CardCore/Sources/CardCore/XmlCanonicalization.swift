// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One canonicalisation method: the algorithm and its comment mode.
internal struct XmlCanonicalization: Equatable, Sendable {
  /// The canonicalisation algorithms `XmlCanonicalizer` computes.
  internal enum Algorithm: Equatable, Sendable {
    /// Canonical XML 1.0: every namespace in scope rendered at the
    /// apex, every `xml:` attribute inherited from omitted ancestors.
    case canonical10

    /// Canonical XML 1.1: as 1.0, with only `xml:lang` and `xml:space`
    /// inherited.
    case canonical11

    /// Exclusive XML Canonicalization 1.0, the prefixes of its
    /// `InclusiveNamespaces PrefixList` rendered as inclusive Canonical
    /// XML renders them.
    case exclusive(InclusivePrefixes)
  }

  /// Whether canonicalisation keeps comments: the `#WithComments`
  /// variant of each algorithm retains them.
  internal enum Comments: Equatable, Sendable {
    /// Comment nodes are not rendered.
    case omitted

    /// Comment nodes are rendered.
    case retained
  }

  /// The prefixes an `InclusiveNamespaces PrefixList` names
  /// (xml-exc-c14n section 4), the default namespace as the empty
  /// string.
  internal struct InclusivePrefixes: Equatable, Sendable {
    /// No prefix listed.
    internal static let empty = Self(prefixes: [])

    /// The `PrefixList` token naming the default namespace.
    private static let defaultToken = "#default"

    /// The named prefixes; the empty string is `#default`.
    internal let prefixes: [String]

    /// Exactly these prefixes.
    private init(prefixes: [String]) {
      self.prefixes = prefixes
    }

    /// The prefixes a `PrefixList` attribute value names.
    ///
    /// Tokens separated by white space, each `#default` or a prefix
    /// without a colon. Nil for any other token.
    internal init?(prefixList: String) {
      var listed: [String] = []
      let separators = Set(XmlParser.whitespace.map { byte in Character(Unicode.Scalar(byte)) })
      for token in prefixList.split(whereSeparator: separators.contains) {
        let prefix: String
        if token == Self.defaultToken {
          prefix = ""
        } else if token.contains(":") || token.hasPrefix("#") {
          return nil
        } else {
          prefix = String(token)
        }
        if !listed.contains(prefix) {
          listed.append(prefix)
        }
      }
      prefixes = listed
    }
  }

  /// Exclusive canonicalisation with comments (xml-exc-c14n section 4).
  internal static let exclusiveWithCommentsUri =
    XadesSignature.canonicalizationExclusive + "WithComments"

  /// Canonical XML 1.0 without comments (xml-c14n section 1.4).
  internal static let inclusive10Uri = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"

  /// Canonical XML 1.0 with comments.
  internal static let inclusive10WithCommentsUri = Self.inclusive10Uri + "#WithComments"

  /// Canonical XML 1.1 without comments (xml-c14n11 section 1.3).
  internal static let inclusive11Uri = "http://www.w3.org/2006/12/xml-c14n11"

  /// Canonical XML 1.1 with comments.
  internal static let inclusive11WithCommentsUri = Self.inclusive11Uri + "#WithComments"

  /// The element under an exclusive `ds:CanonicalizationMethod` or
  /// `ds:Transform` that lists inclusive prefixes (xml-exc-c14n
  /// section 4), in the exclusive canonicalisation namespace.
  internal static let inclusiveNamespacesElement = "InclusiveNamespaces"

  /// Its attribute naming the prefixes.
  internal static let prefixListAttribute = "PrefixList"

  /// Exclusive XML Canonicalization 1.0 without comments and without a
  /// prefix list.
  internal static let exclusive = Self(algorithm: .exclusive(.empty), comments: .omitted)

  /// Canonical XML 1.0 without comments: the canonicalisation of a node
  /// set no transform names (XML Signature 1.1 section 4.4.3.2).
  internal static let inclusive = Self(algorithm: .canonical10, comments: .omitted)

  /// The algorithm.
  internal let algorithm: Algorithm

  /// Whether comments are kept.
  internal let comments: Comments

  /// Exactly this algorithm and comment mode.
  internal init(algorithm: Algorithm, comments: Comments) {
    self.algorithm = algorithm
    self.comments = comments
  }

  /// The method an `Algorithm` URI names without a prefix list, nil for
  /// every canonicalisation the canonicaliser does not compute.
  internal init?(uri: String) {
    switch uri {
    case XadesSignature.canonicalizationExclusive:
      self.init(algorithm: .exclusive(.empty), comments: .omitted)

    case Self.exclusiveWithCommentsUri:
      self.init(algorithm: .exclusive(.empty), comments: .retained)

    case Self.inclusive10Uri:
      self.init(algorithm: .canonical10, comments: .omitted)

    case Self.inclusive10WithCommentsUri:
      self.init(algorithm: .canonical10, comments: .retained)

    case Self.inclusive11Uri:
      self.init(algorithm: .canonical11, comments: .omitted)

    case Self.inclusive11WithCommentsUri:
      self.init(algorithm: .canonical11, comments: .retained)

    default:
      return nil
    }
  }

  /// The method a `ds:CanonicalizationMethod` or `ds:Transform` element
  /// names.
  ///
  /// Its `Algorithm`, and for an exclusive one the prefixes of its one
  /// `InclusiveNamespaces` child when it has one. Nil for a method the
  /// canonicaliser does not compute, or a child it does not read.
  internal init?(method: XmlElement) {
    guard
      let uri = method.attribute(XadesXmlParser.Attribute.algorithm),
      let named = Self(uri: uri)
    else {
      return nil
    }
    let children = method.children
    guard let child = children.first else {
      self = named
      return
    }
    guard
      children.count == 1,
      case .exclusive = named.algorithm,
      child.matches(XadesSignature.canonicalizationExclusive, Self.inclusiveNamespacesElement),
      let list = child.attribute(Self.prefixListAttribute),
      let prefixes = InclusivePrefixes(prefixList: list)
    else {
      return nil
    }
    self.init(algorithm: .exclusive(prefixes), comments: named.comments)
  }
}
