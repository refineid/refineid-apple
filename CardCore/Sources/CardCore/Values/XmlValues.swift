// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Values of W3C XML 1.0 (Fifth Edition) the reader checks against.
internal enum XmlValues {
  /// Horizontal tab, one of the three control characters in `Char`
  /// (section 2.2 production 2).
  internal static let tabScalar: UInt32 = 0x9

  /// Line feed.
  internal static let lineFeedScalar: UInt32 = 0xA

  /// Carriage return.
  internal static let carriageReturnScalar: UInt32 = 0xD

  /// The first `Char` range above the control characters, below the
  /// surrogates.
  internal static let characterRange1: ClosedRange<UInt32> = 0x20...0xD7FF

  /// The second `Char` range, above the surrogates; U+FFFE and U+FFFF
  /// are not characters.
  internal static let characterRange2: ClosedRange<UInt32> = 0xE000...0xFFFD

  /// The supplementary-plane `Char` range.
  internal static let characterRange3: ClosedRange<UInt32> = 0x10000...0x10FFFF

  /// The byte order mark a UTF-8 document may start with (section
  /// 4.3.3).
  internal static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

  /// The first byte of a multi-byte UTF-8 sequence; a name may contain
  /// any non-ASCII character.
  internal static let firstNonAsciiByte: UInt8 = 0x80

  /// Radix of a hexadecimal character reference (section 4.1).
  internal static let hexadecimalRadix = 16

  /// Radix of a decimal character reference.
  internal static let decimalRadix = 10

  /// The parts of a `QName` with a prefix (Namespaces in XML 1.0
  /// section 4).
  internal static let qualifiedNameParts = 2
}
