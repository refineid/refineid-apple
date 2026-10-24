// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// When the development error display expands, what it lists, when it
  /// collapses, and what it copies.
  @Suite
  @MainActor
  internal struct DevErrorModelTests {
    private enum Fixture {
      static let collapse: Duration = .milliseconds(50)
      static let poll: Duration = .milliseconds(10)
      static let patience = 100
      static let many = 5
    }

    /// Counts the arrivals a model announces.
    @MainActor
    private final class ArrivalCounter {
      var count = 0
    }

    private static func entry(_ index: Int) -> DevErrorLog.Entry {
      DevErrorLog.Entry(
        identifier: UUID(),
        date: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
        source: .app,
        message: "error \(index)",
        occurrences: 1)
    }

    private static func wait(until condition: () -> Bool) async throws {
      for _ in 0..<Fixture.patience where !condition() {
        try await Task.sleep(for: Fixture.poll)
      }
    }

    @Test
    internal func aNewErrorExpandsTheDisplay() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      #expect(!model.isExpanded)
      model.take([Self.entry(0)])
      #expect(model.isExpanded)
    }

    @Test
    internal func theNewestErrorComesFirstAndEveryErrorIsListed() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      let stored = (0..<Fixture.many).map(Self.entry)
      model.take(stored)
      #expect(model.entries.map(\.identifier) == stored.reversed().map(\.identifier))
    }

    @Test
    internal func theDisplayCollapsesWithoutANewError() async throws {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      model.take([Self.entry(0)])
      try await Self.wait { !model.isExpanded }
      #expect(!model.isExpanded)
      #expect(model.entries.count == 1)
    }

    @Test
    internal func collapsingByHandKeepsEveryError() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      model.take([Self.entry(0)])
      model.collapse()
      #expect(!model.isExpanded)
      #expect(model.entries.count == 1)
    }

    @Test
    internal func anErrorAlreadySeenDoesNotExpandItAgain() async throws {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      let first = Self.entry(0)
      model.take([first])
      try await Self.wait { !model.isExpanded }
      model.take([first])
      #expect(!model.isExpanded)
      model.take([first, Self.entry(1)])
      #expect(model.isExpanded)
    }

    @Test
    internal func onlyANewErrorIsAnnounced() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      let arrivals = ArrivalCounter()
      model.onArrival = { arrivals.count += 1 }
      let first = Self.entry(0)
      model.take([first])
      model.take([first])
      #expect(arrivals.count == 1)
      model.take([first, Self.entry(1)])
      let afterSecond = arrivals.count
      model.take([])
      #expect(afterSecond == 1 + 1)
      #expect(arrivals.count == afterSecond)
    }

    @Test
    internal func theTranscriptReadsOldestFirst() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      let stored = (0..<Fixture.many).map(Self.entry)
      model.take(stored)
      #expect(
        model.transcript == DevErrorLog.transcript(of: stored, timeZone: .current))
    }

    @Test
    internal func clearingEmptiesTheListAndCollapsesTheDisplay() {
      let model = DevErrorModel(collapseDelay: Fixture.collapse)
      model.take([Self.entry(0)])
      model.isListShown = true
      model.clear()
      #expect(model.entries.isEmpty)
      #expect(!model.isExpanded)
      #expect(!model.isListShown)
    }

    @Test
    internal func aTestRunRecordsNothing() {
      #expect(!DevErrorLog.isRecording)
      #expect(!DevErrorModel.isEnabled)
    }
  }
#endif
