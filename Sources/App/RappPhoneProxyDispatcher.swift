// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    // MARK: Properties

    internal let inbox: RappAuthorizationInbox
    internal let requireExplicitReconnect: @MainActor @Sendable () -> Void
    internal var pin1ByOperation: [Data: String] = [:]
    internal var pin2ByOperation: [Data: String] = [:]
    internal var pin2Window = Pin2Window()
    internal var lastReadAuthCertDER: Data?

    // MARK: Lifecycle

    internal init(
      inbox: RappAuthorizationInbox,
      requireExplicitReconnect: @escaping @MainActor @Sendable () -> Void
    ) {
      self.inbox = inbox
      self.requireExplicitReconnect = requireExplicitReconnect
    }

    // MARK: Static Functions

    /// The remembered name of the selected pair's requesting device.
    internal static func requesterName() async -> String? {
      let catalog = RappPairCatalog(vault: RappDeviceVault())
      guard let selected = try? await catalog.selectedPair() else {
        return nil
      }
      return RappPairNames.name(forPairID: selected.pairID)
    }

    /// Printed serial of the currently primed identity, if available.
    internal static func storedTokenSerial() -> String? {
      guard let tokenSerial = PrimeStore.storedIdentities().first?.tokenSerial else {
        return nil
      }
      if let serial = TokenSerial(value: tokenSerial),
        let printed = PrintedCardSerial(tokenSerial: serial)
      {
        return printed.value.lowercased()
      }
      return tokenSerial.lowercased()
    }

    // MARK: Functions

    internal func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established, .peerBusy, .progress, .batchSignatures:
        return

      case .inspectPrerequisites(let operationID, let operation):
        await inspectPrerequisites(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .awaitUserApproval(let operationID, let operation):
        await handleApproval(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .executeSafeRead(let operationID, let operation):
        await executeSafeRead(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .executeCardCommand(let operationID, let operation):
        await executeCardCommand(
          operationID: operationID, operation: operation, coordinator: coordinator)

      case .operationFinished(let operationID),
        .peerUnknownOperation(let operationID),
        .terminal(let operationID, _, _):
        await cancel(operationID)

      case .completed(let operationID, _):
        await cancel(operationID)

      case .closed:
        await cleanup()
      }
    }

    private func cleanup() async {
      lastReadAuthCertDER = nil
      pin1ByOperation.removeAll(keepingCapacity: false)
      pin2ByOperation.removeAll(keepingCapacity: false)
      pin2Window.forget()
      await inbox.cancelAll()
    }
  }
#endif
