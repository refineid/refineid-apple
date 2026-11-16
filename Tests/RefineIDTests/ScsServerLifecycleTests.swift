// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import CardCore
  import Foundation
  import Network
  import Synchronization
  import XCTest

  @testable import RefineIDTestHost

  @MainActor
  internal final class ScsServerLifecycleTests: XCTestCase {
    #if FEATURE_SCS
      private final class BlockingSignBackend: ScsSigningBackend, @unchecked Sendable {
        let signEntered = DispatchSemaphore(value: 0)
        let releaseSign = DispatchSemaphore(value: 0)

        func certificateChain(for _: ScsSignPurpose) -> [Data] {
          [Data([0x30, 0x03, 0x02, 0x01, 0x01])]
        }

        func keyAlgorithm(for _: ScsSignPurpose) -> ScsKeyAlgorithm { .rsa }

        func sign(_: ScsSignRequest) -> Data {
          signEntered.signal()
          _ = releaseSign.wait(timeout: .now() + 5)
          return Data(repeating: 0xAA, count: 64)
        }
      }

      private static func ephemeralTcpParameters() -> NWParameters? {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        return parameters
      }

      private static func sampleQualifiedSignRequest() -> Data {
        let payload = Data(
          "{\"content\":\"ZGF0YQ==\",\"contentType\":\"data\",\"selector\":{\"keyusages\":[\"nonRepudiation\"]}}"
            .utf8)
        let head =
          "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nOrigin: https://dvv.fineid.fi\r\n"
          + "Content-Type: application/json\r\nContent-Length: \(payload.count)\r\n\r\n"
        return Data(head.utf8) + payload
      }

      nonisolated private static func sendAndRead(
        _ conn: NWConnection,
        payload: Data,
        finish: @escaping @Sendable (Result<String, any Error>) -> Void
      ) {
        conn.send(
          content: payload,
          completion: .contentProcessed { error in
            if let error {
              finish(.failure(error))
              return
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, err in
              if let data, !data.isEmpty {
                finish(.success(String(bytes: data, encoding: .utf8) ?? ""))
              } else if let err {
                finish(.failure(err))
              } else {
                finish(.success(""))
              }
            }
          }
        )
      }

      internal func testVersionStaysResponsiveWhileSignBlocksAndStopCancelsPrompt() async throws {
        let ready = expectation(description: "Listener ready")
        let stopped = expectation(description: "Listener stopped")
        let tokenCancelled = expectation(description: "Prompt cancellation token fired")
        let backend = BlockingSignBackend()
        let server = ScsServer(
          limits: ScsServerLimits(
            maximumConnections: 4, readTimeoutSeconds: 5, signTimeoutSeconds: 30),
          backend: backend,
          cardCancellationHook: { token, work in
            _ = token.installAbort { tokenCancelled.fulfill() }
            return work()
          },
          resetBackendHook: {
            // No-op in test.
          },
          makeParameters: Self.ephemeralTcpParameters,
          observeState: { state in
            if case .ready = state { ready.fulfill() }
            if case .cancelled = state { stopped.fulfill() }
          },
          onStatusFailure: { _ in
            // Status assertions live in testIdleReadTimeoutAndPortConflictSurfaceCleanly.
          }
        )
        server.start()
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(server.localPort)
        let fullSign = Self.sampleQualifiedSignRequest()
        let signClient = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        defer { signClient.cancel() }
        signClient.start(queue: .global())
        signClient.send(
          content: fullSign,
          completion: .contentProcessed { _ in
            // Request stays blocked inside signQueue until stop().
          }
        )
        XCTAssertEqual(backend.signEntered.wait(timeout: .now() + 5), .success)

        let versionAnswer = try await exchangeOverTcp(
          port: port,
          request: "GET /version HTTP/1.1\r\nHost: 127.0.0.1:53952\r\n\r\n"
        )
        XCTAssertTrue(versionAnswer.contains("HTTP/1.1 200 OK"))
        let secondSignAnswer = try await exchangeOverTcp(
          port: port,
          request: String(bytes: fullSign, encoding: .utf8) ?? ""
        )
        XCTAssertTrue(secondSignAnswer.contains("\"reasonCode\":403"))

        server.stop()
        backend.releaseSign.signal()
        await fulfillment(of: [tokenCancelled, stopped], timeout: 5)
        XCTAssertNil(server.localPort)
      }

      internal func testIdleReadTimeoutAndPortConflictSurfaceCleanly() async throws {
        let ready = expectation(description: "Listener ready")
        let server = ScsServer(
          limits: ScsServerLimits(
            maximumConnections: 2, readTimeoutSeconds: 0.2, signTimeoutSeconds: 5),
          backend: BlockingSignBackend(),
          cardCancellationHook: nil,
          resetBackendHook: {
            // No-op in test.
          },
          makeParameters: Self.ephemeralTcpParameters,
          observeState: { state in
            if case .ready = state { ready.fulfill() }
          },
          onStatusFailure: { _ in
            // Primary listener binds on an unused ephemeral port.
          }
        )
        server.start()
        await fulfillment(of: [ready], timeout: 5)
        let occupiedPort = try XCTUnwrap(server.localPort)
        defer { server.stop() }

        await assertIdleConnectionTimesOut(on: occupiedPort)
        await assertPortSquatReportsFailure(on: occupiedPort)
      }

      private func assertIdleConnectionTimesOut(on port: NWEndpoint.Port) async {
        let idleClosed = expectation(description: "Idle client closed by read timeout")
        let idleClient = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        defer { idleClient.cancel() }
        idleClient.stateUpdateHandler = { state in
          if case .ready = state {
            idleClient.receive(minimumIncompleteLength: 1, maximumLength: 16) { _, _, eof, err in
              if eof || err != nil { idleClosed.fulfill() }
            }
          }
        }
        idleClient.start(queue: .global())
        await fulfillment(of: [idleClosed], timeout: 5)
      }

      private func assertPortSquatReportsFailure(on occupiedPort: NWEndpoint.Port) async {
        let conflictReported = expectation(description: "Port squat status failure reported")
        let reported = Mutex<String?>(nil)
        let conflicting = ScsServer(
          limits: .standard,
          backend: BlockingSignBackend(),
          cardCancellationHook: nil,
          resetBackendHook: {
            // No-op in test.
          },
          makeParameters: {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = false
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: occupiedPort)
            return parameters
          },
          observeState: { _ in
            // Conflicting listener state is verified via onStatusFailure.
          },
          onStatusFailure: { message in
            guard let message else { return }
            let first = reported.withLock { slot -> Bool in
              guard slot == nil else { return false }
              slot = message
              return true
            }
            if first { conflictReported.fulfill() }
          }
        )
        conflicting.start()
        defer { conflicting.stop() }
        await fulfillment(of: [conflictReported], timeout: 5)
        XCTAssertNotNil(reported.withLock { $0 })
      }

      private func exchangeOverTcp(port: NWEndpoint.Port, request: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
          let conn = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
          let resumed = Mutex(false)
          let finish: @Sendable (Result<String, any Error>) -> Void = { result in
            let shouldResume = resumed.withLock { done -> Bool in
              guard !done else { return false }
              done = true
              return true
            }
            if shouldResume {
              conn.cancel()
              continuation.resume(with: result)
            }
          }
          conn.stateUpdateHandler = { state in
            if case .failed(let error) = state { finish(.failure(error)) }
            if case .ready = state {
              Self.sendAndRead(conn, payload: Data(request.utf8), finish: finish)
            }
          }
          conn.start(queue: .global())
        }
      }
    #else
      internal func testScsAppImplementationIsCompiledOutByDefault() {
        XCTAssertNil(NSClassFromString("RefineIDTestHost.ScsServer"))
        XCTAssertNil(NSClassFromString("RefineIDTestHost.ScsService"))
        XCTAssertNil(NSClassFromString("RefineID.ScsServer"))
        XCTAssertNil(NSClassFromString("RefineID.ScsService"))
      }
    #endif
  }
#endif
