// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// The warm near field keeps the field, the card session and its PACE
/// channel open between operations for as long as the platform keeps the
/// slot, and ends it when the card leaves, the platform or the hold ends
/// it, the card stops answering, or its owner closes it.
@Suite
internal struct WarmNearFieldTests {
  private typealias Fakes = WarmNearFieldFakes
  private typealias Core = WarmNearField<Fakes.Field>

  /// The platform takes an idle slot away this long after the last exchange.
  private static let platformIdleLifeMs: Int64 = 7_000

  /// The platform ends a field this long after it was given, however busy.
  private static let platformFieldLifeMs: Int64 = 20_000

  /// A field the platform never ends on its own.
  private static let endlessFieldLifeMs = Int64.max

  /// Time between two signatures of one login.
  private static let signatureGapMs: Int64 = 3_000

  /// Signatures one login asks for in a row.
  private static let burstSize = 4

  /// Operations of two computers' sessions, in the order they joined the
  /// card queue.
  private static let queuedOperations = [
    "mac first", "laptop first", "mac second", "laptop second",
  ]

  /// Time between two looks at the idle field.
  private static let lookMs =
    CardSessionHold.nearFieldLookInterval.components.seconds * CardSessionHold.millisecondsPerSecond

  /// The hold's session limit.
  private static let sessionLimitMs =
    CardSessionHold.nearFieldSessionLimitSeconds * CardSessionHold.millisecondsPerSecond

  private static let cardAccessNumber = "access number"

  /// What one signature sends: VERIFY PIN 1, then the signature.
  private static let signatureWork: [Fakes.Command] = [.verify, .sign]

  /// A warm field over `reader` that reports to `log`; the test looks
  /// itself.
  private static func field(over reader: Fakes.Reader, log: Fakes.EventLog) -> Core {
    Core(
      open: { _ in reader.open() },
      clock: { reader.clock.read() },
      pace: nil,
      report: { event in log.record(event) }
    )
  }

  /// One authentication signature in the order the executor runs it: the
  /// PIN 1 counter read once per field, VERIFY every time, then the
  /// signature.
  private static func signature(
    on card: Fakes.Card,
    credentials: CredentialSessionBox
  ) -> Fakes.Outcome {
    if !credentials.read().probedRoles.contains(.pin1) {
      guard card.send(.probe) else { return .unanswered }
      credentials.mutate { $0.markProbed(.pin1) }
    }
    guard card.verifyPin1() else { return .unanswered }
    return card.sign()
  }

  private static func sign(on core: Core) async -> Fakes.Outcome? {
    await core.execute(cardAccessNumber: Self.cardAccessNumber, operation: .authentication) {
      card, credentials in
      Self.signature(on: card, credentials: credentials)
    }
  }

  /// Lets `milliseconds` pass with a look at the field every look
  /// interval, as the field's own watch does; false once a look found no
  /// field.
  @discardableResult
  private static func idle(
    _ core: Core,
    on reader: Fakes.Reader,
    forMs milliseconds: Int64
  ) async -> Bool {
    var elapsed: Int64 = 0
    while elapsed < milliseconds {
      reader.clock.advance(byMs: Self.lookMs)
      elapsed += Self.lookMs
      guard await core.look() else { return false }
    }
    return true
  }

  @Test("A burst of signatures within the field's life uses one field, one tap and one PACE")
  internal func burstUsesOneField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    for index in 0..<Self.burstSize {
      if index > 0 {
        #expect(await Self.idle(core, on: reader, forMs: Self.signatureGapMs))
      }
      #expect(await Self.sign(on: core) == .signed)
    }
    #expect(reader.opens == 1)
    #expect(reader.card.work().filter { $0 == .pace }.count == 1)
    #expect(log.reuses == Self.burstSize - 1)
    #expect(log.endings.isEmpty)
    #expect(await core.isWarm)
  }

  @Test("VERIFY PIN 1 runs before every signature on the reused channel")
  internal func verifyBeforeEverySignature() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let core = Self.field(over: reader, log: Fakes.EventLog())
    for _ in 0..<Self.burstSize {
      #expect(await Self.sign(on: core) == .signed)
      await Self.idle(core, on: reader, forMs: Self.signatureGapMs)
    }
    let signatures = Array(repeating: Self.signatureWork, count: Self.burstSize).flatMap(\.self)
    #expect(reader.card.work() == [.pace, .probe] + signatures)
  }

  @Test("The keep-alive holds an idle field past the platform's idle limit")
  internal func keepAliveHoldsTheIdleField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let core = Self.field(over: reader, log: Fakes.EventLog())
    #expect(await Self.sign(on: core) == .signed)
    let pastIdleLifeMs = Self.platformIdleLifeMs + Self.signatureGapMs
    #expect(await Self.idle(core, on: reader, forMs: pastIdleLifeMs))
    #expect(reader.card.commands.contains(.keepAlive))
    #expect(await Self.sign(on: core) == .signed)
    #expect(reader.opens == 1)
  }

  @Test("An operation after the platform ended the field opens a new one and reads the counter")
  internal func operationAfterTheFieldEndedOpensANewOne() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    #expect(await Self.sign(on: core) == .signed)
    #expect(await Self.idle(core, on: reader, forMs: Self.platformFieldLifeMs) == false)
    #expect(log.endings == [.cardLeft])
    #expect(reader.latest?.isEnded == true)
    #expect(await core.isWarm == false)
    #expect(await Self.sign(on: core) == .signed)
    #expect(reader.opens == 2)
    #expect(reader.card.work() == [.pace, .probe, .verify, .sign, .pace, .probe, .verify, .sign])
  }

  @Test("The hold's session limit ends a field the platform would keep")
  internal func sessionLimitEndsTheField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.endlessFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    #expect(await Self.sign(on: core) == .signed)
    #expect(await Self.idle(core, on: reader, forMs: Self.sessionLimitMs) == false)
    #expect(log.endings == [.sessionAged])
    #expect(await Self.sign(on: core) == .signed)
    #expect(reader.opens == 2)
  }

  @Test("Taking the card off the phone ends the field at the next look")
  internal func cardRemovalEndsTheField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    #expect(await Self.sign(on: core) == .signed)
    reader.latest?.removeCard()
    #expect(await core.look() == false)
    #expect(log.endings == [.cardLeft])
    #expect(reader.latest?.isEnded == true)
    #expect(await core.isWarm == false)
  }

  @Test("A keep-alive or an operation the card does not answer ends the field")
  internal func unansweredCardEndsTheField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    #expect(await Self.sign(on: core) == .signed)
    reader.card.goMute()
    #expect(await Self.idle(core, on: reader, forMs: Self.signatureGapMs) == false)
    #expect(log.endings == [.keepAliveUnanswered])

    let silent = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let silentLog = Fakes.EventLog()
    let silentCore = Self.field(over: silent, log: silentLog)
    #expect(await Self.sign(on: silentCore) == .signed)
    silent.card.goMute()
    #expect(await Self.sign(on: silentCore) == .unanswered)
    #expect(silentLog.endings == [.operationUnanswered])
  }

  @Test("Its owner's close ends the field at once and the next operation opens a new one")
  internal func closeEndsTheField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let log = Fakes.EventLog()
    let core = Self.field(over: reader, log: log)
    #expect(await Self.sign(on: core) == .signed)
    await core.close(.promptShown)
    await core.close(.servingStopped)
    #expect(log.endings == [.promptShown])
    #expect(reader.latest?.isEnded == true)
    #expect(await core.isWarm == false)
    #expect(await Self.sign(on: core) == .signed)
    #expect(reader.opens == 2)
  }

  @MainActor
  @Test("Queued operations of several sessions take the card in turn on one field")
  internal func queuedOperationsShareOneField() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let core = Self.field(over: reader, log: Fakes.EventLog())
    let queue = CustodianCardQueue<String>()
    for operation in Self.queuedOperations {
      _ = queue.join(operation)
    }
    let turns = Self.queuedOperations.map { operation in
      Task { @MainActor () -> Fakes.Outcome? in
        guard await queue.turn(of: operation) else { return nil }
        let outcome = await Self.sign(on: core)
        queue.leave(operation)
        return outcome
      }
    }
    var outcomes: [Fakes.Outcome?] = []
    for turn in turns {
      outcomes.append(await turn.value)
    }
    let count = Self.queuedOperations.count
    #expect(outcomes == Array(repeating: .signed, count: count))
    #expect(reader.opens == 1)
    let signatures = Array(repeating: Self.signatureWork, count: count).flatMap(\.self)
    #expect(reader.card.work() == [.pace, .probe] + signatures)
  }

  @Test("The sheet draws each operation's meter, and a failure's sentence after it")
  internal func sheetFollowsTheOperation() async {
    let reader = Fakes.Reader(
      idleLifeMs: Self.platformIdleLifeMs, fieldLifeMs: Self.platformFieldLifeMs)
    let core = Self.field(over: reader, log: Fakes.EventLog())
    #expect(await Self.sign(on: core) == .signed)
    reader.card.goMute()
    #expect(await Self.sign(on: core) == .unanswered)
    var meter = NearFieldMeter(.authentication)
    meter.reach(.secureChannel)
    let found = meter.text
    meter.advance()
    let working = meter.text
    var finished = meter
    finished.finish()
    var broken = meter
    broken.fail(at: nil)
    #expect(
      reader.latest?.sheetLines == [
        found, working, finished.text,
        found, working, broken.text, NearFieldMeter.cardNotRead,
      ])
  }
}
