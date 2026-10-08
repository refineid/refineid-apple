// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Finds a card holder publishing the stream transport.
  ///
  /// This browses with the plain name service rather than the nearby
  /// framework. Both are fed by the same records, but only one of them
  /// hands the result to the app on a device whose system generation
  /// differs from its peer's.
  public final class StreamRelayBrowser: @unchecked Sendable {
    private let onFound: @Sendable (NWEndpoint) -> Void
    private let name: String?
    private let attributes: [String: String]
    private let recordMatches: (@Sendable ([String: String]) -> Bool)?
    private let queue = DispatchQueue(label: "fi.refineid.stream-browser")
    private var browser: NWBrowser?
    private var reported = false

    /// Reports a published requester to one owner.
    ///
    /// A network carries more than one of these, so a caller that knows
    /// which it wants says so; a caller that does not takes the first.
    @preconcurrency
    public init(
      matching name: String? = nil,
      onFound: @escaping @Sendable (NWEndpoint) -> Void
    ) {
      self.name = name
      self.attributes = [:]
      self.recordMatches = nil
      self.onFound = onFound
    }

    /// Reports the first published service whose discovery attributes
    /// carry every given key and value.
    @preconcurrency
    public init(
      matchingAttributes attributes: [String: String],
      onFound: @escaping @Sendable (NWEndpoint) -> Void
    ) {
      self.name = nil
      self.attributes = attributes
      self.recordMatches = nil
      self.onFound = onFound
    }

    /// Reports the first published service whose discovery attributes
    /// satisfy `recordMatches`.
    @preconcurrency
    public init(
      matchingRecord recordMatches: @escaping @Sendable ([String: String]) -> Bool,
      onFound: @escaping @Sendable (NWEndpoint) -> Void
    ) {
      self.name = nil
      self.attributes = [:]
      self.recordMatches = recordMatches
      self.onFound = onFound
    }

    /// Starts browsing.
    public func start() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let descriptor: NWBrowser.Descriptor =
        attributes.isEmpty && recordMatches == nil
        ? .bonjour(type: StreamRelayListener.serviceType, domain: nil)
        : .bonjourWithTXTRecord(type: StreamRelayListener.serviceType, domain: nil)
      let made = NWBrowser(for: descriptor, using: parameters)
      made.browseResultsChangedHandler = { [weak self] results, _ in
        guard let self, let wanted = results.first(where: matches) else { return }
        queue.async { [weak self] in
          guard let self, !reported else { return }
          reported = true
          onFound(wanted.endpoint)
        }
      }
      browser = made
      made.start(queue: queue)
    }

    private func matches(_ result: NWBrowser.Result) -> Bool {
      if let name {
        guard case .service(let serviceName, _, _, _) = result.endpoint else { return false }
        return serviceName == name
      }
      guard !attributes.isEmpty || recordMatches != nil else { return true }
      guard case .bonjour(let record) = result.metadata else { return false }
      if let recordMatches {
        return recordMatches(record.dictionary)
      }
      return attributes.allSatisfy { key, value in record[key] == value }
    }

    /// Stops browsing.
    public func cancel() {
      queue.async {
        self.browser?.cancel()
        self.browser = nil
      }
    }
  }
#endif
