// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    // MARK: Properties

    internal let inbox: RappAuthorizationInbox
    internal var pin1ByOperation: [Data: String] = [:]
    internal var pin2ByOperation: [Data: String] = [:]
    internal var pin2Window = Pin2Window()
    internal var lastReadAuthCertDER: Data?

    // MARK: Lifecycle

    internal init(inbox: RappAuthorizationInbox) {
      self.inbox = inbox
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

    // MARK: Functions

    internal func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established, .peerBusy, .progress, .batchSignatures, .cardStatus:
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
