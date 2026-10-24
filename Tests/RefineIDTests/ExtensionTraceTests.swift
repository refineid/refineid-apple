// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import Testing

  @testable import RefineIDTestHost

  /// Exercises the trace's line and trimming rules.
  ///
  /// Only the rules are tested, not the keychain around them: a test run
  /// records nothing, and the rules are where a mistake would actually live.
  /// The mistake that matters most is cutting the wrong end -- a trace that
  /// kept the OLDEST lines would answer every question with the state from
  /// before the run being measured.
  @Suite
  internal struct ExtensionTraceTests {
    /// Separates two lines in the stored blob.
    private static let separator = "\n"

    /// A line long enough that a few hundred of them overflow the cap.
    private static let filler = String(repeating: "x", count: 100)

    /// How many lines are needed to overflow the cap several times over.
    private static let overflowingLineCount = 400

    /// `lineCount` numbered lines, oldest first.
    private static func buffer(lineCount: Int) -> String {
      (0..<lineCount)
        .map { "\($0) " + Self.filler }
        .joined(separator: Self.separator)
    }

    @Test
    internal func aTestRunNeverReachesTheKeychain() {
      #expect(!ExtensionTrace.isRecording)
      ExtensionTrace.append(Self.filler)
      #expect(ExtensionTrace.read().isEmpty)
    }

    @Test
    internal func aBufferInsideTheCapIsKeptWhole() {
      let short = Self.buffer(lineCount: 3)
      #expect(ExtensionTrace.trimmed(short) == short)
    }

    @Test
    internal func anEmptyBufferStaysEmpty() {
      #expect(ExtensionTrace.trimmed("").isEmpty)
    }

    @Test
    internal func anOverfullBufferIsCutToTheCap() {
      let overfull = Self.buffer(lineCount: Self.overflowingLineCount)
      #expect(overfull.utf8.count > ExtensionTrace.maximumBytes)
      #expect(ExtensionTrace.trimmed(overfull).utf8.count <= ExtensionTrace.maximumBytes)
    }

    @Test
    internal func theNewestLinesAreTheOnesKept() {
      let overfull = Self.buffer(lineCount: Self.overflowingLineCount)
      let kept = ExtensionTrace.trimmed(overfull)
      #expect(kept.hasSuffix("\(Self.overflowingLineCount - 1) " + Self.filler))
      #expect(!kept.hasPrefix("0 "))
    }

    @Test
    internal func aStampedLineCannotForgeAnotherLine() {
      let stamped = ExtensionTrace.stamped("first\nsecond\rthird")
      let carriesNewline = stamped.contains(where: \.isNewline)
      #expect(!carriesNewline)
      #expect(stamped.hasSuffix("first second third"))
    }

    @Test
    internal func aStampedLineIsClamped() {
      let runaway = String(repeating: "z", count: ExtensionTrace.maximumLineLength * 2)
      let stamped = ExtensionTrace.stamped(runaway)
      let body = stamped.drop { $0 != " " }.dropFirst()
      #expect(body.count == ExtensionTrace.maximumLineLength)
    }

    @Test
    internal func pendingLinesDrainOldestFirstAndOnce() {
      let pending = ExtensionTrace.Pending()
      pending.record("one")
      pending.record("two")
      #expect(pending.drain() == ["one", "two"])
      #expect(pending.drain().isEmpty)
    }

    @Test
    internal func oneUnsplittableLineIsLeftAlone() {
      // Nothing to cut on: refusing to truncate mid-line keeps the trace
      // readable rather than trading a whole line for a byte count.
      let single = String(repeating: "y", count: ExtensionTrace.maximumBytes + 1)
      #expect(ExtensionTrace.trimmed(single) == single)
    }
  }
#endif
