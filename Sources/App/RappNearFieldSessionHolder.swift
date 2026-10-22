// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine
  import UIKit

  /// The custodian's warm near field: one ``WarmNearField`` over the
  /// phone's own antenna, shared by every session, so consecutive remote
  /// operations pay for the field, the tap and PACE once.
  ///
  /// The field ends when the card leaves, when the platform ends it, when
  /// an operation or a keep-alive goes unanswered, at the hold's session
  /// limit, when the app goes to the background, when serving stops or
  /// the last session closes, and before a PIN prompt the system sheet
  /// would cover.
  internal actor RappNearFieldSessionHolder {
    internal struct Context: Sendable {
      internal let isRoleProbed: @Sendable (CredentialRole) -> Bool
      internal let isNegativePin: @Sendable (String) -> Bool
      internal let markRoleProbed: @Sendable (CredentialRole) -> Void
      internal let recordNegativePin: @Sendable (String, CredentialRole) -> Void
    }

    internal static let shared = RappNearFieldSessionHolder()

    /// The field, its channel and the operations over it.
    private let field = WarmNearField<LiveNearField>(
      open: { message in try await LiveNearField.open(message: message) },
      clock: { Int64(clamping: RappPlatformClock().monotonicMilliseconds()) },
      pace: {
        try? await Task.sleep(for: CardSessionHold.nearFieldLookInterval)
        return !Task.isCancelled
      },
      report: { event in RappNearFieldSessionHolder.report(event) }
    )

    /// The background observation, held for the actor's lifetime.
    private var backgroundObserver: (any NSObjectProtocol)?

    /// Whether a field with the card in it is open now.
    internal var isWarm: Bool {
      get async { await field.isWarm }
    }

    private init() {
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: nil
      ) { _ in
        Task { await RappNearFieldSessionHolder.shared.closeSession(.appBackgrounded) }
      }
    }

    /// Runs `operation` on the warm field, opening one with the sheet
    /// saying `message` when none is held.
    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      await field.execute(cardAccessNumber: cardAccessNumber, message: message) { held, box in
        operation(held.operations, Context.live(on: box))
      }
    }

    /// Ends the field for `ending` once the operation under way has
    /// finished.
    internal func closeSession(_ ending: CardSessionHold.Ending) async {
      await field.close(ending)
    }
  }
#endif
