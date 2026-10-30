// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import CardCore
  import Foundation
  import Network
  import Security

  /// The localhost SCS listener: TLS on 127.0.0.1:53952, one request
  /// per connection, dispatched to the CardCore protocol surface.
  ///
  /// `@unchecked Sendable` is the audit, not a shrug: the listener,
  /// every connection, and every dispatch run on the one serial
  /// queue below, so no state is touched concurrently. A sign blocks
  /// that queue while the holder answers the PIN prompt, which is
  /// the intended behaviour - the SCS serves one signature at a
  /// time.
  internal final class ScsServer: @unchecked Sendable {
    private static let readChunkLength = 65_536

    internal static var isFeatureEnabled: Bool {
      #if FEATURE_SCS
        true
      #else
        false
      #endif
    }

    private let queue = DispatchQueue(label: "fi.refineid.scs.server")
    private let backend = ScsCardBackend()
    private let transactions = ScsTransactionManager()
    private let makeParameters: () -> NWParameters?
    private let observeState: @Sendable (NWListener.State) -> Void
    private let lifecycleLock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    internal var localPort: NWEndpoint.Port? {
      lifecycleLock.withLock { listener?.port }
    }

    internal convenience init() {
      self.init(
        makeParameters: Self.localTLSParameters,
        observeState: { _ in
          // Production listener status is reported through ScsLog.
        })
    }

    internal init(
      makeParameters: @escaping () -> NWParameters?,
      observeState: @escaping @Sendable (NWListener.State) -> Void
    ) {
      self.makeParameters = makeParameters
      self.observeState = observeState
    }

    private static func localTLSParameters() -> NWParameters? {
      guard let identity = ScsIdentityStore.obtain() else {
        ScsLog.error("server: no TLS identity; SCS not started")
        return nil
      }
      guard let secIdentity = sec_identity_create(identity) else {
        ScsLog.error("server: identity rejected by Network framework")
        return nil
      }
      let tls = NWProtocolTLS.Options()
      sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
      let parameters = NWParameters(tls: tls)
      guard let port = NWEndpoint.Port(rawValue: ScsDispatcher.port) else {
        ScsLog.error("server: invalid port")
        return nil
      }
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host("127.0.0.1"), port: port)
      return parameters
    }

    /// Binds and starts serving; failures are logged, never fatal
    /// to the app.
    @MainActor
    internal func start() {
      guard Self.isFeatureEnabled else { return }
      guard lifecycleLock.withLock({ listener == nil }) else { return }
      guard let parameters = makeParameters() else { return }
      let bound: NWListener
      do {
        bound = try NWListener(using: parameters)
      } catch {
        ScsLog.error("server: bind failed; another SCS already running?")
        return
      }
      bound.stateUpdateHandler = { [observeState] state in
        observeState(state)
        switch state {
        case .ready:
          ScsLog.info("server: listening on https://127.0.0.1:\(ScsDispatcher.port)")

        case .failed:
          ScsLog.error("server: listener failed")

        default:
          break
        }
      }
      bound.newConnectionHandler = { [weak self, weak bound] connection in
        guard let self, let bound else {
          connection.cancel()
          return
        }
        accept(connection, from: bound)
      }
      lifecycleLock.withLock { listener = bound }
      bound.start(queue: queue)
    }

    private func accept(_ connection: NWConnection, from bound: NWListener) {
      let accepted = lifecycleLock.withLock {
        guard listener === bound else { return false }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        return true
      }
      guard accepted else {
        connection.cancel()
        return
      }
      connection.stateUpdateHandler = { [weak self] state in
        switch state {
        case .cancelled, .failed:
          self?.forget(connection)
        default:
          break
        }
      }
      receive(connection, buffered: Data())
    }

    /// Cancels the listener and accepted connections, including queued requests.
    @MainActor
    internal func stop() {
      let active = lifecycleLock.withLock {
        let active = (listener, Array(connections.values))
        listener = nil
        connections.removeAll()
        return active
      }
      active.0?.cancel()
      for connection in active.1 { connection.cancel() }
    }

    private func forget(_ connection: NWConnection) {
      lifecycleLock.withLock {
        _ = connections.removeValue(forKey: ObjectIdentifier(connection))
      }
      connection.stateUpdateHandler = nil
    }

    private func permits(_ connection: NWConnection) -> Bool {
      lifecycleLock.withLock { connections[ObjectIdentifier(connection)] != nil }
    }

    /// Accumulates one request's bytes and dispatches it when
    /// complete.
    private func receive(_ connection: NWConnection, buffered: Data) {
      connection.receive(
        minimumIncompleteLength: 1,
        maximumLength: Self.readChunkLength
      ) { [weak self] content, _, isComplete, error in
        guard let self else {
          connection.cancel()
          return
        }
        guard permits(connection) else {
          connection.cancel()
          return
        }
        var buffer = buffered
        if let content {
          buffer.append(content)
        }
        switch ScsHttpAssembly.assemble(buffer: buffer) {
        case .complete(let exchange):
          respond(to: exchange, over: connection)

        case .invalid:
          connection.cancel()

        case .needMoreData:
          if error != nil || isComplete {
            connection.cancel()
          } else {
            receive(connection, buffered: buffer)
          }
        }
      }
    }

    /// Dispatches one assembled exchange and closes the connection
    /// after the answer, per the SCS's one-request connections.
    private func respond(to exchange: ScsHttpExchange, over connection: NWConnection) {
      guard permits(connection) else {
        connection.cancel()
        return
      }
      ScsLog.info("server: \(exchange.request.method) \(exchange.request.path)")
      let response = ScsDispatcher.dispatch(
        request: exchange.request,
        body: exchange.body,
        backend: backend,
        transactions: transactions
      )
      connection.send(
        content: response,
        completion: .contentProcessed { _ in
          connection.cancel()
        }
      )
    }
  }
#endif
