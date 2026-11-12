// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  @MainActor
  internal struct CardSetupReadLoopTests {
    private enum Reading: CaseIterable {
      case missedCard
      case connectionLost
      case ready
      case wrongCan
      case cancelled
      case storageFailed

      var retryable: Bool {
        self == .missedCard || self == .connectionLost
      }
    }

    @Test
    internal func missedCardAndLostFieldContinueTheSameOperationUntilSuccess() async {
      var readings: [Reading] = [.missedCard, .connectionLost, .missedCard, .ready]
      var pauses = [Reading]()
      var lastReading = Reading.ready
      let result = await CardSetupReadLoop.run(
        attempt: {
          lastReading = readings.removeFirst()
          return lastReading
        },
        shouldRetry: { $0.retryable },
        pause: { pauses.append(lastReading) })
      #expect(result == .ready)
      #expect(readings.isEmpty)
      #expect(pauses == [.missedCard, .connectionLost, .missedCard])
    }

    @Test(arguments: [Reading.wrongCan, .cancelled, .storageFailed])
    private func terminalOutcomeDoesNotStartAnotherField(reading: Reading) async {
      var readings: [Reading] = [reading, .ready]
      let result = await CardSetupReadLoop.run(
        attempt: { readings.removeFirst() },
        shouldRetry: { $0.retryable },
        pause: { Issue.record("A terminal outcome must not wait for another field") })
      #expect(result == reading)
      #expect(readings == [.ready])
    }

    @Test
    internal func cancellationBetweenFieldsDoesNotStartAnotherRead() async {
      var readings: [Reading] = [.missedCard, .ready]
      let result = await CardSetupReadLoop.run(
        attempt: { readings.removeFirst() },
        shouldRetry: { $0.retryable },
        pause: { throw CancellationError() })
      #expect(result == nil)
      #expect(readings == [.ready])
    }

    @Test
    internal func cancelledTaskDoesNotOpenAField() async {
      let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        return await CardSetupReadLoop.run(
          attempt: {
            Issue.record("A cancelled task must not open a field")
            return Reading.ready
          },
          shouldRetry: { $0.retryable },
          pause: { Issue.record("A cancelled task must not wait for another field") })
      }
      #expect(await task.value == nil)
    }
  }
#endif
