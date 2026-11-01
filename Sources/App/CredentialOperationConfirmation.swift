// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The step between filling in a management form and spending
/// something on the card.
///
/// Every task in this window costs an attempt that no software can
/// give back, and the two forms differ by a single character - which
/// is exactly how a card ends up with a new PIN 1 when its holder
/// meant PIN 2. WCAG 3.3.4 accepts reversal, checking, or
/// confirmation; nothing about a card is reversible and no entry can
/// be checked before the card sees it, so confirmation is the only
/// one of the three available here.
///
/// The centered alert names the operation once, on its affirmative action. That
/// label is explicit for assistive technology and long enough for the system to
/// stack it above Cancel without a redundant question. A pristine credential needs
/// no warning; retry guidance appears only after one or two mistakes,
/// while the shared retry floor prevents a third. Cancel is the default
/// and destroys every secret held by the form.
internal struct CredentialOperationConfirmation: ViewModifier {
  /// What the holder is about to do.
  internal enum Operation: Equatable {
    /// Replace a PIN, which the card grants only after checking the
    /// current value of that same PIN.
    case change(CredentialRole)

    /// Reset a blocked PIN, which the card grants only after checking
    /// the PUK.
    case unblock(CredentialRole)

    /// Reset PIN 1 and PIN 2 together, which the card grants only after
    /// checking the PUK, once for each.
    case unblockBoth

    /// Set both PINs from the issuance letter, which a card accepts
    /// once.
    case activate

    /// The credential the card checks before it grants the operation,
    /// and therefore the counter this costs when the entry is wrong.
    ///
    /// Activation has no single answer: which counter it spends
    /// depends on how the card was issued, and naming the wrong one
    /// would be worse than naming none.
    internal var spends: CredentialRole? {
      switch self {
      case .change(let role):
        role

      case .unblock, .unblockBoth:
        .puk

      case .activate:
        nil
      }
    }
  }

  /// The operation awaiting a decision, or nil while the form is
  /// still being filled in.
  @Binding internal var pending: Operation?

  /// The last counter reading, so the dialog can say what is left.
  internal let report: CredentialProbeReport?

  /// Runs the operation the holder confirmed.
  internal let confirm: (Operation) -> Void

  /// Rejects the operation and destroys the form's transient secrets.
  internal let reject: (Operation) -> Void

  /// The affirmative action, derived from the existing localized question so
  /// all supported languages retain their translations without duplicating keys.
  private static func actionTitle(of operation: Operation) -> String {
    let title: String =
      switch operation {
      case .change(let role):
        String(localized: "Confirm \(Self.name(of: role)) change?")

      case .unblock(let role):
        String(localized: "Confirm \(Self.name(of: role)) reset?")

      case .unblockBoth:
        String(localized: "Change both PINs?")

      case .activate:
        String(localized: "Confirm card activation?")
      }
    return title.last == "?" ? String(title.dropLast()) : title
  }

  /// Warns only after the counter has fallen to four or three.
  ///
  /// Five is pristine and needs no commentary; one and two are refused
  /// by policy.
  private static func warning(
    for operation: Operation,
    report: CredentialProbeReport?
  ) -> String? {
    let spent = operation.spends.map(Self.name) ?? ""
    let minimum = Int(RetryFloor.minimumAttemptsToProceed)
    let pristine = Int(RetryCount.pristineAllowance)
    guard
      let remaining = operation.spends.flatMap({ role in
        Self.remaining(for: role, in: report)
      }),
      remaining >= minimum,
      remaining < pristine
    else {
      return nil
    }
    switch operation {
    case .change:
      return String(
        localized: """
          A wrong current \(spent) spends one attempt. \
          \(remaining) attempts remain.
          """
      )

    case .unblock, .unblockBoth:
      return String(
        localized: """
          A wrong \(spent) spends one attempt. \(remaining) attempts remain. \
          Exhausting the \(spent) cannot be undone by software.
          """
      )

    case .activate:
      return nil
    }
  }

  /// The reported count for one credential, if the card gave one.
  private static func remaining(
    for role: CredentialRole,
    in report: CredentialProbeReport?
  ) -> Int? {
    let outcome: RetryProbeOutcome? =
      switch role {
      case .pin1:
        report?.pin1

      case .pin2:
        report?.pin2

      case .puk:
        report?.puk
      }
    guard case .remaining(let count) = outcome else { return nil }
    return Int(count.attemptsRemaining)
  }

  /// The on-screen name, written the way the card documentation
  /// writes it.
  private static func name(of role: CredentialRole) -> String {
    switch role {
    case .pin1:
      "PIN 1"

    case .pin2:
      "PIN 2"

    case .puk:
      "PUK"
    }
  }
  internal func body(content: Content) -> some View {
    content
      .alert(
        Text(verbatim: ""),
        isPresented: Binding(
          get: { pending != nil },
          // UIKit writes false before dispatching the selected alert action.
          // Clearing `pending` here invalidates `presenting:` before either
          // button closure can run. Alerts have explicit Confirm and Cancel
          // actions, and those are the sole owners of this state transition.
          set: { _ in
            // UIKit drives dismissal through explicit alert actions
          }
        ),
        presenting: pending
      ) { operation in
        Button(Self.actionTitle(of: operation)) {
          confirm(operation)
          pending = nil
        }
        .accessibilityIdentifier("managementConfirm")
        .keyboardShortcut(.defaultAction)
        Button("Cancel", role: .cancel) {
          pending = nil
          reject(operation)
        }
        .accessibilityIdentifier("managementCancel")
      } message: { operation in
        if let warning = Self.warning(for: operation, report: report) {
          Text(warning)
        }
      }
  }
}

extension View {
  /// Puts an irreversible card operation to the holder before it is
  /// sent.
  internal func confirmCredentialOperation(
    _ pending: Binding<CredentialOperationConfirmation.Operation?>,
    report: CredentialProbeReport?,
    reject: @escaping (CredentialOperationConfirmation.Operation) -> Void,
    confirm: @escaping (CredentialOperationConfirmation.Operation) -> Void
  ) -> some View {
    modifier(
      CredentialOperationConfirmation(
        pending: pending,
        report: report,
        confirm: confirm,
        reject: reject
      )
    )
  }
}
