// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// Every NFC operation draws one meter: the operation's name on the
/// first line, a ball per step on the second; a failure turns its step
/// red and its sentence follows.
@Suite
internal struct NearFieldMeterTests {
  /// What a sheet drew, in order.
  private final class Drawing: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    var lines: [String] {
      lock.withLock { texts }
    }

    func draw(_ text: String) {
      lock.withLock { texts.append(text) }
    }
  }

  private static let failureSentence = "the card left"

  /// Seconds left in a security delay the countdown shows.
  private static let countdownSeconds = 30

  /// Longer than one countdown tick.
  private static let pastOneTick: Duration = .milliseconds(1_500)

  /// The row of `markers`, drawn as the meter draws it.
  private static func row(_ markers: [String]) -> String {
    markers.joined(separator: NearFieldMeter.markerGap)
  }

  /// The whole message for `markers` and `operation`.
  private static func message(_ markers: [String], _ operation: NearFieldOperation) -> String {
    operation.title + NearFieldMeter.lineBreak + Self.row(markers)
  }

  @Test("Each operation has its steps in the order they happen")
  internal func stepLists() {
    #expect(
      NearFieldOperation.setup.steps == [
        .found, .secureChannel, .certificate, .stored, .registered,
      ])
    for signing in [NearFieldOperation.authentication, .signature] {
      #expect(signing.steps == [.found, .secureChannel, .certificate, .credential, .signature])
    }
    #expect(NearFieldOperation.identity.steps == [.found, .secureChannel, .certificate])
    #expect(NearFieldOperation.cardStatus.steps == [.found, .secureChannel, .certificate])
    for credential in [
      NearFieldOperation.activation, .changePin1, .changePin2, .resetPin1, .resetPin2,
    ] {
      #expect(credential.steps == [.found, .secureChannel, .credential])
    }
  }

  @Test("Every operation opens with the card found and the secure channel, under a one-line name")
  internal func everyOperationOpensTheSameWay() {
    let opening: [NearFieldStep] = [.found, .secureChannel]
    for operation in NearFieldOperation.allCases {
      #expect(Array(operation.steps.prefix(opening.count)) == opening)
      #expect(!operation.title.isEmpty)
      #expect(!operation.title.contains(NearFieldMeter.lineBreak))
    }
  }

  @Test("Every read of the card carries the same name")
  internal func readsShareOneName() {
    #expect(NearFieldOperation.identity.title == NearFieldOperation.setup.title)
    #expect(NearFieldOperation.cardStatus.title == NearFieldOperation.setup.title)
  }

  @Test("The opening meter is the operation's name, then every ball white")
  internal func openingMeter() {
    let operation = NearFieldOperation.setup
    let white = Array(repeating: NearFieldMeter.waiting, count: operation.steps.count)
    #expect(NearFieldSheet.opening(operation) == Self.message(white, operation))
  }

  @Test("A step reached and every step before it are blue")
  internal func reachFillsTheRow() {
    var meter = NearFieldMeter(.authentication)
    meter.reach(.secureChannel)
    #expect(meter.states == [.done, .running, .waiting, .waiting, .waiting])
    #expect(
      meter.text
        == Self.message(
          [
            NearFieldMeter.reached, NearFieldMeter.reached,
            NearFieldMeter.waiting, NearFieldMeter.waiting, NearFieldMeter.waiting,
          ],
          .authentication))
    meter.advance()
    #expect(meter.states == [.done, .done, .running, .waiting, .waiting])
    meter.reach(.found)
    #expect(meter.states == [.done, .done, .running, .waiting, .waiting])
    meter.reach(.stored)
    #expect(meter.states == [.done, .done, .running, .waiting, .waiting])
  }

  @Test("A finished meter is every ball blue")
  internal func finishFillsEverything() {
    var meter = NearFieldMeter(.changePin1)
    meter.reach(.secureChannel)
    meter.finish()
    #expect(meter.states == [.done, .done, .done])
    #expect(
      meter.markers
        == Self.row(Array(repeating: NearFieldMeter.reached, count: meter.states.count)))
    meter.fail(at: nil)
    #expect(meter.states == [.done, .done, .done])
  }

  @Test("A failure turns its own step red and leaves later steps white")
  internal func failureAtANamedStep() {
    var meter = NearFieldMeter(.signature)
    meter.reach(.credential)
    meter.fail(at: .signature)
    #expect(meter.states == [.done, .done, .done, .done, .failed])
    #expect(
      meter.markers
        == Self.row([
          NearFieldMeter.reached, NearFieldMeter.reached, NearFieldMeter.reached,
          NearFieldMeter.reached, NearFieldMeter.failed,
        ]))
    meter.reach(.signature)
    meter.finish()
    #expect(meter.states == [.done, .done, .done, .done, .failed])
  }

  @Test("A signing operation that breaks at the certificate leaves the PIN white")
  internal func signingBrokenBeforeThePin() {
    for signing in [NearFieldOperation.authentication, .signature] {
      var meter = NearFieldMeter(signing)
      meter.reach(.secureChannel)
      meter.advance()
      meter.fail(at: .certificate)
      #expect(meter.states == [.done, .done, .failed, .waiting, .waiting])
    }
  }

  @Test("A failure at no step, or at a step the operation lacks, breaks the running step")
  internal func failureAtTheRunningStep() {
    var unnamed = NearFieldMeter(.authentication)
    unnamed.reach(.credential)
    unnamed.fail(at: nil)
    #expect(unnamed.states == [.done, .done, .done, .failed, .waiting])

    var foreign = NearFieldMeter(.changePin1)
    foreign.reach(.secureChannel)
    foreign.fail(at: .certificate)
    #expect(foreign.states == [.done, .failed, .waiting])
  }

  @Test("The recovery countdown follows the balls under the name, and ends as the meter alone")
  internal func recoveryText() {
    var meter = NearFieldMeter(.setup)
    meter.reach(.secureChannel)
    #expect(
      meter.recoveryText(remainingSeconds: Self.countdownSeconds)
        == NearFieldOperation.setup.title + NearFieldMeter.lineBreak + meter.markers
        + NearFieldMeter.textGap + "\(Self.countdownSeconds)s")
    #expect(meter.recoveryText(remainingSeconds: .zero) == meter.text)
  }

  @Test("A stopped countdown draws nothing after the next change")
  internal func stoppedCountdownStaysQuiet() async throws {
    let drawing = Drawing()
    let sheet = NearFieldSheet(.setup) { text in drawing.draw(text) }
    sheet.reach(.secureChannel)
    sheet.startRecovery()
    #expect(
      drawing.lines.last
        == sheet.current.recoveryText(remainingSeconds: NearFieldSheet.defaultRecoverySeconds))
    sheet.stopRecovery()
    sheet.reach(.certificate)
    try await Task.sleep(for: Self.pastOneTick)
    #expect(drawing.lines.last == sheet.current.text)
  }

  @Test("The sheet redraws the meter on every change, and the sentence after a failure")
  internal func sheetDrawsEveryChange() {
    let drawing = Drawing()
    let sheet = NearFieldSheet(.resetPin2) { text in drawing.draw(text) }
    sheet.reach(.secureChannel)
    sheet.advance()
    sheet.fail(at: nil, saying: Self.failureSentence)
    var meter = NearFieldMeter(.resetPin2)
    meter.reach(.secureChannel)
    let found = meter.text
    meter.advance()
    let working = meter.text
    meter.fail(at: nil)
    #expect(drawing.lines == [found, working, meter.text, Self.failureSentence])
    #expect(sheet.current == meter)
  }
}
