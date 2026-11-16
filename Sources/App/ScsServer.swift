// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if FEATURE_SCS && os(macOS)
  import CardCore
  import Foundation
  import Network

  /// The localhost SCS listener: TLS on `127.0.0.1:53952`, bounded
  /// connections and read deadlines, prompt-independent `/version` and
  /// `OPTIONS`, and one card-signing operation at a time.
  internal final class ScsServer: @unchecked Sendable {
    private struct ConnectionSlot {
      let connection: NWConnection
      let cancellation: ScsPromptCancellationToken
      var readWorkItem: DispatchWorkItem?
    }

    private static let readChunkLength = 65_536

    private let ioQueue = DispatchQueue(label: "fi.refineid.scs.io")
    private let executor: ScsSignExecutor
    private let limits: ScsServerLimits
    private let makeParameters: () -> NWParameters?
    private let observeState: @Sendable (NWListener.State) -> Void
    private let onStatusFailure: @Sendable (String?) -> Void
    private let lifecycleLock = NSLock()
    private var listener: NWListener?
    private var slots: [ObjectIdentifier: ConnectionSlot] = [:]

    internal var localPort: NWEndpoint.Port? {
      lifecycleLock.withLock { listener?.port }
    }

    internal init(
      limits: ScsServerLimits,
      backend: any ScsSigningBackend & Sendable,
      cardCancellationHook: (@Sendable (ScsPromptCancellationToken, () -> Data) -> Data)?,
      resetBackendHook: @escaping @Sendable () -> Void,
      makeParameters: @escaping () -> NWParameters?,
      observeState: @escaping @Sendable (NWListener.State) -> Void,
      onStatusFailure: @escaping @Sendable (String?) -> Void
    ) {
      self.limits = limits
      self.executor = ScsSignExecutor(
        backend: backend,
        cardCancellationHook: cardCancellationHook,
        resetBackendHook: resetBackendHook
      )
      self.makeParameters = makeParameters
      self.observeState = observeState
      self.onStatusFailure = onStatusFailure
    }

    @MainActor
    internal func start() {
      guard lifecycleLock.withLock({ listener == nil }), let parameters = makeParameters() else {
        return
      }
      guard let bound = try? NWListener(using: parameters) else {
        ScsLog.error("server: bind failed on port \(ScsDispatcher.port)")
        onStatusFailure(
          String(
            localized:
              "Local signing port 53952 is unavailable; another signing service may be running."
          ))
        return
      }
      configureListener(bound)
      lifecycleLock.withLock { listener = bound }
      bound.start(queue: ioQueue)
    }

    @MainActor
    internal func stop() {
      let active = lifecycleLock.withLock { () -> (NWListener?, [ConnectionSlot]) in
        let captured = (listener, Array(slots.values))
        listener = nil
        slots.removeAll()
        return captured
      }
      active.0?.cancel()
      for slot in active.1 {
        slot.readWorkItem?.cancel()
        slot.cancellation.cancel()
        slot.connection.cancel()
      }
      executor.reset()
      onStatusFailure(nil)
    }

    private func configureListener(_ bound: NWListener) {
      bound.stateUpdateHandler = { [weak self, weak bound, observeState, onStatusFailure] state in
        observeState(state)
        switch state {
        case .ready:
          onStatusFailure(nil)
          ScsLog.info("server: listening on https://127.0.0.1:\(ScsDispatcher.port)")
        case .waiting(let error), .failed(let error):
          ScsLog.error("server: listener unavailable on port \(ScsDispatcher.port) (\(error))")
          onStatusFailure(
            String(localized: "Local signing port 53952 is already in use or unavailable."))
          if let self, let bound { failListener(bound) }
        default:
          break
        }
      }
      bound.newConnectionHandler = { [weak self, weak bound] connection in
        if let self, let bound {
          accept(connection, from: bound)
        } else {
          connection.cancel()
        }
      }
    }

    private func failListener(_ bound: NWListener) {
      let owned = lifecycleLock.withLock { () -> Bool in
        guard listener === bound else { return false }
        listener = nil
        return true
      }
      if owned { bound.cancel() }
    }

    private func accept(_ connection: NWConnection, from bound: NWListener) {
      let token = ScsPromptCancellationToken()
      let readDeadline = DispatchWorkItem { [weak self, weak connection] in
        if let self, let connection { dropConnection(connection) }
      }
      let accepted = lifecycleLock.withLock { () -> Bool in
        guard listener === bound, slots.count < limits.maximumConnections else { return false }
        slots[ObjectIdentifier(connection)] = ConnectionSlot(
          connection: connection, cancellation: token, readWorkItem: readDeadline)
        connection.start(queue: ioQueue)
        return true
      }
      guard accepted else {
        readDeadline.cancel()
        connection.cancel()
        return
      }
      ioQueue.asyncAfter(deadline: .now() + limits.readTimeoutSeconds, execute: readDeadline)
      connection.stateUpdateHandler = { [weak self] state in
        if case .cancelled = state { self?.dropConnection(connection) }
        if case .failed = state { self?.dropConnection(connection) }
      }
      receive(connection, buffered: Data())
    }

    private func dropConnection(_ connection: NWConnection) {
      let removed = lifecycleLock.withLock {
        slots.removeValue(forKey: ObjectIdentifier(connection))
      }
      removed?.readWorkItem?.cancel()
      removed?.cancellation.cancel()
      connection.stateUpdateHandler = nil
      connection.cancel()
    }

    private func claimReadComplete(_ connection: NWConnection) -> ScsPromptCancellationToken? {
      lifecycleLock.withLock {
        let key = ObjectIdentifier(connection)
        guard var slot = slots[key] else { return nil }
        slot.readWorkItem?.cancel()
        slot.readWorkItem = nil
        slots[key] = slot
        return slot.cancellation
      }
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readChunkLength) {
        [weak self] content, _, isComplete, error in
        guard let self, lifecycleLock.withLock({ slots[ObjectIdentifier(connection)] != nil })
        else {
          connection.cancel()
          return
        }
        let incoming = content ?? Data()
        if ScsHttpAssembly.exceedsReceiveCeiling(
          bufferedCount: buffered.count, incomingCount: incoming.count)
        {
          dropConnection(connection)
          return
        }
        var buffer = buffered
        buffer.append(incoming)
        switch ScsHttpAssembly.assemble(buffer: buffer) {
        case .complete(let exchange):
          route(exchange, over: connection)
        case .invalid:
          dropConnection(connection)
        case .needMoreData:
          if error != nil || isComplete {
            dropConnection(connection)
          } else {
            receive(connection, buffered: buffer)
          }
        }
      }
    }

    private func route(_ exchange: ScsHttpExchange, over connection: NWConnection) {
      guard let token = claimReadComplete(connection) else {
        connection.cancel()
        return
      }
      ScsLog.info("server: \(exchange.request.method) \(exchange.request.path)")
      if exchange.request.isStatelessFastPath {
        sendAndClose(executor.dispatchFastPath(exchange), over: connection)
        return
      }
      let submitted = executor.submit(
        exchange,
        token: token,
        timeoutSeconds: limits.signTimeoutSeconds,
        callbackQueue: ioQueue
      ) { [weak self] response in
        guard let self else {
          connection.cancel()
          return
        }
        if let response {
          sendAndClose(response, over: connection)
        } else {
          dropConnection(connection)
        }
      }
      if !submitted {
        sendAndClose(
          ScsDispatcher.busySignResponse(origin: exchange.request.origin), over: connection)
      }
    }

    private func sendAndClose(_ response: Data, over connection: NWConnection) {
      guard lifecycleLock.withLock({ slots[ObjectIdentifier(connection)] != nil }) else {
        connection.cancel()
        return
      }
      connection.send(
        content: response,
        completion: .contentProcessed { [weak self] _ in
          self?.dropConnection(connection)
        }
      )
    }
  }
#endif
