// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && os(macOS)
  import Darwin
  import Foundation
  import os

  /// Peer-verified `AF_UNIX` stream socket transport for RAPP session handoff.
  extension RappHeldSessionHandoff {
    /// Active local listener handle supporting inode-checked deterministic shutdown.
    internal final class Listener: Sendable {
      private let descriptor: OSAllocatedUnfairLock<Int32>
      private let socketPath: String
      private let socketIdentity: FileSystemIdentity
      private let concurrency = DispatchSemaphore(value: maxConcurrentRequests)

      fileprivate init(
        descriptor: Int32,
        socketPath: String,
        socketIdentity: FileSystemIdentity
      ) {
        self.descriptor = OSAllocatedUnfairLock(initialState: descriptor)
        self.socketPath = socketPath
        self.socketIdentity = socketIdentity
      }

      /// Closes the listening socket and unlinks `socketPath` only if its inode still matches.
      internal func stop() {
        let activeSocket = descriptor.withLock { current -> Int32 in
          defer { current = invalidDescriptor }
          return current
        }
        guard activeSocket != invalidDescriptor else { return }
        _ = Darwin.shutdown(activeSocket, SHUT_RDWR)
        _ = Darwin.close(activeSocket)
        unlinkMatchingSocket(at: socketPath, expected: socketIdentity)
      }

      fileprivate func currentDescriptor() -> Int32 {
        descriptor.withLock { $0 }
      }

      fileprivate func acquireSlot() {
        concurrency.wait()
      }

      fileprivate func releaseSlot() {
        concurrency.signal()
      }

      deinit {
        stop()
      }
    }

    /// Bridges an async handler back to a worker thread servicing one socket request.
    private final class AnsweringBox: Sendable {
      private let value = OSAllocatedUnfairLock(initialState: Answer.failed(.transport))
      private let semaphore = DispatchSemaphore(value: 0)

      func complete(_ answer: Answer) {
        value.withLock { $0 = answer }
        semaphore.signal()
      }

      func wait() -> Answer {
        semaphore.wait()
        return value.withLock { $0 }
      }
    }

    internal static let invalidDescriptor: Int32 = -1
    internal static let serverReadTimeoutSeconds: TimeInterval = 2
    internal static let serverWriteTimeoutSeconds: TimeInterval = 5
    private static let maxConcurrentRequests = 4
    private static let transientAcceptBackoffSeconds: TimeInterval = 0.05
    private static let acceptThreadName = "fi.refineid.rapp-held-session"
    private static let activeListener = OSAllocatedUnfairLock<Listener?>(initialState: nil)

    /// Starts the app's peer-verified handoff listener in the shared app-group container.
    @preconcurrency
    @discardableResult
    public static func serve(
      answering handler: @escaping @Sendable (Request) async -> Answer
    ) -> Bool {
      guard
        let socketURL = defaultSocketURL(),
        let clientPolicy = productionPeerPolicy(
          expectedSigningIdentifier: tokenExtensionSigningIdentifier
        ),
        let serverPolicy = productionPeerPolicy(expectedSigningIdentifier: appSigningIdentifier)
      else {
        return false
      }
      let previous = activeListener.withLock { current -> Listener? in
        defer { current = nil }
        return current
      }
      previous?.stop()
      guard
        let listener = startListener(
          socketURL: socketURL,
          clientPolicy: clientPolicy,
          serverPolicy: serverPolicy,
          answering: handler
        )
      else {
        return false
      }
      activeListener.withLock { $0 = listener }
      return true
    }

    /// Sends `request` to the verified running app, returning nil when no verified app holds the socket.
    public static func ask(_ request: Request) -> Answer? {
      guard let socketURL = defaultSocketURL() else { return nil }
      return ask(
        request,
        socketURL: socketURL,
        serverPolicy: productionPeerPolicy(expectedSigningIdentifier: appSigningIdentifier)
      )
    }

    /// Starts a peer-verified listener at `socketURL` for production or test callers.
    internal static func startListener(
      socketURL: URL,
      clientPolicy: PeerPolicy,
      serverPolicy: PeerPolicy,
      answering handler: @escaping @Sendable (Request) async -> Answer
    ) -> Listener? {
      let directoryURL = socketURL.deletingLastPathComponent()
      guard
        let directoryIdentity = preparePinnedDirectory(directoryURL),
        let bound = bindListenerSocket(
          at: socketURL.path,
          directoryPath: directoryURL.path,
          directoryIdentity: directoryIdentity,
          serverPolicy: serverPolicy
        )
      else {
        return nil
      }
      let listener = Listener(
        descriptor: bound.descriptor,
        socketPath: socketURL.path,
        socketIdentity: bound.identity
      )
      let thread = Thread {
        acceptLoop(
          listener: listener,
          clientPolicy: clientPolicy,
          answering: handler
        )
      }
      thread.name = acceptThreadName
      thread.start()
      return listener
    }

    /// Sends `request` to `socketURL` after verifying the server peer's kernel audit-token identity.
    internal static func ask(
      _ request: Request,
      socketURL: URL,
      serverPolicy: PeerPolicy?
    ) -> Answer? {
      guard let payload = request.encoded() else { return .failed(.protocolFailure) }
      guard let serverPolicy, let address = makeSocketAddress(path: socketURL.path) else {
        return nil
      }
      let clientSocket = makeConfiguredSocket(
        readTimeout: answerWaitSeconds,
        writeTimeout: sendTimeoutSeconds
      )
      guard clientSocket != invalidDescriptor else { return .failed(.transport) }
      defer { _ = Darwin.close(clientSocket) }
      guard
        connectSocket(clientSocket, to: address, timeoutSeconds: sendTimeoutSeconds),
        verifyPeer(of: clientSocket, satisfying: serverPolicy)
      else {
        return nil
      }
      return exchangePayload(payload, over: clientSocket)
    }

    private static func exchangePayload(_ payload: Data, over socket: Int32) -> Answer {
      switch writeFramed(payload, to: socket) {
      case .completed:
        break
      case .timedOut:
        return .failed(.timedOut)
      case .disconnected, .failed:
        return .failed(.transport)
      }
      switch readFramed(from: socket) {
      case .message(let reply):
        return Answer(encoded: reply) ?? .failed(.protocolFailure)
      case .timedOut:
        return .failed(.timedOut)
      case .endOfStream, .failed:
        return .failed(.transport)
      }
    }

    private static func acceptLoop(
      listener: Listener,
      clientPolicy: PeerPolicy,
      answering handler: @escaping @Sendable (Request) async -> Answer
    ) {
      while listener.currentDescriptor() != invalidDescriptor {
        let listenSocket = listener.currentDescriptor()
        guard listenSocket != invalidDescriptor else { return }
        let clientSocket = Darwin.accept(listenSocket, nil, nil)
        if clientSocket == invalidDescriptor {
          let acceptError = errno
          guard shouldContinueAccepting(after: acceptError, listener: listener) else { return }
          continue
        }
        guard
          configureAcceptedSocket(clientSocket),
          verifyPeer(of: clientSocket, satisfying: clientPolicy)
        else {
          _ = Darwin.close(clientSocket)
          continue
        }
        listener.acquireSlot()
        DispatchQueue.global(qos: .userInitiated).async {
          defer {
            _ = Darwin.close(clientSocket)
            listener.releaseSlot()
          }
          handleVerifiedClient(clientSocket, answering: handler)
        }
      }
    }

    private static func shouldContinueAccepting(
      after acceptError: Int32,
      listener: Listener
    ) -> Bool {
      guard listener.currentDescriptor() != invalidDescriptor else { return false }
      if acceptError == EINTR || acceptError == ECONNABORTED {
        return true
      }
      if acceptError == EBADF || acceptError == EINVAL || acceptError == ENOTSOCK {
        return false
      }
      Thread.sleep(forTimeInterval: transientAcceptBackoffSeconds)
      return listener.currentDescriptor() != invalidDescriptor
    }

    private static func handleVerifiedClient(
      _ clientSocket: Int32,
      answering handler: @escaping @Sendable (Request) async -> Answer
    ) {
      guard
        case .message(let data) = readFramed(from: clientSocket),
        let request = Request(encoded: data)
      else {
        return
      }
      let box = AnsweringBox()
      Task {
        box.complete(await handler(request))
      }
      guard let encoded = box.wait().encoded() else { return }
      _ = writeFramed(encoded, to: clientSocket)
    }
  }
#endif
