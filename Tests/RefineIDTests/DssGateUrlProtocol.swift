// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation

  @testable import RefineIDTestHost

  /// Answers the signing network's requests from the synthetic authorities.
  ///
  /// It answers in memory for the timestamp authority the app is
  /// configured with and for the addresses the synthetic certificates
  /// publish. Any other request is refused, so nothing reaches a
  /// network.
  internal final class DssGateUrlProtocol: URLProtocol {
    /// The authorities answering; set for the gate's duration.
    nonisolated(unsafe) internal static var authorities: DssGateAuthorities?

    private static let okStatus = 200
    private static let notFoundStatus = 404
    private static let httpVersion = "HTTP/1.1"
    private static let readChunk = 4_096

    override internal static func canInit(with request: URLRequest) -> Bool {
      guard Self.authorities != nil, let host = request.url?.host else { return false }
      return host == DssGateAuthorities.host
        || request.url?.absoluteString == TimestampClient.authority
    }

    override internal static func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    private static func answer(to address: String, body: Data) -> Data? {
      guard let authorities = Self.authorities else { return nil }
      switch address {
      case TimestampClient.authority:
        return try? authorities.timestampResponse(to: body)

      case DssGateAuthorities.revocationListAddress:
        return try? authorities.revocationList()

      default:
        return nil
      }
    }

    /// A POST body as URLSession hands it to a protocol: as a stream.
    private static func body(of request: URLRequest) -> Data {
      if let body = request.httpBody { return body }
      guard let stream = request.httpBodyStream else { return Data() }
      stream.open()
      defer { stream.close() }
      var body = Data()
      var buffer = [UInt8](repeating: .zero, count: Self.readChunk)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > .zero else { break }
        body.append(contentsOf: buffer.prefix(read))
      }
      return body
    }

    override internal func startLoading() {
      let answer = Self.answer(
        to: request.url?.absoluteString ?? "",
        body: Self.body(of: request)
      )
      guard let url = request.url,
        let response = HTTPURLResponse(
          url: url,
          statusCode: answer == nil ? Self.notFoundStatus : Self.okStatus,
          httpVersion: Self.httpVersion,
          headerFields: nil
        )
      else { return }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: answer ?? Data())
      client?.urlProtocolDidFinishLoading(self)
    }

    override internal func stopLoading() {
      // Every answer is complete when startLoading returns.
    }
  }

#endif
