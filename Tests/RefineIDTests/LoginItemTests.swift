// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import ServiceManagement
  import Testing

  @testable import RefineID

  /// A login launch is read from the launch event, and the app registers
  /// itself once, never against a registration the holder removed.
  @Suite
  internal struct LoginItemTests {
    private static let allStatuses: [SMAppService.Status] = [
      .notRegistered, .enabled, .requiresApproval, .notFound,
    ]

    private static func launchEvent(
      _ eventID: AEEventID,
      propertyData: OSType? = nil
    ) -> NSAppleEventDescriptor {
      let event = NSAppleEventDescriptor.appleEvent(
        withEventClass: kCoreEventClass,
        eventID: eventID,
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
      )
      if let propertyData {
        event.setParam(
          NSAppleEventDescriptor(enumCode: propertyData),
          forKeyword: keyAEPropData
        )
      }
      return event
    }

    @Test
    internal func openingAsLoginItemIsALoginLaunch() {
      let event = Self.launchEvent(kAEOpenApplication, propertyData: keyAELaunchedAsLogInItem)
      #expect(LoginItem.isLoginLaunch(event))
    }

    @Test
    internal func theLoginItemCodeAsItsOwnParameterIsALoginLaunch() {
      let event = Self.launchEvent(kAEOpenApplication)
      event.setParam(
        NSAppleEventDescriptor(boolean: true),
        forKeyword: keyAELaunchedAsLogInItem
      )
      #expect(LoginItem.isLoginLaunch(event))
    }

    @Test
    internal func otherLaunchesAreNotLoginLaunches() {
      #expect(!LoginItem.isLoginLaunch(nil))
      #expect(!LoginItem.isLoginLaunch(Self.launchEvent(kAEOpenApplication)))
      #expect(
        !LoginItem.isLoginLaunch(
          Self.launchEvent(kAEOpenApplication, propertyData: keyAELaunchedAsServiceItem)))
      #expect(
        !LoginItem.isLoginLaunch(
          Self.launchEvent(kAEReopenApplication, propertyData: keyAELaunchedAsLogInItem)))
    }

    @Test(arguments: allStatuses)
    internal func automatedLaunchesLeaveTheRegistration(status: SMAppService.Status) {
      let action = LoginItem.action(
        automated: true, installed: true, registeredBefore: false, status: status)
      #expect(action == .nothing)
    }

    @Test
    internal func automatedLaunchesNeverAskServiceManagement() {
      var asked = false
      let action = LoginItem.action(
        automated: true, installed: true, registeredBefore: false,
        status: {
          asked = true
          return .notRegistered
        }())
      #expect(action == .nothing)
      #expect(!asked)
    }

    @Test(arguments: allStatuses)
    internal func aRemovedRegistrationStaysRemoved(status: SMAppService.Status) {
      let action = LoginItem.action(
        automated: false, installed: true, registeredBefore: true, status: status)
      #expect(action == .nothing)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, .notFound])
    internal func aFirstInstalledLaunchRegisters(status: SMAppService.Status) {
      let action = LoginItem.action(
        automated: false, installed: true, registeredBefore: false, status: status)
      #expect(action == .register)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, .notFound])
    internal func aCopyOutsideApplicationsNeverRegisters(status: SMAppService.Status) {
      let action = LoginItem.action(
        automated: false, installed: false, registeredBefore: false, status: status)
      #expect(action == .nothing)
    }

    @Test(arguments: [SMAppService.Status.enabled, .requiresApproval])
    internal func anExistingRegistrationIsRecordedNotRepeated(status: SMAppService.Status) {
      for installed in [true, false] {
        let action = LoginItem.action(
          automated: false, installed: installed, registeredBefore: false, status: status)
        #expect(action == .recordRegistration)
      }
    }
  }

#endif
