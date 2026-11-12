// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The credential policy selected for a contactless card.
///
/// Personal cards open with CAN; organization cards open with the PIN
/// an operation spends (FINEID S1 v4.0, organizational cards, section 2.1).
public enum ContactlessCardKind: Equatable, Sendable {
  /// PACE uses the operation's PIN.
  case organization
  /// PACE uses the printed CAN.
  case personal

  /// Selects only the matching identity, without reading the other store.
  public func select<Value>(personal: () -> Value?, organization: () -> Value?) -> Value? {
    switch self {
    case .personal:
      personal()
    case .organization:
      organization()
    }
  }
}
