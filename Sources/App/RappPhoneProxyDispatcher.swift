// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// Exhaustive semantic dispatcher for one authenticated phone-side RAPP
  /// connection. It sees no wire frames and owns no transport capability.
  internal actor RappPhoneProxyDispatcher {
    // MARK: Properties

    internal let inbox: RappAuthorizationInbox
    /// PIN 1 for each browser authentication, typed or held, until the card
    /// command spends it.
    internal var pin1ByOperation: [RappOperationIdentifier: RappCardExecutor.SigningPin] = [:]
    /// PIN 2 the holder typed for each signature or batch, until the card
    /// command spends it; never kept beyond it (RAPP v26.10.22 §11 item 2).
    internal var pin2ByOperation: [RappOperationIdentifier: String] = [:]
    internal var lastReadAuthCertDER: Data?
    /// The prompt each operation shows the holder, by operation.
    internal var requestIDs: [RappOperationIdentifier: String] = [:]
    /// The operations whose PIN prompt reached the screen, so the requester
    /// hears `consent_shown` once for each (§8.2 item 3).
    internal var promptedOperations: Set<RappOperationIdentifier> = []

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
      case .established, .progress, .cardStatus:
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

      case .completed(let operationID, _), .terminal(let operationID, _),
        .operationEnded(.dropped(let operationID)),
        .operationEnded(.cardExchangeContinues(let operationID)):
        await cancel(operationID)

      case .closed:
        await cleanup()
      }
    }

    /// The prompt identifier for `operationID`, made once per operation.
    internal func requestID(for operationID: RappOperationIdentifier) -> String {
      if let existing = requestIDs[operationID] { return existing }
      let made = UUID().uuidString
      requestIDs[operationID] = made
      return made
    }

    private func cleanup() async {
      lastReadAuthCertDER = nil
      pin1ByOperation.removeAll(keepingCapacity: false)
      pin2ByOperation.removeAll(keepingCapacity: false)
      requestIDs.removeAll(keepingCapacity: false)
      promptedOperations.removeAll(keepingCapacity: false)
      await inbox.cancelAll()
    }
  }
#endif
