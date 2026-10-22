// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The device as a person names it, for the platform description a
/// pairing carries (RAPP v26.10.22 section 7.1): "iPhone 15 Pro Max"
/// rather than the operating system, since the model tells which device
/// this is and the system does not.
///
/// Apple reports the hardware as a machine identifier such as
/// `iPhone16,2` and publishes no interface for the marketing name; the
/// names come from the device database Xcode ships, generated into
/// `DeviceModels` by `Scripts/generate-device-models.sh`, and an
/// identifier not listed is shown as it is.
internal enum DeviceModel {
  /// The marketing name of this device, or its machine identifier.
  internal static var description: String {
    #if os(macOS)
      return "Mac"
    #else
      return name(ofMachine: machineIdentifier)
    #endif
  }

  /// `iPhone16,2` as `uname` reports it, or the simulated device's
  /// identifier when running in the simulator.
  internal static var machineIdentifier: String {
    if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simulated
    }
    var system = utsname()
    uname(&system)
    return withUnsafePointer(to: &system.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { characters in
        String(cString: characters)
      }
    }
  }

  /// The marketing name for `identifier`, or `identifier` itself.
  internal static func name(ofMachine identifier: String) -> String {
    DeviceModels.names[identifier] ?? identifier
  }
}
