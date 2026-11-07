// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a document did not parse as the XML `XmlDocument` reads.
public enum XmlReadError: Error, Equatable, Sendable {
  /// The text is not well-formed XML, or misuses namespaces.
  case malformed(String)

  /// The bytes are not UTF-8.
  case notUtf8

  /// Elements nest deeper than the reader accepts.
  case tooDeep

  /// The document holds more nodes than the reader accepts.
  case tooManyNodes

  /// Well-formed XML using a feature the reader refuses.
  case unsupported(String)
}
