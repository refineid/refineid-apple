// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What opens a card on an antenna, told from its first answers, before any
/// PACE and without any password.
///
/// A personal card refuses the application with `6982` until PACE with the
/// card access number printed on it. An organization card answers `6985`
/// to everything but EF.CardAccess until PACE with PIN 1 or PIN 2 (FINEID
/// S1 v4.0, organizational cards, section 2.1; observed on hardware), to
/// the select or to the reads after it. Asking costs no try of any PIN and
/// sends no password.
public enum ContactlessCardKind: Equatable, Sendable {
  /// Opens only with the PIN an operation spends.
  case organization

  /// A personal card: opens with the card access number, or answers in
  /// the clear.
  case personal

  /// Asks the card behind `operations`, which must be a plain channel.
  ///
  /// Only `6985` names an organization card; every other answer, a
  /// transport failure included, leaves the card to the path that opens a
  /// personal card, as before.
  public static func of(_ operations: CardOperations) -> Self {
    do {
      try operations.selectFineidApplication()
    } catch  where CardOperationError.refusesBeforePace(error) {
      return .organization
    } catch {
      return .personal
    }
    do {
      _ = try operations.readChipSerial()
    } catch  where CardOperationError.refusesBeforePace(error) {
      return .organization
    } catch {
      return .personal
    }
    return .personal
  }
}
