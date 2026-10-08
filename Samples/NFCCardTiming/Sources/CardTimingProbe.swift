// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CryptoTokenKit
  import Foundation
  import UIKit

  /// Times a contactless card's PACE computations in an NFC field this
  /// app holds through CryptoTokenKit.
  ///
  /// One run opens the system NFC slot, waits for a card, takes its
  /// session, sends the commands in ``PaceTimingCommand/sequence`` and
  /// records what the card took to answer each, then ends the field.
  @MainActor
  internal final class CardTimingProbe: ObservableObject {
    // MARK: Nested Types

    internal struct Exchange: Sendable {
      internal let identifier = UUID()
      internal let name: String
      internal let statusWord: String
      internal let milliseconds: Double
    }

    internal struct Run: Sendable {
      internal let identifier = UUID()
      internal let started: Date
      internal let cardArrivalMilliseconds: Double
      internal let exchanges: [Exchange]
      internal let fieldMilliseconds: Double
      internal let outcome: String
    }

    // MARK: Static Properties

    internal static let holdMessage = "Hold the card on the top back of the phone."

    /// How long a run waits for a card after the sheet appears.
    private static let arrivalBudgetSeconds = 20
    private static let arrivalPollMilliseconds = 50
    private static let arrivalBudget: Duration = .seconds(arrivalBudgetSeconds)
    private static let arrivalPoll: Duration = .milliseconds(arrivalPollMilliseconds)
    private static let millisecondsPerSecond: Double = 1_000
    private static let attosecondsPerSecond: Double = 1e18

    /// What this phone is, for the report: model identifier and OS build.
    internal static let device: String = {
      var systemInfo = utsname()
      uname(&systemInfo)
      let model = withUnsafeBytes(of: &systemInfo.machine) { raw in
        String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? UIDevice.current.model
      }
      return "\(model) iOS \(UIDevice.current.systemVersion)"
    }()

    // MARK: Properties

    @Published internal private(set) var runs: [Run] = []
    @Published internal private(set) var isRunning = false

    // MARK: Computed Properties

    /// Every run as text, newest last, ready to paste into a report.
    internal var report: String {
      var lines = ["NFC card timing, \(Self.device)"]
      for run in runs {
        lines.append("")
        lines.append(
          "run \(run.started.formatted(date: .omitted, time: .standard)): "
            + "card after \(Self.text(run.cardArrivalMilliseconds)) ms, "
            + "field \(Self.text(run.fieldMilliseconds)) ms, \(run.outcome)")
        for exchange in run.exchanges {
          lines.append(
            "  \(exchange.name): \(Self.text(exchange.milliseconds)) ms, SW \(exchange.statusWord)")
        }
      }
      return lines.joined(separator: "\n")
    }

    // MARK: Functions

    private static func measure() async -> Run {
      let started = Date()
      let opened = ContinuousClock.now
      func finished(
        arrival: Double, exchanges: [Exchange], outcome: String
      ) -> Run {
        Run(
          started: started,
          cardArrivalMilliseconds: arrival,
          exchanges: exchanges,
          fieldMilliseconds: milliseconds(since: opened),
          outcome: outcome)
      }
      guard let manager = TKSmartCardSlotManager.default else {
        return finished(arrival: 0, exchanges: [], outcome: "no slot manager")
      }
      let session: TKSmartCardSlotNFCSession
      do {
        session = try await openSlot(manager)
      } catch {
        return finished(arrival: 0, exchanges: [], outcome: "slot refused: \(error)")
      }
      defer { session.end() }
      guard let name = session.slotName, let slot = manager.slotNamed(name) else {
        return finished(arrival: 0, exchanges: [], outcome: "slot not listed")
      }
      guard let card = await waitForCard(in: slot, named: name, from: manager) else {
        return finished(arrival: 0, exchanges: [], outcome: "card never arrived")
      }
      let arrival = milliseconds(since: opened)
      do {
        try await beginSession(card)
      } catch {
        return finished(arrival: arrival, exchanges: [], outcome: "session refused: \(error)")
      }
      let (exchanges, outcome) = await exchange(with: card, in: slot)
      card.endSession()
      return finished(arrival: arrival, exchanges: exchanges, outcome: outcome)
    }

    /// Sends the sequence and times each answer, stopping at the first
    /// command the field does not carry.
    private static func exchange(
      with card: TKSmartCard, in slot: TKSmartCardSlot
    ) async -> ([Exchange], String) {
      var exchanges: [Exchange] = []
      for command in PaceTimingCommand.sequence {
        let sent = ContinuousClock.now
        do {
          let response = try await transmit(card, command.apdu)
          exchanges.append(
            Exchange(
              name: command.name,
              statusWord: statusWord(of: response),
              milliseconds: milliseconds(since: sent)))
        } catch {
          exchanges.append(
            Exchange(
              name: command.name,
              statusWord: "error \((error as NSError).code)",
              milliseconds: milliseconds(since: sent)))
          return (exchanges, "field lost during \(command.name), slot state \(slot.state.rawValue)")
        }
      }
      return (exchanges, "completed")
    }

    private static func openSlot(
      _ manager: TKSmartCardSlotManager
    ) async throws -> TKSmartCardSlotNFCSession {
      try await withCheckedThrowingContinuation { continuation in
        manager.createNFCSlot(message: holdMessage) { session, error in
          if let session {
            continuation.resume(returning: session)
          } else {
            continuation.resume(throwing: error ?? TKError(.objectNotFound))
          }
        }
      }
    }

    /// Polls until the slot validates a card, or the sheet is gone, or
    /// the budget is spent.
    private static func waitForCard(
      in slot: TKSmartCardSlot, named name: String, from manager: TKSmartCardSlotManager
    ) async -> TKSmartCard? {
      let deadline = ContinuousClock.now + arrivalBudget
      while ContinuousClock.now < deadline {
        if slot.state == .validCard, let card = slot.makeSmartCard() {
          return card
        }
        if manager.slotNamed(name) == nil {
          return nil
        }
        try? await Task.sleep(for: arrivalPoll)
      }
      return nil
    }

    private static func beginSession(_ card: TKSmartCard) async throws {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        card.beginSession { began, error in
          if began {
            continuation.resume()
          } else {
            continuation.resume(throwing: error ?? TKError(.communicationError))
          }
        }
      }
    }

    private static func transmit(_ card: TKSmartCard, _ apdu: Data) async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        card.transmit(apdu) { response, error in
          if let response {
            continuation.resume(returning: response)
          } else {
            continuation.resume(throwing: error ?? TKError(.communicationError))
          }
        }
      }
    }

    private static func statusWord(of response: Data) -> String {
      response.suffix(PaceTimingValues.statusWordLength)
        .map { String(format: "%02X", $0) }
        .joined()
    }

    private static func milliseconds(since instant: ContinuousClock.Instant) -> Double {
      let elapsed = instant.duration(to: ContinuousClock.now)
      let seconds = Double(elapsed.components.seconds)
      let attoseconds = Double(elapsed.components.attoseconds) / attosecondsPerSecond
      return (seconds + attoseconds) * millisecondsPerSecond
    }

    private static func text(_ milliseconds: Double) -> String {
      String(format: "%.1f", milliseconds)
    }

    internal func run() async {
      guard !isRunning else { return }
      isRunning = true
      let run = await Self.measure()
      runs.append(run)
      isRunning = false
    }

    internal func clear() {
      runs.removeAll()
    }
  }
#endif
