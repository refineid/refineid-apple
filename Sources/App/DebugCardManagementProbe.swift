// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation

  /// Live reader/NFC proof that never retains or prints a credential.
  internal enum DebugCardManagementProbe {
    private struct Configuration {
      let transport: CardMaintenance.Transport
      let pin1: String
      let pin2: String
      let temporaryPin1: String
      let temporaryPin2: String
      let can: String?
    }

    private static let pin1Key = "REFINEID_MANAGEMENT_PIN1"
    private static let pin2Key = "REFINEID_MANAGEMENT_PIN2"
    private static let temporaryPin1Key = "REFINEID_MANAGEMENT_TEMP_PIN1"
    private static let temporaryPin2Key = "REFINEID_MANAGEMENT_TEMP_PIN2"
    private static let canKey = "REFINEID_MANAGEMENT_CAN"

    internal static func run() async -> Bool {
      guard let configuration = configuration() else {
        DebugConsole.emit("management probe: transport and PIN environment are required")
        return false
      }
      DebugConsole.emit(
        "=== card management probe (\(configuration.transport.rawValue)) ==="
      )
      guard
        let initial = await CardMaintenance.snapshot(
          transport: configuration.transport,
          cardAccessNumber: configuration.can
        )
      else {
        DebugConsole.emit("initial card read: failed")
        return false
      }
      DebugConsole.emit("initial card read: succeeded")
      if let needs = initial.activationNeeds {
        DebugConsole.emit(
          "activation needed: PIN 1 \(needs.pin1), PIN 2 \(needs.pin2)"
        )
      } else {
        DebugConsole.emit("activation classification: unavailable")
        await diagnoseActivationClassification(
          transport: configuration.transport,
          can: configuration.can
        )
      }
      guard
        await changeAndRestorePin1(
          current: configuration.pin1,
          temporary: configuration.temporaryPin1,
          transport: configuration.transport,
          can: configuration.can
        )
      else {
        return false
      }
      guard
        await changeAndRestorePin2(
          current: configuration.pin2,
          temporary: configuration.temporaryPin2,
          transport: configuration.transport,
          can: configuration.can
        )
      else {
        return false
      }
      DebugConsole.emit("=== card management probe complete ===")
      return true
    }

    private static func configuration() -> Configuration? {
      guard
        let transport = selectedTransport(),
        let pin1 = environment(pin1Key),
        let pin2 = environment(pin2Key),
        let temporaryPin1 = environment(temporaryPin1Key),
        let temporaryPin2 = environment(temporaryPin2Key)
      else {
        return nil
      }
      return Configuration(
        transport: transport,
        pin1: pin1,
        pin2: pin2,
        temporaryPin1: temporaryPin1,
        temporaryPin2: temporaryPin2,
        can: environment(canKey)
      )
    }

    /// The diagnosis reports its own failures in its lines; the meter
    /// finishes whenever the card answered.
    private static func failedStep(of _: [String]) -> NearFieldStep? {
      nil
    }

    private static func diagnoseActivationClassification(
      transport: CardMaintenance.Transport,
      can: String?
    ) async {
      let lines = await CardMaintenance.onCard(
        transport: transport,
        opener: .cardAccessNumber(can),
        operation: .cardStatus,
        failedStep: Self.failedStep(of:)
      ) { operations -> [String] in
        do {
          let certificate = try operations.readCertificate(.authentication)
          let facts = CertificateFacts(der: certificate)
          let activation = operations.activationClassification(
            authenticationCertificate: certificate
          )
          return [
            "activation certificate read: \(certificate.count) bytes",
            "activation certificate DER parse: \(facts == nil ? "failed" : "succeeded")",
            "activation classification: \(activation.map { String(describing: $0) } ?? "none")",
          ]
        } catch {
          return ["activation certificate read: failed (\(type(of: error)))"]
        }
      }
      for line in lines ?? ["activation diagnostic session: failed"] {
        DebugConsole.emit(line)
      }
    }

    private static func changeAndRestorePin1(
      current: String,
      temporary: String,
      transport: CardMaintenance.Transport,
      can: String?
    ) async -> Bool {
      let changed = await CardMaintenance.changePin1(
        current: current,
        new: temporary,
        transport: transport,
        cardAccessNumber: can
      )
      DebugConsole.emit("PIN 1 change: \(name(changed.outcome))")
      guard changed.outcome == .success else { return false }
      let restored = await CardMaintenance.changePin1(
        current: temporary,
        new: current,
        transport: transport,
        cardAccessNumber: can
      )
      DebugConsole.emit("PIN 1 restore: \(name(restored.outcome))")
      return restored.outcome == .success
    }

    private static func changeAndRestorePin2(
      current: String,
      temporary: String,
      transport: CardMaintenance.Transport,
      can: String?
    ) async -> Bool {
      let changed = await CardMaintenance.changePin2(
        current: current,
        new: temporary,
        transport: transport,
        cardAccessNumber: can
      )
      DebugConsole.emit("PIN 2 change: \(name(changed.outcome))")
      guard changed.outcome == .success else { return false }
      let restored = await CardMaintenance.changePin2(
        current: temporary,
        new: current,
        transport: transport,
        cardAccessNumber: can
      )
      DebugConsole.emit("PIN 2 restore: \(name(restored.outcome))")
      return restored.outcome == .success
    }

    private static func selectedTransport() -> CardMaintenance.Transport? {
      let arguments = ProcessInfo.processInfo.arguments
      guard
        let flag = arguments.firstIndex(of: DebugLaunchMode.managementProbe.rawValue),
        arguments.index(after: flag) < arguments.endIndex
      else {
        return nil
      }
      return CardMaintenance.Transport(
        rawValue: arguments[arguments.index(after: flag)]
      )
    }

    private static func environment(_ name: String) -> String? {
      guard
        let value = ProcessInfo.processInfo.environment[name],
        !value.isEmpty,
        value.allSatisfy(\.isNumber)
      else {
        return nil
      }
      return value
    }

    private static func name(_ outcome: CardMaintenance.Outcome) -> String {
      switch outcome {
      case .success:
        "succeeded"

      case .alreadyActivated:
        "already activated"

      case .failed:
        "failed"

      case .floorRefused:
        "refused by retry floor"

      case .invalidated:
        "invalidated"

      case .invalidEntry:
        "invalid local entry"

      case .noCard:
        "no card"

      case .pinBlocked:
        "blocked"

      case .rejected(let remaining):
        "rejected with \(remaining.attemptsRemaining) attempts remaining"
      }
    }
  }

#endif
