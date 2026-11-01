// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension CardOperationError {
  /// Whether `error` is the card answering `6985` to a select or a read:
  /// an organization card on the contactless interface, which answers
  /// nothing but EF.CardAccess before PACE with a PIN has run (FINEID S1
  /// v4.0, organizational cards, section 2.1; observed on hardware).
  public static func refusesBeforePace(_ error: any Error) -> Bool {
    switch error {
    case Self.selectRejected(.conditionsNotSatisfied),
      Self.readFailed(.unexpectedStatus(.conditionsNotSatisfied)):
      true

    default:
      false
    }
  }
}
