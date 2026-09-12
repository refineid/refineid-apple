// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Synchronization

/// The PKCS#11 entry points implemented in Swift.
///
/// The wrappers below export them with their standard C names. Semantics
/// follow OASIS PKCS#11 v2.40 section 5.4 (general-purpose functions) and
/// section 5.5 (slot and token management). Everything else lives in the
/// CCryptoki target: stubs and the exported CK_FUNCTION_LIST.
internal enum CryptokiEntryPoints {
  /// Module identification reported by C_GetInfo.
  private static let manufacturerName = "RefineID"

  /// Library description reported by C_GetInfo; at most 32 characters.
  private static let libraryName = "PKCS#11 over CryptoTokenKit"

  /// The bridge's own version, distinct from the Cryptoki spec version.
  ///
  /// The year and month this build was cut in; see ``ModuleVersion``
  /// for where the day and bucket are reported.
  private static var libraryVersion: CK_VERSION { ModuleVersion.library }

  /// Whether C_Initialize has completed without a matching C_Finalize.
  private static let initialized = Mutex(false)

  /// Whether the module is between C_Initialize and C_Finalize; the
  /// other entry-point families gate on this.
  internal static var isLive: Bool { initialized.withLock { $0 } }

  /// C_Initialize: validates threading arguments and marks the module live.
  ///
  /// Native locking is always used, which satisfies every caller threading
  /// model the spec allows.
  internal static func initialize(arguments: CK_VOID_PTR?) -> CK_RV {
    if let arguments {
      let initializeArgs = arguments.assumingMemoryBound(to: CK_C_INITIALIZE_ARGS.self)
        .pointee
      guard initializeArgs.pReserved == nil else { return CKR_ARGUMENTS_BAD }
      let anyMutexCallback =
        initializeArgs.CreateMutex != nil || initializeArgs.DestroyMutex != nil
        || initializeArgs.LockMutex != nil || initializeArgs.UnlockMutex != nil
      let everyMutexCallback =
        initializeArgs.CreateMutex != nil && initializeArgs.DestroyMutex != nil
        && initializeArgs.LockMutex != nil && initializeArgs.UnlockMutex != nil
      guard !anyMutexCallback || everyMutexCallback else { return CKR_ARGUMENTS_BAD }
    }
    return initialized.withLock { state in
      guard !state else { return CKR_CRYPTOKI_ALREADY_INITIALIZED }
      state = true
      return CKR_OK
    }
  }

  /// C_Finalize: pReserved must be nil per the spec.
  ///
  /// Section 5.4 has C_Finalize close every session and log every token
  /// out, so a later C_Initialize starts with no state from this epoch.
  internal static func finalize(reserved: CK_VOID_PTR?) -> CK_RV {
    guard reserved == nil else { return CKR_ARGUMENTS_BAD }
    let outcome = initialized.withLock { (state: inout Bool) -> CK_RV in
      guard state else { return CKR_CRYPTOKI_NOT_INITIALIZED }
      state = false
      return CKR_OK
    }
    guard outcome == CKR_OK else { return outcome }
    ModuleRegistry.shared.withLock { registry in
      registry.sessions.removeAll()
      for index in registry.tokens.indices {
        registry.tokens[index].loggedIn = false
        registry.tokens[index].authenticationContext = nil
      }
    }
    return CKR_OK
  }

  /// C_GetInfo: reports the Cryptoki version and module identification.
  internal static func info(into pointer: CK_INFO_PTR?) -> CK_RV {
    guard initialized.withLock({ $0 }) else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let pointer else { return CKR_ARGUMENTS_BAD }
    var value = CK_INFO()
    value.cryptokiVersion = CK_VERSION(
      major: CK_BYTE(CRYPTOKI_VERSION_MAJOR),
      minor: CK_BYTE(CRYPTOKI_VERSION_MINOR)
    )
    value.flags = 0
    value.libraryVersion = libraryVersion
    withUnsafeMutableBytes(of: &value.manufacturerID) { buffer in
      write(padded: manufacturerName, into: buffer)
    }
    withUnsafeMutableBytes(of: &value.libraryDescription) { buffer in
      write(padded: libraryName, into: buffer)
    }
    pointer.pointee = value
    return CKR_OK
  }

  /// Fills a fixed-width PKCS#11 text field: UTF-8 content, space padded,
  /// never NUL terminated, truncated to the field width.
  internal static func write(padded text: String, into buffer: UnsafeMutableRawBufferPointer) {
    let pad = UInt8(ascii: " ")
    var index = 0
    for byte in text.utf8.prefix(buffer.count) {
      buffer[index] = byte
      index += 1
    }
    while index < buffer.count {
      buffer[index] = pad
      index += 1
    }
  }
}

/// Exported C_Initialize; see CryptokiEntryPoints.initialize.
@_cdecl("C_Initialize")
internal func cryptokiInitialize(_ arguments: CK_VOID_PTR?) -> CK_RV {
  CryptokiEntryPoints.initialize(arguments: arguments)
}

/// Exported C_Finalize; see CryptokiEntryPoints.finalize.
@_cdecl("C_Finalize")
internal func cryptokiFinalize(_ reserved: CK_VOID_PTR?) -> CK_RV {
  CryptokiEntryPoints.finalize(reserved: reserved)
}

/// Exported C_GetInfo; see CryptokiEntryPoints.info.
@_cdecl("C_GetInfo")
internal func cryptokiGetInfo(_ pointer: CK_INFO_PTR?) -> CK_RV {
  CryptokiEntryPoints.info(into: pointer)
}

/// Exported C_GetSlotList; see SlotTokenEntryPoints.slotList.
@_cdecl("C_GetSlotList")
internal func cryptokiGetSlotList(
  _ tokenPresent: CK_BBOOL,
  _ slots: CK_SLOT_ID_PTR?,
  _ count: CK_ULONG_PTR?
) -> CK_RV {
  SlotTokenEntryPoints.slotList(tokenPresent: tokenPresent, slots: slots, count: count)
}
