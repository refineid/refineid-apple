// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension SigningNetwork {
  /// A memory-bounded body accumulator for one HTTP response.
  internal struct BoundedResponseBody {
    /// The maximum body size accepted from the server.
    private let limit: Int

    /// Bytes retained so far; this never grows beyond `limit`.
    internal private(set) var data = Data()

    /// Creates an empty response accumulator for one known size limit.
    internal init(limit: Int) {
      self.limit = limit
    }

    /// Appends one incoming chunk if it fits.
    ///
    /// A false result means the caller received the byte at `limit + 1`
    /// and must cancel its task.
    internal mutating func append(_ chunk: Data) -> Bool {
      guard chunk.count <= limit - data.count else { return false }
      data.append(chunk)
      return true
    }
  }

  /// Receives a response incrementally and cancels as soon as its body
  /// exceeds the caller's size limit.
  internal final class BoundedResponseCollector: NSObject,
    URLSessionDataDelegate, @unchecked Sendable
  {
    private let redirects: RedirectGate
    private let lock = NSLock()
    private var body: BoundedResponseBody
    private var continuation: CheckedContinuation<Data, Error>?
    private var failure: Error?
    private var receivedResponse = false
    private var finished = false

    /// Creates a collector with one redirect policy and one body limit.
    internal init(
      initial: URLRequest,
      endpoint: Endpoint,
      carriesCredentials: Bool,
      limit: Int
    ) {
      redirects = RedirectGate(
        initial: initial,
        endpoint: endpoint,
        carriesCredentials: carriesCredentials
      )
      body = BoundedResponseBody(limit: limit)
    }

    /// Starts one data task and resumes only after completion or rejection.
    internal func response(
      using session: URLSession,
      request: URLRequest
    ) async throws -> Data {
      let task = session.dataTask(with: request)
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          lock.lock()
          self.continuation = continuation
          lock.unlock()
          task.resume()
        }
      } onCancel: {
        task.cancel()
      }
    }

    /// Forwards redirect decisions to the bounded request's redirect gate.
    internal func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @Sendable (URLRequest?) -> Void
    ) {
      redirects.urlSession(
        session,
        task: task,
        willPerformHTTPRedirection: response,
        newRequest: request,
        completionHandler: completionHandler
      )
    }

    /// Rejects an error status before its server body is accumulated.
    internal func urlSession(
      _ _: URLSession,
      dataTask _: URLSessionDataTask,
      didReceive response: URLResponse,
      completionHandler: (URLSession.ResponseDisposition) -> Void
    ) {
      let statusFailure: Failure?
      if let http = response as? HTTPURLResponse,
        !SigningNetwork.successStatuses.contains(http.statusCode)
      {
        statusFailure = .httpStatus(http.statusCode)
      } else {
        statusFailure = nil
      }
      lock.lock()
      receivedResponse = true
      if failure == nil { failure = statusFailure }
      lock.unlock()
      completionHandler(statusFailure == nil ? .allow : .cancel)
    }

    /// Retains only chunks that stay within the body budget, then cancels
    /// immediately when the next chunk would contain byte `limit + 1`.
    internal func urlSession(
      _ _: URLSession,
      dataTask: URLSessionDataTask,
      didReceive data: Data
    ) {
      lock.lock()
      guard !finished, failure == nil else {
        lock.unlock()
        return
      }
      guard body.append(data) else {
        failure = Failure.unusableBody
        lock.unlock()
        dataTask.cancel()
        return
      }
      lock.unlock()
    }

    /// Finishes the async operation with the policy failure, transport
    /// failure, or bounded data that was collected.
    internal func urlSession(
      _ _: URLSession,
      task _: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      lock.lock()
      guard !finished else {
        lock.unlock()
        return
      }
      finished = true
      let pendingContinuation = self.continuation
      self.continuation = nil
      let collectedBody = self.body.data
      let recordedFailure = self.failure
      let hasResponse = self.receivedResponse
      lock.unlock()

      let result: Result<Data, Error>
      if let redirectFailure = redirects.redirectFailure {
        result = .failure(redirectFailure)
      } else if let recordedFailure {
        result = .failure(recordedFailure)
      } else if let error {
        result = .failure(error)
      } else if !hasResponse || collectedBody.isEmpty {
        result = .failure(Failure.unusableBody)
      } else {
        result = .success(collectedBody)
      }
      pendingContinuation?.resume(with: result)
    }
  }
}
