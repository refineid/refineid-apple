// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import Foundation

  extension RappNearFieldSessionHolder.Context {
    /// A context over `box`: every question reads the box as it is asked,
    /// and every mark is written before the mark returns.
    internal static func live(on box: CredentialSessionBox) -> Self {
      Self(
        isRoleProbed: { role in box.read().probedRoles.contains(role) },
        isNegativePin: { fingerprint in box.read().isNegativePin(fingerprint) },
        markRoleProbed: { role in box.mutate { $0.markProbed(role) } },
        recordNegativePin: { fingerprint, role in
          box.mutate { $0.recordNegativePin(fingerprint, role: role) }
        }
      )
    }
  }
#endif
