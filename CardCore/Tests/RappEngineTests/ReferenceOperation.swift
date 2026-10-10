// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Golden values encoded independently from the RAPP v26.10.9 request schema.
///
/// They cover the five registered operations, pinning the action names, the
/// split between consent context and profile payload, and the request body.
internal enum ReferenceOperation {
  internal static let browserHash =
    "d76ee9b71a2dfdb9f6a0abbae574880838a123b0ca12515d9046589549310f1e"
  internal static let browserBody =
    "a666616374696f6e7462726f777365725f61757468656e74696361746567636f6e74657874a1666f7269"
    + "67696e7468747470733a2f2f6578616d706c652e74657374677061796c6f6164a3666469676573745820"
    + "666666666666666666666666666666666666666666666666666666666666666669616c676f726974686d"
    + "6c65636473615f7368613235366b6b65795f70726f66696c656a65636473615f703235366770726f6669"
    + "6c65781d66692e726566696e6569642e61757468656e7469636174696f6e2e76316c6f7065726174696f"
    + "6e5f6964504444444444444444444444444444444470657870697265735f61667465725f6d731a0001d4"
    + "c0"
  internal static let signHash =
    "e50133bdeb80a040cf52a198917c3e7e27e3e467b5907087afffe0a11ebfe73c"
  internal static let identityHash =
    "21b100b441d5f29cc92f860716fd27a73443ad37afa649261f282fca49d4c674"
  internal static let certificateHash =
    "34544fb901b0464881895bf7632a70fac9a02f7ea49a487044940491a152ec4c"
  internal static let inspectHash =
    "1eb217b1eaf7d95edf40f19ed07f1e675458cbf4f5b31c488c37f4a1188b8fc8"
}
