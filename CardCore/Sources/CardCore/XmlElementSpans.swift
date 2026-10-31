// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The byte span of every element in one XML document, in the order of
/// their start tags.
///
/// That order is the order in which `XMLParser` reports
/// `didStartElement`, so the n-th element a delegate sees is the n-th
/// span here. A start tag's name runs to whitespace, `/` or `>`, so an
/// element whose name extends another's is a different element, and an
/// end tag closes the innermost open element only when it names it.
/// Comments, CDATA sections and processing instructions are skipped. A
/// document with a document type declaration, an unbalanced or unnamed
/// tag, an unterminated construct, or more elements than
/// `maximumElementCount` yields no spans and is not readable, so every
/// lookup answers nil.
internal struct XmlElementSpans {
  /// One element: its qualified name and its bytes, tags included.
  private struct Span {
    let name: Data
    let start: Int
    var end: Int?
  }

  /// Why the document yields no spans.
  private enum ScanFailure: Error {
    case unreadable
  }

  /// One pass over the document's bytes.
  private struct Scanner {
    let bytes: Data
    var cursor = 0
    var spans: [Span] = []
    var openElements: [Int] = []

    /// Every element's span, or a failure for a document this scan
    /// does not read.
    mutating func run() throws -> [Span] {
      while cursor < bytes.count {
        if bytes[cursor] == XmlElementSpans.tagOpen {
          try self.markup()
        } else {
          cursor += 1
        }
      }
      guard openElements.isEmpty else { throw ScanFailure.unreadable }
      return spans
    }

    /// Reads the markup starting at `cursor`.
    private mutating func markup() throws {
      if self.has(XmlElementSpans.commentOpen) {
        cursor = try self.end(of: XmlElementSpans.commentClose)
      } else if self.has(XmlElementSpans.cdataOpen) {
        cursor = try self.end(of: XmlElementSpans.cdataClose)
      } else if self.has(XmlElementSpans.instructionOpen) {
        cursor = try self.end(of: XmlElementSpans.instructionClose)
      } else if self.has(XmlElementSpans.declarationOpen) {
        throw ScanFailure.unreadable
      } else if self.has(XmlElementSpans.endTagOpen) {
        try self.endTag()
      } else {
        try self.startTag()
      }
    }

    /// Closes the innermost open element, which the end tag must name.
    private mutating func endTag() throws {
      let nameStart = cursor + XmlElementSpans.endTagOpen.count
      let nameEnd = self.nameEnd(from: nameStart)
      let close = try self.tagClose(from: nameEnd)
      guard
        let innermost = openElements.popLast(),
        spans[innermost].name == bytes.subdata(in: nameStart..<nameEnd)
      else {
        throw ScanFailure.unreadable
      }
      spans[innermost].end = close + 1
      cursor = close + 1
    }

    /// Records one element, open until its end tag unless it closes
    /// itself.
    private mutating func startTag() throws {
      let nameStart = cursor + 1
      let nameEnd = self.nameEnd(from: nameStart)
      guard
        nameEnd > nameStart,
        spans.count < XmlElementSpans.maximumElementCount
      else { throw ScanFailure.unreadable }
      let close = try self.tagClose(from: nameEnd)
      let selfClosing = bytes[close - 1] == XmlElementSpans.solidus
      spans.append(
        Span(
          name: bytes.subdata(in: nameStart..<nameEnd),
          start: cursor,
          end: selfClosing ? close + 1 : nil
        ))
      if !selfClosing {
        openElements.append(spans.count - 1)
      }
      cursor = close + 1
    }

    /// Whether `marker` occurs at `cursor`.
    private func has(_ marker: Data) -> Bool {
      self.has(marker, at: cursor)
    }

    private func has(_ marker: Data, at offset: Int) -> Bool {
      offset + marker.count <= bytes.count
        && bytes[offset..<(offset + marker.count)].elementsEqual(marker)
    }

    /// The offset just past the first `marker` at or after `cursor`.
    private func end(of marker: Data) throws -> Int {
      var offset = cursor
      while offset + marker.count <= bytes.count {
        if self.has(marker, at: offset) {
          return offset + marker.count
        }
        offset += 1
      }
      throw ScanFailure.unreadable
    }

    /// Where a tag name starting at `offset` ends.
    private func nameEnd(from offset: Int) -> Int {
      var position = offset
      while position < bytes.count, !XmlElementSpans.nameTerminators.contains(bytes[position]) {
        position += 1
      }
      return position
    }

    /// The offset of the `>` closing a tag, skipping quoted attribute
    /// values.
    private func tagClose(from offset: Int) throws -> Int {
      var quote: UInt8?
      for position in offset..<bytes.count {
        let byte = bytes[position]
        if let opening = quote {
          if byte == opening { quote = nil }
        } else if XmlElementSpans.quotes.contains(byte) {
          quote = byte
        } else if byte == XmlElementSpans.tagClose {
          return position
        }
      }
      throw ScanFailure.unreadable
    }
  }

  private static let tagOpen = UInt8(ascii: "<")
  private static let tagClose = UInt8(ascii: ">")
  private static let solidus = UInt8(ascii: "/")

  /// The two attribute-value delimiters (XML 1.0 production 10).
  private static let quotes: Set<UInt8> = [UInt8(ascii: "\""), UInt8(ascii: "'")]

  /// The bytes that end a tag name: XML whitespace, `/` and `>`.
  private static let nameTerminators: Set<UInt8> = [
    UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"),
    UInt8(ascii: "/"), UInt8(ascii: ">"),
  ]

  private static let commentOpen = Data("<!--".utf8)
  private static let commentClose = Data("-->".utf8)
  private static let cdataOpen = Data("<![CDATA[".utf8)
  private static let cdataClose = Data("]]>".utf8)
  private static let instructionOpen = Data("<?".utf8)
  private static let instructionClose = Data("?>".utf8)
  private static let declarationOpen = Data("<!".utf8)
  private static let endTagOpen = Data("</".utf8)

  /// The most elements one document may carry.
  internal static let maximumElementCount = 100_000

  /// Whether the scan read the whole document.
  internal let isReadable: Bool

  private let bytes: Data
  private let spans: [Span]

  /// Scans `document` once.
  internal init(_ document: Data) {
    let copied = document.subdata(in: document.startIndex..<document.endIndex)
    var scanner = Scanner(bytes: copied)
    bytes = copied
    let scanned = try? scanner.run()
    spans = scanned ?? []
    isReadable = scanned != nil
  }

  /// The text of the element at `ordinal`, when its qualified name is
  /// `qualifiedName`.
  internal func text(ofElement ordinal: Int, named qualifiedName: String) -> String? {
    guard
      spans.indices.contains(ordinal),
      spans[ordinal].name == Data(qualifiedName.utf8),
      let end = spans[ordinal].end
    else {
      return nil
    }
    return String(data: bytes.subdata(in: spans[ordinal].start..<end), encoding: .utf8)
  }
}
