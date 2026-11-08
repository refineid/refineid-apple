// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The device as a person names it, for the display name an iPhone or an
/// iPad gives itself in a pairing (RAPP v26.11.8 §4.3 item 3): "iPhone 15
/// Pro Max" rather than the operating system.
///
/// Apple reports the hardware as a machine identifier such as
/// `iPhone16,2` and publishes no interface for the marketing name; the
/// names come from the device database Xcode ships, generated into
/// `DeviceModels` by `Scripts/generate-device-models.sh`, and an
/// identifier not listed is shown as it is.
internal enum DeviceModel {
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

  /// The marketing name for `identifier`, or the device's family, such
  /// as "iPhone", when the identifier is not listed: the name a phone or
  /// a tablet is known by in a pairing (``PeerDisplayName``).
  internal static func name(ofMachine identifier: String, family: String) -> String {
    DeviceModels.names[identifier] ?? family
  }
}
