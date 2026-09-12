// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation

/// Slot and token management entry points (spec section 5.5).
///
/// Every present CryptoTokenKit token is one slot; slots exist only
/// while their token is present, so slot and token flags both report
/// presence. The token advertises the protected authentication path:
/// PIN entry happens in the system dialog, not through the bridge.
internal enum SlotTokenEntryPoints {
  /// Manufacturer reported for slots and tokens.
  private static let manufacturerName = "RefineID"

  /// Model reported in CK_TOKEN_INFO.
  private static let modelName = "CTK bridge"

  /// PIN length bounds reported in CK_TOKEN_INFO; informational only,
  /// since PIN entry uses the protected authentication path.
  private static let minimumPinLength: CK_ULONG = 4
  private static let maximumPinLength: CK_ULONG = 12

  /// Key-size bounds in bits for CK_MECHANISM_INFO.
  private static let minimumEcBits: CK_ULONG = 256
  private static let maximumEcBits: CK_ULONG = 521
  private static let minimumRsaBits: CK_ULONG = 2_048
  private static let maximumRsaBits: CK_ULONG = 4_096

  /// Width of the CK_TOKEN_INFO serial number field.
  private static let serialNumberWidth = 16

  /// C_GetSlotList: refreshes the token snapshot and lists slots.
  internal static func slotList(
    tokenPresent _: CK_BBOOL,
    slots: CK_SLOT_ID_PTR?,
    count: CK_ULONG_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let count else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      TokenCatalog.refresh(&registry)
      let slotIDs = registry.tokens.map(\.slotID)
      guard let slots else {
        count.pointee = CK_ULONG(slotIDs.count)
        return CKR_OK
      }
      guard Int(count.pointee) >= slotIDs.count else {
        count.pointee = CK_ULONG(slotIDs.count)
        return CKR_BUFFER_TOO_SMALL
      }
      for (index, slotID) in slotIDs.enumerated() {
        slots[index] = slotID
      }
      count.pointee = CK_ULONG(slotIDs.count)
      return CKR_OK
    }
  }

  /// C_GetSlotInfo for one slot.
  internal static func slotInfo(slotID: CK_SLOT_ID, into pointer: CK_SLOT_INFO_PTR?) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let pointer else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      guard let token = registry.token(slotID: slotID) else {
        return CKR_SLOT_ID_INVALID
      }
      var value = CK_SLOT_INFO()
      withUnsafeMutableBytes(of: &value.slotDescription) { buffer in
        CryptokiEntryPoints.write(padded: token.label, into: buffer)
      }
      withUnsafeMutableBytes(of: &value.manufacturerID) { buffer in
        CryptokiEntryPoints.write(padded: manufacturerName, into: buffer)
      }
      value.flags = CKF_TOKEN_PRESENT | CKF_REMOVABLE_DEVICE | CKF_HW_SLOT
      pointer.pointee = value
      return CKR_OK
    }
  }

  /// C_GetTokenInfo for one slot's token.
  internal static func tokenInfo(
    slotID: CK_SLOT_ID, into pointer: CK_TOKEN_INFO_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let pointer else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      guard let token = registry.token(slotID: slotID) else {
        return CKR_SLOT_ID_INVALID
      }
      let sessionCount = registry.sessions.values.count { $0.slotID == slotID }
      pointer.pointee = tokenInfoValue(token: token, sessionCount: sessionCount)
      return CKR_OK
    }
  }

  /// Builds the CK_TOKEN_INFO for one token.
  private static func tokenInfoValue(
    token: ModuleRegistry.TokenRecord, sessionCount: Int
  ) -> CK_TOKEN_INFO {
    var value = CK_TOKEN_INFO()
    withUnsafeMutableBytes(of: &value.label) { buffer in
      CryptokiEntryPoints.write(padded: token.label, into: buffer)
    }
    withUnsafeMutableBytes(of: &value.manufacturerID) { buffer in
      CryptokiEntryPoints.write(padded: manufacturerName, into: buffer)
    }
    withUnsafeMutableBytes(of: &value.model) { buffer in
      CryptokiEntryPoints.write(padded: modelName, into: buffer)
    }
    // This token is published by this module rather than by anyone's
    // silicon, so its firmware version is this build: the day and the
    // ten-minute bucket, which is the half of the stamp the library
    // version has no room for.
    value.firmwareVersion = ModuleVersion.firmware
    let serial = String(token.tokenID.suffix(serialNumberWidth))
    withUnsafeMutableBytes(of: &value.serialNumber) { buffer in
      CryptokiEntryPoints.write(padded: serial, into: buffer)
    }
    var flags =
      CKF_TOKEN_INITIALIZED | CKF_USER_PIN_INITIALIZED | CKF_LOGIN_REQUIRED
      | CKF_WRITE_PROTECTED
    if PinEntry.current == .graphical {
      flags |= CKF_PROTECTED_AUTHENTICATION_PATH
    }
    value.flags = flags
    value.ulMaxSessionCount = CK_EFFECTIVELY_INFINITE
    value.ulSessionCount = CK_ULONG(sessionCount)
    value.ulMaxRwSessionCount = CK_EFFECTIVELY_INFINITE
    value.ulRwSessionCount = 0
    value.ulMaxPinLen = maximumPinLength
    value.ulMinPinLen = minimumPinLength
    value.ulTotalPublicMemory = CK_UNAVAILABLE_INFORMATION
    value.ulFreePublicMemory = CK_UNAVAILABLE_INFORMATION
    value.ulTotalPrivateMemory = CK_UNAVAILABLE_INFORMATION
    value.ulFreePrivateMemory = CK_UNAVAILABLE_INFORMATION
    withUnsafeMutableBytes(of: &value.utcTime) { buffer in
      CryptokiEntryPoints.write(padded: "", into: buffer)
    }
    return value
  }

  /// C_GetMechanismList: the token signs with CKM_ECDSA only.
  internal static func mechanismList(
    slotID: CK_SLOT_ID, mechanisms: CK_MECHANISM_TYPE_PTR?, count: CK_ULONG_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let count else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      guard let token = registry.token(slotID: slotID) else {
        return CKR_SLOT_ID_INVALID
      }
      let supported = signingMechanisms(of: token)
      guard let mechanisms else {
        count.pointee = CK_ULONG(supported.count)
        return CKR_OK
      }
      guard Int(count.pointee) >= supported.count else {
        count.pointee = CK_ULONG(supported.count)
        return CKR_BUFFER_TOO_SMALL
      }
      for (index, mechanism) in supported.enumerated() {
        mechanisms[index] = mechanism
      }
      count.pointee = CK_ULONG(supported.count)
      return CKR_OK
    }
  }

  /// C_GetMechanismInfo for CKM_ECDSA.
  internal static func mechanismInfo(
    slotID: CK_SLOT_ID, mechanism: CK_MECHANISM_TYPE, into pointer: CK_MECHANISM_INFO_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let pointer else { return CKR_ARGUMENTS_BAD }
    return ModuleRegistry.shared.withLock { registry in
      guard let token = registry.token(slotID: slotID) else {
        return CKR_SLOT_ID_INVALID
      }
      guard signingMechanisms(of: token).contains(mechanism) else {
        return CKR_MECHANISM_INVALID
      }
      var value = CK_MECHANISM_INFO()
      value.ulMinKeySize = mechanism == CKM_ECDSA ? minimumEcBits : minimumRsaBits
      value.ulMaxKeySize = mechanism == CKM_ECDSA ? maximumEcBits : maximumRsaBits
      value.flags = CKF_HW | CKF_SIGN
      pointer.pointee = value
      return CKR_OK
    }
  }

  /// The signing mechanisms a token's identities use, in the order
  /// C_GetMechanismList reports them.
  private static func signingMechanisms(
    of token: ModuleRegistry.TokenRecord
  ) -> [CK_MECHANISM_TYPE] {
    var found: [CK_MECHANISM_TYPE] = []
    for object in token.objects where object.objectClass == CKO_PRIVATE_KEY {
      let mechanism = SignEntryPoints.signingMechanism(for: object.keyKind)
      if !found.contains(mechanism) { found.append(mechanism) }
    }
    return found
  }
}

/// Exported C_GetSlotInfo; see SlotTokenEntryPoints.slotInfo.
@_cdecl("C_GetSlotInfo")
internal func cryptokiGetSlotInfo(
  _ slotID: CK_SLOT_ID, _ pointer: CK_SLOT_INFO_PTR?
) -> CK_RV {
  SlotTokenEntryPoints.slotInfo(slotID: slotID, into: pointer)
}

/// Exported C_GetTokenInfo; see SlotTokenEntryPoints.tokenInfo.
@_cdecl("C_GetTokenInfo")
internal func cryptokiGetTokenInfo(
  _ slotID: CK_SLOT_ID, _ pointer: CK_TOKEN_INFO_PTR?
) -> CK_RV {
  SlotTokenEntryPoints.tokenInfo(slotID: slotID, into: pointer)
}

/// Exported C_GetMechanismList; see SlotTokenEntryPoints.mechanismList.
@_cdecl("C_GetMechanismList")
internal func cryptokiGetMechanismList(
  _ slotID: CK_SLOT_ID, _ mechanisms: CK_MECHANISM_TYPE_PTR?, _ count: CK_ULONG_PTR?
) -> CK_RV {
  SlotTokenEntryPoints.mechanismList(slotID: slotID, mechanisms: mechanisms, count: count)
}

/// Exported C_GetMechanismInfo; see SlotTokenEntryPoints.mechanismInfo.
@_cdecl("C_GetMechanismInfo")
internal func cryptokiGetMechanismInfo(
  _ slotID: CK_SLOT_ID, _ mechanism: CK_MECHANISM_TYPE, _ pointer: CK_MECHANISM_INFO_PTR?
) -> CK_RV {
  SlotTokenEntryPoints.mechanismInfo(slotID: slotID, mechanism: mechanism, into: pointer)
}
