// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD
  import CardCore

  /// Takes peer-verified operations from `RappTokenExtension` and carries them
  /// on the session this app holds with the phone (CC-71).
  internal enum HeldSessionHandoffPort {
    /// Opens the peer-verified handoff listener in the shared app-group container.
    internal static func start() {
      let started = RappHeldSessionHandoff.serve { request in
        await PersistentTokenRegistry.shared.carry(request)
      }
      if !started {
        #if DEBUG
          DevErrorLog.report("handoff listener not opened", source: .app)
        #endif
      }
    }
  }
#endif
