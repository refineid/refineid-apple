// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CryptoTokenKit
  import Foundation
  import Testing

  @testable import RefineID

  /// The development error log's ring and the names it gives errors.
  ///
  /// Only the rules are tested, not the keychain around them: a test run
  /// records nothing, so a test's failures never reach a developer's display.
  @Suite
  internal struct DevErrorLogTests {
    /// A case a probe error carries.
    internal enum Leaf {
      case leaf
    }

    /// Errors shaped like the ones the display names.
    internal enum Probe: Error {
      case bare
      case counted(remaining: Int)
      case listed(Leaf, Leaf)
      case texted(String)
      case wrapped(Leaf)
    }

    /// A case only this file can name, which describes itself with an
    /// unknown context in place of its scope.
    private enum Hidden {
      case concealed
    }

    /// An error carrying a case only this file can name.
    private enum HiddenProbe: Error {
      case wrapped(Hidden)
    }

    private enum Fixture {
      /// Entries past the capacity, so the oldest have to go.
      static let overflow = 3
      /// A count a payload carries, which must never be shown.
      static let remaining = 2
      /// A bridged error's code.
      static let code = 7
      static let domain = "Example"
      static let secret = "holder text"
      static let message = "dial refused"
      /// One error reported twice in a row.
      static let repeated = 2
      /// The zone a line's time is written in.
      static let zone = TimeZone(secondsFromGMT: 0) ?? .current
    }

    private static func entry(
      _ index: Int,
      message: String,
      source: DevErrorLog.Source
    ) -> DevErrorLog.Entry {
      DevErrorLog.Entry(
        identifier: UUID(),
        date: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
        source: source,
        message: message,
        occurrences: 1)
    }

    private static func entry(_ index: Int) -> DevErrorLog.Entry {
      Self.entry(index, message: "error \(index)", source: .app)
    }

    private static func filled(count: Int) -> [DevErrorLog.Entry] {
      (0..<count).reduce(into: []) { entries, index in
        entries = DevErrorLog.appending(Self.entry(index), to: entries)
      }
    }

    @Test
    internal func entriesKeepTheirOrderOldestFirst() {
      let first = Self.entry(0)
      let second = Self.entry(1)
      let entries = DevErrorLog.appending(second, to: [first])
      #expect(entries == [first, second])
    }

    @Test
    internal func theRingKeepsOnlyTheNewestEntries() {
      let total = DevErrorLog.capacity + Fixture.overflow
      let entries = Self.filled(count: total)
      #expect(entries.count == DevErrorLog.capacity)
      #expect(entries.first?.message == "error \(Fixture.overflow)")
      #expect(entries.last?.message == "error \(total - 1)")
    }

    @Test
    internal func anErrorRepeatedStraightAfterItselfIsCounted() {
      let first = Self.entry(0, message: Fixture.message, source: .app)
      let again = Self.entry(1, message: Fixture.message, source: .app)
      let entries = DevErrorLog.appending(again, to: [first])
      #expect(entries.count == 1)
      #expect(entries.first?.identifier == again.identifier)
      #expect(entries.first?.occurrences == Fixture.repeated)
    }

    @Test
    internal func theSameTextFromAnotherProcessIsItsOwnEntry() {
      let first = Self.entry(0, message: Fixture.message, source: .app)
      let other = Self.entry(1, message: Fixture.message, source: .rappTokenExtension)
      #expect(DevErrorLog.appending(other, to: [first]) == [first, other])
    }

    @Test
    internal func aLineSaysWhenFromWhereAndWhat() {
      let entry = Self.entry(0, message: Fixture.message, source: .rappTokenExtension)
      let time = entry.date.ISO8601Format(.init(timeZone: Fixture.zone))
      #expect(
        DevErrorLog.line(for: entry, timeZone: Fixture.zone)
          == "\(time) rapp-token \(Fixture.message)")
    }

    @Test
    internal func aLineCarriesTheDayAndTheZone() {
      let line = DevErrorLog.line(for: Self.entry(0), timeZone: Fixture.zone)
      let stamp = line.prefix { $0 != " " }
      #expect(stamp.contains("T"))
      #expect(stamp.hasSuffix("Z"))
    }

    @Test
    internal func aRepeatedErrorSaysHowOften() {
      let first = Self.entry(0, message: Fixture.message, source: .app)
      let again = Self.entry(1, message: Fixture.message, source: .app)
      let counted = DevErrorLog.appending(again, to: [first])
      #expect(counted.first?.text == "\(Fixture.message) (x\(Fixture.repeated))")
      #expect(first.text == Fixture.message)
    }

    @Test
    internal func aTranscriptIsOneLinePerEntryInTheOrderGiven() {
      let entries = (0..<Fixture.overflow).map(Self.entry)
      let lines = entries.map { DevErrorLog.line(for: $0, timeZone: Fixture.zone) }
      let transcript = DevErrorLog.transcript(of: entries, timeZone: Fixture.zone)
      #expect(transcript.components(separatedBy: "\n") == lines)
    }

    @Test
    internal func aMessageIsKeptOnOneLine() {
      #expect(DevErrorLog.sanitized("first\nsecond\rthird\tfourth") == "first second third fourth")
    }

    @Test
    internal func aLongMessageIsCut() {
      let long = String(repeating: "x", count: DevErrorLog.maximumMessageLength + Fixture.overflow)
      #expect(DevErrorLog.sanitized(long).count == DevErrorLog.maximumMessageLength)
    }

    @Test
    internal func aBareCaseIsNamed() {
      #expect(DevErrorLog.reason(Probe.bare) == "bare")
    }

    @Test
    internal func aCasePayloadIsNamedToo() {
      #expect(DevErrorLog.reason(Probe.wrapped(.leaf)) == "wrapped(leaf)")
    }

    @Test
    internal func aPrivateCasePayloadIsNamedWithoutItsContext() {
      #expect(DevErrorLog.reason(HiddenProbe.wrapped(.concealed)) == "wrapped(concealed)")
    }

    @Test
    internal func countsListsAndTextNeverPass() {
      #expect(DevErrorLog.reason(Probe.counted(remaining: Fixture.remaining)) == "counted")
      #expect(DevErrorLog.reason(Probe.listed(.leaf, .leaf)) == "listed")
      #expect(DevErrorLog.reason(Probe.texted(Fixture.secret)) == "texted")
    }

    @Test
    internal func aValueThatIsNoCaseIsNamedByItsType() {
      #expect(DevErrorLog.caseName(of: Fixture.secret) == "String")
    }

    @Test
    internal func aTokenErrorIsNamedByItsCode() {
      #expect(DevErrorLog.reason(TKError(.communicationError)) == "TKError communicationError")
    }

    @Test
    internal func aBridgedErrorIsNamedByDomainAndCode() {
      let error = NSError(domain: Fixture.domain, code: Fixture.code)
      #expect(DevErrorLog.reason(error) == "\(Fixture.domain) \(Fixture.code)")
    }
  }
#endif
