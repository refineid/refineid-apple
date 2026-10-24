// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import ServiceManagement

  /// The app as a login item: it starts with the session, so a paired
  /// phone stays reachable without the holder opening anything.
  ///
  /// Registered once, from the first launch a holder makes of the copy
  /// in an Applications folder. macOS announces the addition itself and
  /// lists the app under General > Login Items, where the holder can
  /// remove it. A removal stands: once a registration has existed, the
  /// app never registers again.
  internal enum LoginItem {
    /// What a launch does about the registration.
    internal enum Action: Equatable {
      /// Leave the registration as it is.
      case nothing
      /// A registration exists; remember that one has.
      case recordRegistration
      /// Register the app.
      case register
    }

    /// The defaults key recording that a registration has existed.
    private static let registeredKey = "fi.refineid.loginItemRegistered"

    /// Whether a test or a debug launch mode drives this process.
    private static var launchIsAutomated: Bool {
      #if DEBUG
        return DebugLaunchModes.selected() != nil || TestCredentialEnvironment.isTestMode
      #else
        return false
      #endif
    }

    /// Whether this copy of the app sits in an Applications folder.
    ///
    /// A build run from its products folder is not the copy a holder
    /// starts, and a login item pointing there would outlive it.
    private static var runsFromApplicationsFolder: Bool {
      let folder = Bundle.main.bundleURL
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .pathComponents
      return FileManager.default
        .urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        .contains { $0.resolvingSymlinksInPath().pathComponents == folder }
    }

    /// Whether `event` launched the app as a login item.
    ///
    /// A login launch is an open-application event carrying the
    /// launched-as-login-item code (AERegistry.h), as the value of its
    /// property data or as a parameter of its own. AppKit makes that
    /// event current while it delivers the finished-launching
    /// notification, and not before.
    internal static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
      guard let event,
        event.eventClass == kCoreEventClass,
        event.eventID == kAEOpenApplication
      else { return false }
      return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        == keyAELaunchedAsLogInItem
        || event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }

    /// The action for one launch.
    ///
    /// - Parameters:
    ///   - automated: a test or a debug launch mode drives this process.
    ///   - installed: this copy runs from an Applications folder.
    ///   - registeredBefore: a registration has existed since install.
    ///   - status: what Service Management reports for the app now,
    ///     asked only when the other inputs leave the answer open.
    /// - Returns: registration only for a holder's first launch of an
    ///   installed copy with none in place, a record of one in place,
    ///   and otherwise nothing.
    internal static func action(
      automated: Bool,
      installed: Bool,
      registeredBefore: Bool,
      status: @autoclosure () -> SMAppService.Status
    ) -> Action {
      guard !automated, !registeredBefore else { return .nothing }
      switch status() {
      case .enabled, .requiresApproval:
        return .recordRegistration

      case .notRegistered, .notFound:
        return installed ? .register : .nothing

      @unknown default:
        return .nothing
      }
    }

    /// Registers the app when this launch calls for it.
    ///
    /// Service Management answers over XPC, so this leaves the main
    /// actor before asking.
    internal static func registerIfDue() {
      let automated = Self.launchIsAutomated
      Task.detached(priority: .utility) {
        let defaults = UserDefaults.standard
        let service = SMAppService.mainApp
        let action = Self.action(
          automated: automated,
          installed: Self.runsFromApplicationsFolder,
          registeredBefore: defaults.bool(forKey: Self.registeredKey),
          status: service.status
        )
        switch action {
        case .register:
          do {
            try service.register()
            defaults.set(true, forKey: Self.registeredKey)
          } catch {
            #if DEBUG
              DevErrorLog.report(
                "login item: registration failed: \(DevErrorLog.reason(error))", source: .app)
            #endif
          }

        case .recordRegistration:
          defaults.set(true, forKey: Self.registeredKey)

        case .nothing:
          break
        }
      }
    }
  }

#endif
