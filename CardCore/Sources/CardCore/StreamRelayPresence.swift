// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Watches whether one named stream-transport service is on the network.
  ///
  /// A one-shot browser reports the first find and stops caring. A requester
  /// that has already published a borrowed identity has to know when that
  /// service leaves, so the identity can leave with it.
  public final class StreamRelayPresence: @unchecked Sendable {
    /// The primary Bonjour service name this watcher browses for.
    public var name: String { matchingNames.first ?? "" }
    /// The set of Bonjour service names this watcher browses for, or what
    /// its record classifier follows.
    public let matchingNames: Set<String>
    /// Names the holder a published record belongs to, or nil when the
    /// record is not one this watcher follows.
    private let classify: (@Sendable ([String: String]) -> String?)?
    private let onChange: @Sendable (Bool, String?) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.stream-presence")
    private var browser: NWBrowser?
    private var isPresent = false
    private var currentMatchedName: String?
    private var hasDelivered = false

    /// Reports presence of any service published under `names`.
    @preconcurrency
    public init(
      matching names: Set<String>,
      onChange: @escaping @Sendable (Bool, String?) -> Void
    ) {
      self.matchingNames = names
      self.classify = nil
      self.onChange = onChange
    }

    /// Reports presence of any service whose discovery attributes
    /// `classify` names; the name it returns travels with the change.
    /// `following` names what the classifier looks for, so an owner can
    /// tell whether a running watcher still matches.
    @preconcurrency
    public init(
      following: Set<String>,
      classifyingRecord classify: @escaping @Sendable ([String: String]) -> String?,
      onChange: @escaping @Sendable (Bool, String?) -> Void
    ) {
      self.matchingNames = following
      self.classify = classify
      self.onChange = onChange
    }

    /// Reports presence of the service published under `name`.
    @preconcurrency
    public convenience init(
      matching name: String,
      onChange: @escaping @Sendable (Bool) -> Void
    ) {
      self.init(matching: [name]) { present, _ in
        onChange(present)
      }
    }

    /// Starts browsing.
    public func start() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let descriptor: NWBrowser.Descriptor =
        classify == nil
        ? .bonjour(type: StreamRelayListener.serviceType, domain: nil)
        : .bonjourWithTXTRecord(type: StreamRelayListener.serviceType, domain: nil)
      let made = NWBrowser(for: descriptor, using: parameters)
      made.browseResultsChangedHandler = { [weak self] results, _ in
        self?.apply(results)
      }
      browser = made
      made.start(queue: queue)
    }

    /// Stops browsing.
    public func cancel() {
      queue.async {
        self.browser?.cancel()
        self.browser = nil
      }
    }

    private func matchedName(in results: Set<NWBrowser.Result>) -> String? {
      for result in results {
        if let classify {
          guard case .bonjour(let record) = result.metadata,
            let holder = classify(record.dictionary)
          else { continue }
          return holder
        }
        guard case .service(let serviceName, _, _, _) = result.endpoint else {
          continue
        }
        if matchingNames.contains(serviceName) {
          return serviceName
        }
      }
      return nil
    }

    private func apply(_ results: Set<NWBrowser.Result>) {
      guard !matchingNames.isEmpty || classify != nil else {
        if isPresent {
          isPresent = false
          currentMatchedName = nil
          onChange(false, nil)
        }
        return
      }
      let matchedName = matchedName(in: results)
      let found = matchedName != nil
      if !hasDelivered {
        hasDelivered = true
        isPresent = found
        currentMatchedName = matchedName
        if found {
          onChange(true, matchedName)
        }
        return
      }
      guard found != isPresent || matchedName != currentMatchedName else { return }
      isPresent = found
      currentMatchedName = matchedName
      onChange(found, matchedName)
    }
  }
#endif
