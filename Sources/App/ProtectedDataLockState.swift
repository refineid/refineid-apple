// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import Foundation
  import UIKit

  /// The lock state iOS gives an app: locked while protected data is
  /// unavailable.
  ///
  /// A phone with no passcode always has protected data available while it
  /// is on, so it never reads locked; that is the holder's choice (RAPP
  /// v26.11.2 §8.2 item 3). iOS makes protected data unavailable some time
  /// after the screen locks, by the holder's "Require Passcode" setting, and
  /// an action that starts inside that interval is not held back: iOS offers
  /// a public app no earlier signal.
  @MainActor
  internal struct ProtectedDataLockState: CustodianLockState {
    internal var isLocked: Bool {
      !UIApplication.shared.isProtectedDataAvailable
    }

    /// Runs `changed` whenever the phone may have become unlocked: protected
    /// data came back, or the app came forward, which a locked phone does
    /// not allow.
    internal static func observeUnlock(
      _ changed: @escaping @MainActor () -> Void
    ) -> [any NSObjectProtocol] {
      [
        UIApplication.protectedDataDidBecomeAvailableNotification,
        UIApplication.didBecomeActiveNotification,
      ].map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { changed() }
        }
      }
    }
  }
#endif
