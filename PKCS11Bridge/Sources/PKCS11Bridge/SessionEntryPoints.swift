// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation
import LocalAuthentication

/// Session management entry points (spec section 5.6).
///
/// Sessions are read-only bookkeeping: the token is write-protected and
/// PIN entry uses the protected authentication path, so C_Login mostly
/// records state. A PIN supplied anyway is carried in an LAContext and
/// bound to the private key at signing time.
internal enum SessionEntryPoints {
  /// C_OpenSession for one slot.
  internal static func open(
    slotID: CK_SLOT_ID, flags: CK_FLAGS, handle: CK_SESSION_HANDLE_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let handle else { return CKR_ARGUMENTS_BAD }
    guard flags & CKF_SERIAL_SESSION != 0 else {
      return CKR_SESSION_PARALLEL_NOT_SUPPORTED
    }
    return ModuleRegistry.shared.withLock { registry in
      if registry.tokens.isEmpty {
        TokenCatalog.refresh(&registry)
      }
      guard registry.token(slotID: slotID) != nil else { return CKR_SLOT_ID_INVALID }
      let sessionHandle = registry.nextSessionHandle
      registry.nextSessionHandle += 1
      registry.sessions[sessionHandle] = ModuleRegistry.SessionRecord(
        slotID: slotID, flags: flags)
      handle.pointee = sessionHandle
      return CKR_OK
    }
  }

  /// C_CloseSession.
  internal static func close(handle: CK_SESSION_HANDLE) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    return ModuleRegistry.shared.withLock { registry in
      guard registry.sessions.removeValue(forKey: handle) != nil else {
        return CKR_SESSION_HANDLE_INVALID
      }
      return CKR_OK
    }
  }

  /// C_CloseAllSessions for one slot.
  internal static func closeAll(slotID: CK_SLOT_ID) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    return ModuleRegistry.shared.withLock { registry in
      guard registry.token(slotID: slotID) != nil else { return CKR_SLOT_ID_INVALID }
      registry.sessions = registry.sessions.filter { $0.value.slotID != slotID }
      return CKR_OK
    }
  }

  /// C_GetSessionInfo.
  internal static func info(
    handle: CK_SESSION_HANDLE, into pointer: CK_SESSION_INFO_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let pointer else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      guard let session = registry.sessions[handle] else {
        return CKR_SESSION_HANDLE_INVALID
      }
      let loggedIn = registry.token(slotID: session.slotID)?.loggedIn ?? false
      var value = CK_SESSION_INFO()
      value.slotID = session.slotID
      value.state = loggedIn ? CKS_RO_USER_FUNCTIONS : CKS_RO_PUBLIC_SESSION
      value.flags = session.flags
      value.ulDeviceError = 0
      pointer.pointee = value
      return CKR_OK
    }
  }

  /// C_Login: with a nil PIN the protected authentication path applies;
  /// a supplied PIN is stored in an LAContext for key operations, and
  /// the bridge's own copy is zeroed before returning.
  internal static func login(
    handle: CK_SESSION_HANDLE,
    userType: CK_USER_TYPE,
    pin: CK_UTF8CHAR_PTR?,
    pinLength: CK_ULONG
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    return ModuleRegistry.shared.withLock { registry in
      guard let session = registry.sessions[handle] else {
        return CKR_SESSION_HANDLE_INVALID
      }
      guard userType == CKU_USER else { return CKR_USER_TYPE_INVALID }
      return registry.withToken(slotID: session.slotID) { token in
        guard !token.loggedIn else { return CKR_USER_ALREADY_LOGGED_IN }
        if let pin, pinLength > 0 {
          var credential = Data(bytes: pin, count: Int(pinLength))
          defer { credential.resetBytes(in: 0..<credential.count) }
          let context = LAContext()
          guard context.setCredential(credential, type: .smartCardPIN) else {
            return CKR_PIN_INCORRECT
          }
          token.authenticationContext = context
        }
        token.loggedIn = true
        return CKR_OK
      }
    }
  }

  /// C_Logout: invalidates the LAContext holding a supplied PIN.
  internal static func logout(handle: CK_SESSION_HANDLE) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    return ModuleRegistry.shared.withLock { registry in
      guard let session = registry.sessions[handle] else {
        return CKR_SESSION_HANDLE_INVALID
      }
      return registry.withToken(slotID: session.slotID) { token in
        guard token.loggedIn else { return CKR_USER_NOT_LOGGED_IN }
        token.loggedIn = false
        token.authenticationContext?.invalidate()
        token.authenticationContext = nil
        return CKR_OK
      }
    }
  }
}

/// Exported C_OpenSession; see SessionEntryPoints.open.
///
/// The application pointer and notification callback are accepted and
/// unused: the bridge never issues notifications.
@_cdecl("C_OpenSession")
internal func cryptokiOpenSession(
  _ slotID: CK_SLOT_ID,
  _ flags: CK_FLAGS,
  _: CK_VOID_PTR?,
  _: CK_NOTIFY?,
  _ handle: CK_SESSION_HANDLE_PTR?
) -> CK_RV {
  SessionEntryPoints.open(slotID: slotID, flags: flags, handle: handle)
}

/// Exported C_CloseSession; see SessionEntryPoints.close.
@_cdecl("C_CloseSession")
internal func cryptokiCloseSession(_ handle: CK_SESSION_HANDLE) -> CK_RV {
  SessionEntryPoints.close(handle: handle)
}

/// Exported C_CloseAllSessions; see SessionEntryPoints.closeAll.
@_cdecl("C_CloseAllSessions")
internal func cryptokiCloseAllSessions(_ slotID: CK_SLOT_ID) -> CK_RV {
  SessionEntryPoints.closeAll(slotID: slotID)
}

/// Exported C_GetSessionInfo; see SessionEntryPoints.info.
@_cdecl("C_GetSessionInfo")
internal func cryptokiGetSessionInfo(
  _ handle: CK_SESSION_HANDLE, _ pointer: CK_SESSION_INFO_PTR?
) -> CK_RV {
  SessionEntryPoints.info(handle: handle, into: pointer)
}

/// Exported C_Login; see SessionEntryPoints.login.
@_cdecl("C_Login")
internal func cryptokiLogin(
  _ handle: CK_SESSION_HANDLE,
  _ userType: CK_USER_TYPE,
  _ pin: CK_UTF8CHAR_PTR?,
  _ pinLength: CK_ULONG
) -> CK_RV {
  SessionEntryPoints.login(
    handle: handle, userType: userType, pin: pin, pinLength: pinLength)
}

/// Exported C_Logout; see SessionEntryPoints.logout.
@_cdecl("C_Logout")
internal func cryptokiLogout(_ handle: CK_SESSION_HANDLE) -> CK_RV {
  SessionEntryPoints.logout(handle: handle)
}
