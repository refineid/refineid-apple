// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Darwin
import Foundation

#if canImport(UIKit)
  import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif

extension RappDeviceIdentity {
  // MARK: Internal Static Functions

  internal static func resolveDeviceName() -> String {
    #if os(iOS)
      resolveIOSDeviceName()
    #elseif os(macOS)
      resolveMacOSDeviceName()
    #else
      "Apple Device"
    #endif
  }

  internal static func resolveModelName() -> String {
    #if os(iOS)
      let machine = readSysctlString("hw.machine") ?? ""
      if !machine.isEmpty, let marketing = friendlyMarketingName(from: machine) {
        return marketing
      }
      return machine.isEmpty ? currentDeviceModel() : machine
    #elseif os(macOS)
      let model = readSysctlString("hw.model") ?? ""
      if !model.isEmpty, let marketing = friendlyMarketingName(from: model) {
        return marketing
      }
      return model.isEmpty ? "Mac" : model
    #else
      return "Apple"
    #endif
  }

  /// Resolves a hardware model identifier (e.g. "iPhone16,2", "MacBookPro18,1") to a
  /// user-facing marketing name (e.g. "iPhone 15 Pro Max", "MacBook Pro") using the
  /// OS-provided UniformTypeIdentifiers database, without hardcoded tables.
  public static func friendlyMarketingName(from rawIdentifier: String) -> String? {
    let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    #if canImport(UniformTypeIdentifiers)
      if let uttype = UTType(
        tag: trimmed,
        tagClass: UTTagClass(rawValue: "com.apple.device-model-code"),
        conformingTo: nil
      ),
        let desc = uttype.localizedDescription,
        !desc.isEmpty
      {
        return desc
      }
    #endif
    return nil
  }

  #if os(iOS)
    private static func currentDeviceModel() -> String {
      guard !Thread.isMainThread else {
        return MainActor.assumeIsolated { UIDevice.current.model }
      }
      return DispatchQueue.main.sync {
        MainActor.assumeIsolated { UIDevice.current.model }
      }
    }

    private static func currentDeviceName() -> String {
      guard !Thread.isMainThread else {
        return MainActor.assumeIsolated { UIDevice.current.name }
      }
      return DispatchQueue.main.sync {
        MainActor.assumeIsolated { UIDevice.current.name }
      }
    }

    private static func resolveIOSDeviceName() -> String {
      let deviceNameStorageKey = "fi.refineid.rapp.device-name"
      let args = ProcessInfo.processInfo.arguments
      if let idx = args.firstIndex(of: "--device-name"), args.indices.contains(idx + 1) {
        let passed = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        if !passed.isEmpty {
          UserDefaults.standard.set(passed, forKey: deviceNameStorageKey)
          return passed
        }
      }

      let current = currentDeviceName().trimmingCharacters(in: .whitespacesAndNewlines)
      if !current.isEmpty,
        current.caseInsensitiveCompare("iPhone") != .orderedSame,
        current.caseInsensitiveCompare("iPad") != .orderedSame,
        current.caseInsensitiveCompare("iPod touch") != .orderedSame,
        current.caseInsensitiveCompare("Apple Device") != .orderedSame,
        current.caseInsensitiveCompare("localhost") != .orderedSame
      {
        UserDefaults.standard.set(current, forKey: deviceNameStorageKey)
        return current
      }

      if let prefix = resolveHostPrefix(from: ProcessInfo.processInfo.hostName) {
        UserDefaults.standard.set(prefix, forKey: deviceNameStorageKey)
        return prefix
      }

      if let cached = UserDefaults.standard.string(forKey: deviceNameStorageKey),
        !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return cached.trimmingCharacters(in: .whitespacesAndNewlines)
      }

      return current.isEmpty ? currentDeviceName() : current
    }

    private static func resolveHostPrefix(from host: String) -> String? {
      if host.hasSuffix(".arpa") || host.contains(".in-addr.") || host.contains(".ip6.") {
        return nil
      }
      let prefix =
        host
        .replacingOccurrences(of: ".coredevice.local", with: "")
        .replacingOccurrences(of: ".local", with: "")
        .components(separatedBy: ".")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !prefix.isEmpty,
        UUID(uuidString: prefix) == nil,
        prefix.range(of: #"^[0-9a-fA-F-]+$"#, options: .regularExpression) == nil,
        prefix.caseInsensitiveCompare("localhost") != .orderedSame,
        prefix.caseInsensitiveCompare("iphone") != .orderedSame,
        prefix.caseInsensitiveCompare("ipad") != .orderedSame,
        prefix.caseInsensitiveCompare("apple device") != .orderedSame
      {
        return prefix
      }
      return nil
    }
  #endif

  #if os(macOS)
    private static func resolveMacOSDeviceName() -> String {
      let localized =
        Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let isFqdn = localized.contains(".") && !localized.hasSuffix(".local")
      if !localized.isEmpty,
        !isFqdn,
        localized.caseInsensitiveCompare("localhost") != .orderedSame
      {
        return localized
      }
      let host =
        ProcessInfo.processInfo.hostName
        .replacingOccurrences(of: ".coredevice.local", with: "")
        .replacingOccurrences(of: ".local", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !host.isEmpty,
        !host.contains("."),
        !host.contains(":"),
        host.caseInsensitiveCompare("localhost") != .orderedSame
      {
        return host
      }
      return localized.isEmpty ? "Mac" : localized
    }
  #endif

  private static func readSysctlString(_ name: String) -> String? {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
    let str = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (str?.isEmpty == false) ? str : nil
  }
}
