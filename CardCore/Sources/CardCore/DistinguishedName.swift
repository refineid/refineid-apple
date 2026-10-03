// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The one human-readable name in an X.509 subject: its common name.
///
/// A FINEID citizen certificate carries the holder's identity four
/// times over: a common name of `SURNAME FORENAME <identifier>`, and
/// then that surname, forename and identifier again as attributes of
/// their own. Everything that shows a name to a person shows the
/// common name, so the reading lives here once rather than in each of
/// them.
public enum DistinguishedName {
  /// What ends one segment of a name and begins the next.
  ///
  /// Both apostrophes appear in certificates: the typewriter one and
  /// the typographic one.
  private static let segmentSeparators: Set<Character> = [
    " ", "-", "'", "\u{2019}",
  ]

  private static let minimumIdentifierLength = 6
  private static let maximumIdentifierLength = 12

  /// The holder as a person reads it: given name, then surname, each
  /// capitalised, or nil when the name states neither.
  ///
  /// Built from the separate attributes rather than by cutting up the
  /// common name. A certificate states "SURNAME FORENAME identifier"
  /// there, which is an index entry, not how anyone writes their own
  /// name - and taking it apart by looking for spaces guesses at
  /// something the certificate already says exactly.
  ///
  /// The attributes are stored in capitals, mirroring the machine
  /// readable zone's conventions, so they are recased for reading.
  /// The rule is deliberately simple and locale-independent: a
  /// segment begins after a space, a hyphen or an apostrophe, its
  /// first character is uppercased and the rest lowercased, and the
  /// separators are kept as they were. Finnish and Swedish need
  /// nothing more; only languages with locale-sensitive casing would.
  ///
  /// The apostrophe earns its place: every surname that carries one
  /// capitalises the letter after it - O'Brien, O'Neill, D'Angelo,
  /// D'Arcy. It costs the Dutch "'t Hooft", which comes out as
  /// "'T Hooft", and that is the rarer name by a wide margin.
  ///
  /// Its remaining limits are known and accepted rather than papered
  /// over: "MCCABE" becomes "Mccabe" and "VAN DER BERG" becomes "Van
  /// Der Berg". Guessing at those would misspell as many names as it
  /// fixed - a particle rule would have to know that "Van" is a
  /// particle in Dutch and a surname on its own elsewhere.
  ///
  /// The certificate is the right source for this. A card that
  /// published the holder's own spelling directly would be better
  /// still, and this card does not; the machine readable zone is
  /// worse, being transliterated - it writes Ä as AE and Ö as OE, and
  /// nothing records what the original was.
  public static func personalName(inName name: Data) -> String? {
    let given = Self.givenName(inName: name)
    let family = Self.surname(inName: name)
    let stated = [given, family].compactMap(\.self)
    guard !stated.isEmpty else { return nil }
    return stated.joined(separator: " ")
  }

  /// The separately stated given name, recased for display.
  public static func givenName(inName name: Data) -> String? {
    Self.attribute(SignOids.givenName, inName: name).map(Self.recased)
  }

  /// The separately stated surname, recased for display.
  public static func surname(inName name: Data) -> String? {
    Self.attribute(SignOids.surname, inName: name).map(Self.recased)
  }

  /// One name recased for reading.
  private static func recased(_ text: String) -> String {
    var out = ""
    var startsSegment = true
    for character in text {
      if Self.segmentSeparators.contains(character) {
        out.append(character)
        startsSegment = true
        continue
      }
      out +=
        startsSegment
        ? character.uppercased() : character.lowercased()
      startsSegment = false
    }
    return out
  }

  /// The holder's identifier, as the certificate states it.
  public static func identifier(inName name: Data) -> String? {
    Self.attribute(SignOids.serialNumber, inName: name)
  }

  /// The person line a window shows: the certificate's common name stripped
  /// of any trailing identifier, or raw surname followed by given names as stated.
  public static func holderLine(inName name: Data) -> String? {
    if let common = Self.commonName(inName: name) {
      return Self.cleanedCommonName(common)
    }
    let family = Self.attribute(SignOids.surname, inName: name)
    let given = Self.attribute(SignOids.givenName, inName: name)
    let stated = [family, given].compactMap(\.self)
    guard !stated.isEmpty else { return nil }
    return stated.joined(separator: " ")
  }

  private static func isIdentifierToken(_ token: Substring) -> Bool {
    guard token.count >= Self.minimumIdentifierLength,
      token.count <= Self.maximumIdentifierLength,
      token.contains(where: \.isNumber)
    else {
      return false
    }
    return true
  }

  /// Removes a trailing SATU / PEUIN or specimen identifier from a common name.
  private static func cleanedCommonName(_ common: String) -> String {
    let parts = common.split(separator: " ")
    guard parts.count > 1, let last = parts.last else { return common }
    if Self.isIdentifierToken(last) {
      return parts.dropLast().joined(separator: " ")
    }
    return common
  }

  /// The person line from a certificate's subject, or nil when it
  /// carries no name this app can show.
  public static func holderLine(fromCertificate der: Data) -> String? {
    guard let facts = CertificateFacts(der: der) else { return nil }
    return Self.holderLine(inName: facts.subjectName)
  }

  /// The holder's identifier (SATU / PEUIN) from a certificate's subject, or trailing identifier in common name.
  public static func identifier(fromCertificate der: Data) -> String? {
    guard let facts = CertificateFacts(der: der) else { return nil }
    if let serial = Self.identifier(inName: facts.subjectName) {
      return serial
    }
    if let common = Self.commonName(inName: facts.subjectName) {
      let parts = common.split(separator: " ")
      if parts.count > 1, let last = parts.last, Self.isIdentifierToken(last) {
        return String(last)
      }
    }
    return nil
  }

  /// The common name in a DER-encoded Name, or nil when it carries
  /// none this can read.
  ///
  /// A Name is a sequence of relative names, each a set of
  /// type-and-value pairs; the common name is the pair whose type is
  /// `id-at-commonName`. Its value is a text string in one of several
  /// ASN.1 flavours, and only the flavours that are plainly text are
  /// accepted - a name this cannot read honestly is better absent
  /// than mangled.
  public static func commonName(inName name: Data) -> String? {
    Self.attribute(SignOids.commonName, inName: name)
  }

  /// One attribute's value, found by its object identifier.
  private static func attribute(_ oid: String, inName name: Data) -> String? {
    var outer = DerReader(name)
    guard
      let sequence = outer.next(),
      sequence.tag == DerValues.tagSequence
    else {
      return nil
    }
    var relativeNames = DerReader(name, within: sequence)
    while let relativeName = relativeNames.next() {
      var pairs = DerReader(name, within: relativeName)
      while let pair = pairs.next() {
        guard
          let found = Self.value(inPair: pair, of: name, matching: oid)
        else {
          continue
        }
        return found
      }
    }
    return nil
  }

  /// The value of one type-and-value pair, when its type is the
  /// common name.
  private static func value(
    inPair pair: DerReader.Element,
    of name: Data,
    matching oid: String
  ) -> String? {
    var parts = DerReader(name, within: pair)
    guard
      let type = parts.next(),
      DerReader(name).data(of: type) == DerEncoder.objectIdentifier(oid),
      let value = parts.next(),
      Self.isTextTag(value.tag)
    else {
      return nil
    }
    let text = DerReader(name).contentData(of: value)
    return String(data: text, encoding: .utf8)
      ?? String(data: text, encoding: .isoLatin1)
  }

  /// Whether a tag introduces a string this can read as text.
  ///
  /// UTF-8, printable and IA5 strings are plain text. The wide
  /// encodings a Name may also use are not accepted: they would need
  /// their own decoding, and guessing at one produces a name that
  /// looks right and is not.
  private static func isTextTag(_ tag: UInt8) -> Bool {
    tag == DerValues.tagUtf8String
      || tag == DerValues.tagPrintableString
      || tag == DerValues.tagIa5String
  }
}
