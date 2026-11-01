// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Which citizen-card PINs still carry their factory activation state.
public struct CardActivationNeeds: Equatable, Sendable {
  /// Whether PIN1 still awaits its first holder value.
  public let pin1: Bool

  /// Whether PIN2 still awaits its first holder value.
  public let pin2: Bool

  /// Whether the card still has any activation work left.
  public var any: Bool { pin1 || pin2 }

  /// Records the independent state of both PINs.
  public init(pin1: Bool, pin2: Bool) {
    self.pin1 = pin1
    self.pin2 = pin2
  }
}

extension CardOperations {
  /// Reads both PINs' activation state without changing either counter.
  public func activationNeeds(scheme: ActivationScheme) -> CardActivationNeeds {
    CardActivationNeeds(
      pin1: pinAwaitsActivation(scheme: scheme, role: .pin1),
      pin2: pinAwaitsActivation(scheme: scheme, role: .pin2)
    )
  }

  /// Reads one PIN through the scheme-specific, counter-safe preflight.
  private func pinAwaitsActivation(
    scheme: ActivationScheme,
    role: CredentialRole
  ) -> Bool {
    let probe = try? probeRetryCounter(role: role)
    let record = (try? readPinChangeRecord(role: role)) ?? .unreadable
    return ActivationPreflight.evaluate(
      scheme: scheme,
      probe: probe,
      changeRecord: record
    ) == .ready
  }
}
