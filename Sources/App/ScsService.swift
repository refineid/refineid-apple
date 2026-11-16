// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import SwiftUI

  /// Starts the local signing server only for the holder's stored
  /// opt-in, removes the localhost identity and trust on opt-out, and
  /// publishes listener errors, pending prompt status, and holder-only
  /// PIN notices.
  @MainActor
  internal final class ScsService: ObservableObject {
    internal static let shared = ScsService()

    @Published internal private(set) var isEnabled: Bool
    @Published internal private(set) var statusError: String?
    @Published internal private(set) var pendingRequestOrigin: String?
    @Published internal private(set) var holderNotice: String?

    private let controller: ScsOptInController

    private convenience init() {
      let server = ScsServer { failure in
        Task { @MainActor in
          Self.shared.setStatusError(failure)
        }
      }
      self.init(
        defaults: .standard,
        start: { server.start() },
        stop: { server.stop() },
        removeIdentity: { ScsIdentityStore.removeAll() }
      )
    }

    internal init(
      defaults: UserDefaults,
      start: @escaping () -> Void,
      stop: @escaping () -> Void,
      removeIdentity: @escaping () -> Void
    ) {
      let optIn = ScsOptInController(
        defaults: defaults,
        start: start,
        stop: stop,
        removeIdentity: removeIdentity
      )
      self.controller = optIn
      self.isEnabled = optIn.isEnabled
    }

    /// Restores an explicit opt-in without creating an identity when
    /// disabled.
    internal func restore() {
      controller.restore()
      isEnabled = controller.isEnabled
    }

    internal func setEnabled(_ enabled: Bool) {
      controller.setEnabled(enabled)
      isEnabled = controller.isEnabled
      if !enabled {
        statusError = nil
        pendingRequestOrigin = nil
        holderNotice = nil
      }
    }

    internal func setStatusError(_ error: String?) {
      statusError = error
    }

    internal func setPendingRequest(origin: String?) {
      pendingRequestOrigin =
        ScsOriginPolicy.sanitizedForDisplay(origin)
        ?? String(localized: "(no Origin header)")
    }

    internal func clearPendingRequest() {
      pendingRequestOrigin = nil
    }

    internal func setHolderNotice(_ notice: String?) {
      holderNotice = notice
    }
  }
#endif
