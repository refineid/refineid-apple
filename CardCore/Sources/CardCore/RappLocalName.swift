// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  #if os(macOS)
    import SystemConfiguration
  #else
    import UIKit
  #endif

  /// How this device introduces itself to its RAPP peers (RAPP v26.11.8
  /// §4.3 item 3): its display name, sent in `pairing.hello`,
  /// `session.ready` and `session.hello`, and its platform.
  public enum RappLocalName {
    /// The machine identifier prefix of every iPad.
    private static let tabletFamily = "iPad"
    /// The family a handheld that is not an iPad names.
    private static let phoneFamily = "iPhone"
    /// The host name a Mac without one names.
    private static let macFallbackHost = "Mac"

    /// The name this device gives itself (``PeerDisplayName``): a Mac its
    /// system and host name, an iPhone or an iPad its own name, shortened
    /// at a character boundary to the bound the protocol sets.
    public static var displayName: RappDisplayName {
      if let name = RappDisplayName(shortening: deviceName) { return name }
      #if os(macOS)
        return RappDisplayName(PeerDisplayName.macSystem) ?? fallbackName
      #else
        return fallbackName
      #endif
    }

    /// The operating system this device runs, as `pairing.hello` names it
    /// (§4.3 item 3).
    public static var platform: String {
      #if os(macOS)
        "macOS"
      #else
        isTablet ? "iPadOS" : "iOS"
      #endif
    }

    /// The device's name before the protocol bound applies.
    private static var deviceName: String {
      #if os(macOS)
        computerDeviceName(
          localHostName: SCDynamicStoreCopyLocalHostName(nil) as String?,
          localizedName: Host.current().localizedName)
      #else
        PeerDisplayName.handheld(name: handheldName).text
      #endif
    }

    /// The family name, a name that is never blank.
    private static var fallbackName: RappDisplayName {
      guard let name = RappDisplayName(isTablet ? tabletFamily : phoneFamily) else {
        preconditionFailure("a family name is a display name")
      }
      return name
    }

    private static var isTablet: Bool {
      DeviceModel.machineIdentifier.hasPrefix(tabletFamily)
    }

    #if !os(macOS)
      /// Whether the app reads the name the owner gave this device.
      ///
      /// That takes the
      /// `com.apple.developer.device-information.user-assigned-device-name`
      /// entitlement. Without it `UIDevice.current.name` is only "iPhone"
      /// or "iPad", so the device is named by its model; once the
      /// entitlement is granted and in `Config/RefineID-iOS.entitlements`,
      /// this turns true and the name the owner gave the device is sent.
      private static let readsUserAssignedDeviceName = false

      /// The name the owner gave this device, or its model, such as
      /// "iPhone 15 Pro Max", or its family for a model not listed.
      private static var handheldName: String {
        if readsUserAssignedDeviceName {
          return MainActor.assumeIsolated { UIDevice.current.name }
        }
        return DeviceModel.name(
          ofMachine: DeviceModel.machineIdentifier,
          family: isTablet ? tabletFamily : phoneFamily)
      }
    #endif

    /// A Mac's name from its two host-name sources: the first that
    /// names one, else the fallback host.
    internal static func computerDeviceName(
      localHostName: String?, localizedName: String?
    ) -> String {
      for candidate in [localHostName, localizedName] {
        if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty
        {
          return PeerDisplayName.computer(system: PeerDisplayName.macSystem, host: trimmed).text
        }
      }
      return PeerDisplayName.computer(system: PeerDisplayName.macSystem, host: macFallbackHost)
        .text
    }
  }
#endif
