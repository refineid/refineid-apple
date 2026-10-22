// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import Foundation
  import Testing

  @testable import RefineID

  /// When the development error strip shows, what it lists, and when it
  /// fades.
  @Suite
  @MainActor
  internal struct DevErrorStripModelTests {
    private enum Fixture {
      static let fade: Duration = .milliseconds(50)
      static let poll: Duration = .milliseconds(10)
      static let patience = 100
      /// More errors than the strip lists.
      static let many = DevErrorStripModel.stripLineCount + 2
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
    internal func aNewErrorShowsTheStrip() {
      let model = DevErrorStripModel(fadeDelay: Fixture.fade)
      #expect(!model.isStripShown)
      model.take([Self.entry(0)])
      #expect(model.isStripShown)
    }

    @Test
    internal func theNewestErrorComesFirstAndTheStripListsAFew() {
      let model = DevErrorStripModel(fadeDelay: Fixture.fade)
      let stored = (0..<Fixture.many).map(Self.entry)
      model.take(stored)
      #expect(model.entries.map(\.identifier) == stored.reversed().map(\.identifier))
      #expect(model.stripEntries.count == DevErrorStripModel.stripLineCount)
      #expect(model.stripEntries.first?.identifier == stored.last?.identifier)
    }

    @Test
    internal func theStripFadesWithoutANewError() async throws {
      let model = DevErrorStripModel(fadeDelay: Fixture.fade)
      model.take([Self.entry(0)])
      try await Self.wait { !model.isStripShown }
      #expect(!model.isStripShown)
      #expect(model.entries.count == 1)
    }

    @Test
    internal func anErrorAlreadyShownDoesNotShowItAgain() async throws {
      let model = DevErrorStripModel(fadeDelay: Fixture.fade)
      let first = Self.entry(0)
      model.take([first])
      try await Self.wait { !model.isStripShown }
      model.take([first])
      #expect(!model.isStripShown)
      model.take([first, Self.entry(1)])
      #expect(model.isStripShown)
    }

    @Test
    internal func clearingEmptiesTheListAndHidesTheStrip() {
      let model = DevErrorStripModel(fadeDelay: Fixture.fade)
      model.take([Self.entry(0)])
      model.isListShown = true
      model.clear()
      #expect(model.entries.isEmpty)
      #expect(!model.isStripShown)
      #expect(!model.isListShown)
    }

    @Test
    internal func aTestRunRecordsNothing() {
      #expect(!DevErrorLog.isRecording)
      #expect(!DevErrorStripModel.isEnabled)
    }
  }
#endif
