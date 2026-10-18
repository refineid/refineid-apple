// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The device as a person names it, for the platform description a
/// pairing carries (RAPP v26.10.18 section 7.1): "iPhone 15 Pro Max"
/// rather than the operating system, since the model tells which device
/// this is and the system does not.
///
/// Apple reports the hardware as a machine identifier such as
/// `iPhone16,2` and publishes no interface for the marketing name, so the
/// names of the iPhones the application runs on are listed here by
/// identifier, and an identifier not listed is shown as it is.
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

  /// Apple machine identifiers and the names on the box.
  private static let marketingNames: [String: String] = [
    "iPhone13,1": "iPhone 12 mini",
    "iPhone13,2": "iPhone 12",
    "iPhone13,3": "iPhone 12 Pro",
    "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro",
    "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,4": "iPhone 13 mini",
    "iPhone14,5": "iPhone 13",
    "iPhone14,6": "iPhone SE (3rd generation)",
    "iPhone14,7": "iPhone 14",
    "iPhone14,8": "iPhone 14 Plus",
    "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15",
    "iPhone15,5": "iPhone 15 Plus",
    "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16",
    "iPhone17,4": "iPhone 16 Plus",
    "iPhone17,5": "iPhone 16e",
  ]

  /// The marketing name for `identifier`, or `identifier` itself.
  internal static func name(ofMachine identifier: String) -> String {
    marketingNames[identifier] ?? identifier
  }
}
