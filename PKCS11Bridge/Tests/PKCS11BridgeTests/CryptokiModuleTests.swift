// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation
import Testing

@testable import PKCS11Bridge

/// The interface versions the module publishes, newest first.
private let currentVersion = CK_VERSION(
  major: CK_BYTE(CRYPTOKI_VERSION_MAJOR),
  minor: CK_BYTE(CRYPTOKI_VERSION_MINOR)
)
private let version30Major: CK_BYTE = 3
private let baseVersion30 = CK_VERSION(major: version30Major, minor: 0)
private let legacyVersion = CK_VERSION(
  major: CK_BYTE(CRYPTOKI_LEGACY_VERSION_MAJOR),
  minor: CK_BYTE(CRYPTOKI_LEGACY_VERSION_MINOR)
)

/// Whether a reflected function-list member holds a non-nil value.
private func isPresent(_ value: Any) -> Bool {
  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else { return true }
  return !mirror.children.isEmpty
}

/// Expects every function pointer of a reflected function list to be set.
private func expectComplete(_ list: some Any, entries: Int) {
  let children = Mirror(reflecting: list).children.filter { $0.label != "version" }
  #expect(children.count == entries)
  for (label, value) in children {
    #expect(isPresent(value), "missing function list entry: \(label ?? "unlabeled")")
  }
}

@Suite(.serialized)
internal struct CryptokiModuleTests {
  private let legacyEntryCount = 68
  private let entryCount30 = 92
  private let entryCount32 = 104

  @Test
  internal func legacyFunctionListIsCompleteAndVersioned() throws {
    var listPointer: CK_FUNCTION_LIST_PTR?
    #expect(C_GetFunctionList(&listPointer) == CKR_OK)
    let list = try #require(listPointer).pointee
    #expect(list.version.major == legacyVersion.major)
    #expect(list.version.minor == legacyVersion.minor)
    expectComplete(list, entries: legacyEntryCount)
  }

  @Test
  internal func rejectsNilFunctionListDestination() {
    #expect(C_GetFunctionList(nil) == CKR_ARGUMENTS_BAD)
    #expect(C_GetInterfaceList(nil, nil) == CKR_ARGUMENTS_BAD)
    #expect(C_GetInterface(nil, nil, nil, 0) == CKR_ARGUMENTS_BAD)
  }

  @Test
  internal func interfaceListUsesTwoCallConvention() {
    var count = CK_ULONG(0)
    #expect(C_GetInterfaceList(nil, &count) == CKR_OK)
    #expect(count == 3)

    var tooSmall = [CK_INTERFACE()]
    var smallCount = CK_ULONG(tooSmall.count)
    #expect(C_GetInterfaceList(&tooSmall, &smallCount) == CKR_BUFFER_TOO_SMALL)
    #expect(smallCount == count)

    var interfaces = [CK_INTERFACE](repeating: CK_INTERFACE(), count: Int(count))
    #expect(C_GetInterfaceList(&interfaces, &count) == CKR_OK)
    for interface in interfaces {
      #expect(String(cString: interface.pInterfaceName) == "PKCS 11")
    }
  }

  @Test
  internal func defaultInterfaceIsCurrentVersionAndComplete() throws {
    var interfacePointer: CK_INTERFACE_PTR?
    #expect(C_GetInterface(nil, nil, &interfacePointer, 0) == CKR_OK)
    let interface = try #require(interfacePointer).pointee
    #expect(String(cString: interface.pInterfaceName) == "PKCS 11")
    let functionList = try #require(interface.pFunctionList)
      .assumingMemoryBound(to: CK_FUNCTION_LIST_3_2.self).pointee
    #expect(functionList.version.major == currentVersion.major)
    #expect(functionList.version.minor == currentVersion.minor)
    expectComplete(functionList, entries: entryCount32)
  }

  @Test
  internal func interfaceSelectionByVersion() throws {
    var utf8Name: [CK_UTF8CHAR] = Array("PKCS 11".utf8) + [0]
    var interfacePointer: CK_INTERFACE_PTR?
    try utf8Name.withUnsafeMutableBufferPointer { buffer in
      let name = buffer.baseAddress

      var requested = baseVersion30
      #expect(C_GetInterface(name, &requested, &interfacePointer, 0) == CKR_OK)
      let selected = try #require(interfacePointer).pointee
      let list30 = try #require(selected.pFunctionList)
        .assumingMemoryBound(to: CK_FUNCTION_LIST_3_0.self).pointee
      #expect(list30.version.major == baseVersion30.major)
      #expect(list30.version.minor == baseVersion30.minor)
      expectComplete(list30, entries: entryCount30)

      var legacyRequested = legacyVersion
      #expect(C_GetInterface(name, &legacyRequested, &interfacePointer, 0) == CKR_OK)

      let unpublished: CK_BYTE = 9
      var unknown = CK_VERSION(major: unpublished, minor: unpublished)
      #expect(C_GetInterface(name, &unknown, &interfacePointer, 0) == CKR_ARGUMENTS_BAD)
    }
  }

  @Test
  internal func lifecycleInfoSlotsAndStubs() throws {
    var info = CK_INFO()
    #expect(C_GetInfo(&info) == CKR_CRYPTOKI_NOT_INITIALIZED)

    #expect(C_Initialize(nil) == CKR_OK)
    #expect(C_Initialize(nil) == CKR_CRYPTOKI_ALREADY_INITIALIZED)

    #expect(C_GetInfo(&info) == CKR_OK)
    #expect(info.cryptokiVersion.major == currentVersion.major)
    #expect(info.cryptokiVersion.minor == currentVersion.minor)
    let manufacturer = try #require(
      withUnsafeBytes(of: info.manufacturerID) { raw in
        String(bytes: raw, encoding: .utf8)
      }
    )
    #expect(manufacturer.hasPrefix("RefineID"))
    #expect(manufacturer.hasSuffix(" "))

    var slotCount = CK_ULONG(0)
    #expect(C_GetSlotList(CK_FALSE, nil, &slotCount) == CKR_OK)
    #expect(C_GetSlotList(CK_FALSE, nil, nil) == CKR_ARGUMENTS_BAD)

    #expect(C_OpenSession(0, 0, nil, nil, nil) == CKR_ARGUMENTS_BAD)
    #expect(C_Login(0, 0, nil, 0) == CKR_SESSION_HANDLE_INVALID)
    #expect(C_Sign(0, nil, 0, nil, nil) == CKR_ARGUMENTS_BAD)
    #expect(C_SignInit(0, nil, 0) == CKR_ARGUMENTS_BAD)
    #expect(C_FindObjectsFinal(0) == CKR_SESSION_HANDLE_INVALID)
    #expect(C_GetSessionInfo(0, nil) == CKR_ARGUMENTS_BAD)
    #expect(C_GetSlotInfo(CK_UNAVAILABLE_INFORMATION, nil) == CKR_ARGUMENTS_BAD)
    #expect(C_LoginUser(0, 0, nil, 0, nil, 0) == CKR_FUNCTION_NOT_SUPPORTED)
    #expect(
      C_EncapsulateKey(0, nil, 0, nil, 0, nil, nil, nil) == CKR_FUNCTION_NOT_SUPPORTED
    )
    #expect(C_GetFunctionStatus(0) == CKR_FUNCTION_NOT_PARALLEL)
    #expect(C_CancelFunction(0) == CKR_FUNCTION_NOT_PARALLEL)

    #expect(C_Finalize(nil) == CKR_OK)
    #expect(C_Finalize(nil) == CKR_CRYPTOKI_NOT_INITIALIZED)
  }

  /// Section 5.4: C_Finalize closes every session and logs every token
  /// out, so a later C_Initialize starts with no state from this epoch.
  @Test
  internal func finalizeClosesSessionsAndLogsTokensOut() {
    #expect(C_Initialize(nil) == CKR_OK)
    ModuleRegistry.shared.withLock { registry in
      registry.tokens = [
        ModuleRegistry.TokenRecord(
          slotID: 1,
          tokenID: "finalize-test",
          label: "Finalize Test",
          objects: [],
          loggedIn: true,
          authenticationContext: nil)
      ]
      registry.sessions[7] = ModuleRegistry.SessionRecord(slotID: 1, flags: 0)
    }

    #expect(C_Finalize(nil) == CKR_OK)

    let (sessionsLeft, stillLoggedIn) = ModuleRegistry.shared.withLock { registry in
      (registry.sessions.count, registry.tokens.contains(where: \.loggedIn))
    }
    #expect(sessionsLeft == 0)
    #expect(!stillLoggedIn)
    ModuleRegistry.shared.withLock { $0.tokens = [] }
  }
}
