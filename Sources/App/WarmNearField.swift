// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Keeps the phone's near field warm between card operations: the system
/// slot, the card session in it and its PACE channel stay open after an
/// operation for as long as the platform keeps the slot, so the next
/// operation, from any session, runs on the open channel with no new
/// field, no new tap and no new PACE.
///
/// The platform decides how long a field lives. It takes an idle slot
/// away six to eight seconds after the last exchange, and ends a field
/// that is kept busy some twenty seconds after it was given; after any
/// ending, the reader refuses a new slot for eight to eleven seconds. The
/// warm field therefore sends one harmless command on the channel whenever
/// it has been idle for ``CardSessionHold/nearFieldKeepAliveSeconds``,
/// looks at the slot every ``CardSessionHold/nearFieldLookInterval``, and
/// ends the moment the slot is gone, so the reader's pause runs while
/// nothing is asked of the card. It also ends when the hold's session
/// limit passes, when an operation or a keep-alive goes unanswered, and
/// when its owner closes it.
///
/// Every operation, every look and every close runs on one chain, so a
/// keep-alive never interleaves with an operation, and an operation that
/// arrives while a keep-alive is in flight waits for the card's answer.
/// The field keeps no belief about the card's security status: each
/// operation verifies its PIN itself. What the field keeps is which retry
/// counters it has read and which digits the card refused, both forgotten
/// with the channel.
internal actor WarmNearField<Field: NearField> {
  /// Opens a field, given the message the sheet shows while the holder
  /// looks for the spot on the phone.
  private let open: @Sendable (String) async throws -> Field

  /// Reads the monotonic clock in milliseconds.
  private let clock: @Sendable () -> Int64

  /// Waits for the next look at the field.
  ///
  /// False once the wait was cancelled; nil when the owner looks itself.
  private let pace: (@Sendable () async -> Bool)?

  /// Hears what the field does.
  private let report: @Sendable (NearFieldEvent) -> Void

  /// Every operation, look and close runs on this chain.
  private let chain = SerialChain()

  /// Which counters this field read and which digits the card refused.
  private let credentials = CredentialSessionBox()

  private var hold = CardSessionHold(
    sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds,
    idleLimitSeconds: nil)

  /// The field held now.
  private var field: Field?

  /// The channel prepared in ``field``.
  private var channel: Field.Channel?

  /// Counts the fields opened, so a look meant for an ended field touches
  /// no later one.
  private var generation = 0

  /// When the card last answered on the field.
  private var lastExchangeMs: Int64 = 0

  /// The looks at the field held now.
  private var watch: Task<Void, Never>?

  /// Whether a field with the card in it is open now, so an operation
  /// runs on it without a new field.
  internal var isWarm: Bool {
    field?.holdsValidCard == true
  }

  /// A warm field that opens fields with `open`, reads `clock`, waits
  /// between looks with `pace` and tells `report` what it does.
  internal init(
    open: @escaping @Sendable (String) async throws -> Field,
    clock: @escaping @Sendable () -> Int64,
    pace: (@Sendable () async -> Bool)?,
    report: @escaping @Sendable (NearFieldEvent) -> Void
  ) {
    self.open = open
    self.clock = clock
    self.pace = pace
    self.report = report
  }

  /// Runs `body` on a worker thread: card commands block until the card
  /// answers.
  private static func offActor<Value: Sendable>(
    _ body: @escaping @Sendable () -> Value
  ) async -> Value {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: body())
      }
    }
  }

  /// Runs `work` on the field's channel, opening a field and preparing
  /// its channel with `cardAccessNumber` first when none is held; the
  /// sheet draws the meter of `operation`.
  ///
  /// Between operations the sheet keeps the meter of the last one: all
  /// steps done, or the failure's sentence.
  ///
  /// Nil when no field opened, the channel could not be prepared, or the
  /// field aged before the operation could start.
  internal func execute<Outcome: NearFieldOutcome>(
    cardAccessNumber: String,
    operation: NearFieldOperation,
    _ work: @escaping @Sendable (Field.Channel, CredentialSessionBox) -> Outcome
  ) async -> Outcome? {
    await chain.run {
      await self.run(cardAccessNumber: cardAccessNumber, operation: operation, work)
    }
  }

  /// Looks at the field once, after any operation under way.
  ///
  /// Ends the field when its slot is gone or its session aged, and keeps
  /// its channel up with one harmless command when it has been idle for
  /// ``CardSessionHold/nearFieldKeepAliveSeconds``. False once no field is
  /// held.
  internal func look() async -> Bool {
    await look(generation: generation)
  }

  /// Ends the field for `ending` once the operation under way has
  /// finished.
  internal func close(_ ending: CardSessionHold.Ending) async {
    await chain.run {
      await self.release(ending)
    }
  }

  private func look(generation fieldGeneration: Int) async -> Bool {
    await chain.run {
      await self.lookNow(generation: fieldGeneration)
    }
  }

  private func run<Outcome: NearFieldOutcome>(
    cardAccessNumber: String,
    operation: NearFieldOperation,
    _ work: @escaping @Sendable (Field.Channel, CredentialSessionBox) -> Outcome
  ) async -> Outcome? {
    // A field too old for another operation ends here, so the request
    // opens a fresh one instead of meeting the platform's end mid-command.
    if case .end(let ending) = hold.tick(nowMs: clock()) {
      release(ending)
    }
    guard let current = await warmField(opening: NearFieldSheet.opening(operation)) else {
      return nil
    }
    let sheet = NearFieldSheet(operation) { text in current.show(text) }
    sheet.reach(.secureChannel)
    report(.operationStarted)
    let outcome = await perform(work, in: current, cardAccessNumber: cardAccessNumber, sheet: sheet)
    let succeeded = outcome?.isResult == true
    if succeeded {
      sheet.finish()
    } else {
      sheet.fail(at: outcome?.failedStep, saying: NearFieldMeter.cardNotRead)
    }
    report(.operationFinished(succeeded: succeeded))
    if let outcome {
      settle(outcome)
    }
    return outcome
  }

  /// The field held now when its card is still in it; otherwise a new one.
  private func warmField(opening: String) async -> Field? {
    if let field {
      if field.holdsValidCard {
        report(.reused)
        return field
      }
      release(.cardLeft)
    }
    // The platform's limit on the field runs from the request, before the
    // card is even in the field, so the hold's clock starts here.
    let openedAtMs = clock()
    let opened: Field
    do {
      opened = try await open(opening)
    } catch {
      report(.notOpened(error))
      return nil
    }
    field = opened
    generation += 1
    hold.sessionOpened(nowMs: openedAtMs)
    credentials.mutate { $0.sessionEnded() }
    lastExchangeMs = clock()
    report(.opened)
    startWatch()
    return opened
  }

  private func perform<Outcome: NearFieldOutcome>(
    _ work: @escaping @Sendable (Field.Channel, CredentialSessionBox) -> Outcome,
    in current: Field,
    cardAccessNumber: String,
    sheet: NearFieldSheet
  ) async -> Outcome? {
    guard
      let prepared = await preparedChannel(in: current, cardAccessNumber: cardAccessNumber)
    else {
      sheet.fail(at: .secureChannel)
      release(.channelUnprepared)
      return nil
    }
    sheet.advance()
    // The field may have aged while the channel was prepared: it ends,
    // rather than run the operation on a field the platform is about to
    // end.
    if case .end(let ending) = hold.startsOperation(nowMs: clock()) {
      release(ending)
      return nil
    }
    let box = credentials
    let outcome = await Self.offActor { work(prepared, box) }
    lastExchangeMs = clock()
    return outcome
  }

  /// The channel held in `current` when the hold lets it be reused;
  /// otherwise a fresh one, opened and prepared with PACE.
  private func preparedChannel(
    in current: Field,
    cardAccessNumber: String
  ) async -> Field.Channel? {
    if let channel, hold.reusesChannel { return channel }
    if let channel {
      current.endChannel(channel)
    }
    channel = nil
    guard let prepared = await current.prepareChannel(cardAccessNumber: cardAccessNumber) else {
      return nil
    }
    hold.channelPrepared()
    credentials.mutate { $0.sessionEnded() }
    channel = prepared
    lastExchangeMs = clock()
    return prepared
  }

  /// Keeps the field for the next operation, or ends it.
  private func settle(_ outcome: some NearFieldOutcome) {
    let verdict = hold.operationFinished(answered: outcome.cardAnswered, nowMs: clock())
    if case .end(let ending) = verdict {
      release(ending)
    } else if field?.holdsValidCard != true {
      release(.cardLeft)
    }
  }

  private func lookNow(generation fieldGeneration: Int) async -> Bool {
    guard let current = field, fieldGeneration == generation else { return false }
    // Only a slot that is gone means the card is: any other state can be
    // a card that still answers, and the keep-alive tells.
    if current.isMissing {
      release(.cardLeft)
      return false
    }
    if case .end(let ending) = hold.tick(nowMs: clock()) {
      release(ending)
      return false
    }
    let keepAliveMs =
      CardSessionHold.nearFieldKeepAliveSeconds * CardSessionHold.millisecondsPerSecond
    guard let channel, hold.reusesChannel, clock() - lastExchangeMs >= keepAliveMs else {
      return true
    }
    guard await current.keepAlive(channel) else {
      release(.keepAliveUnanswered)
      return false
    }
    lastExchangeMs = clock()
    return true
  }

  /// Starts looking at the field just opened, every time `pace` lets.
  private func startWatch() {
    watch?.cancel()
    guard let pace else { return }
    let fieldGeneration = generation
    // Detached, so the looks run outside the chain body that opened the
    // field and queue on the chain like any other caller.
    watch = Task.detached { [weak self] in
      while await pace() {
        guard let self, await look(generation: fieldGeneration) else { return }
      }
    }
  }

  /// Ends the field, its channel and the looks at it, and forgets what
  /// the field learned of the credentials.
  private func release(_ ending: CardSessionHold.Ending) {
    _ = hold.end(ending)
    watch?.cancel()
    watch = nil
    guard let current = field else { return }
    if let channel {
      current.endChannel(channel)
    }
    channel = nil
    let slotState = current.stateName
    current.end()
    field = nil
    credentials.mutate { $0.sessionEnded() }
    report(.ended(ending, slotState: slotState))
  }
}
