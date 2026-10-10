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
    /// What a published record says about a followed holder.
    public enum Classification: Sendable, Equatable {
      /// A session record naming this holder.
      case holder(String)
      /// A verified withdrawn record for this holder.
      case withdrawn(String)
    }

    /// The primary Bonjour service name this watcher browses for.
    public var name: String { matchingNames.first ?? "" }
    /// The set of Bonjour service names this watcher browses for, or what
    /// its record classifier follows.
    public let matchingNames: Set<String>

    /// Classifies a record published under an instance name, or nil when
    /// the record is not one this watcher follows.
    private let classify: (@Sendable ([String: String], String) -> Classification?)?
    private let onChange: @Sendable (Bool, String?) -> Void
    private let onWithdrawn: @Sendable (String) -> Void
    private var currentInstance: String?
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
      self.onWithdrawn = { _ in
        // A watcher following names has no records to withdraw.
      }
    }

    /// Reports presence of any service whose discovery attributes
    /// `classify` names; the name it returns travels with the change.
    /// `following` names what the classifier looks for, so an owner can
    /// tell whether a running watcher still matches.
    ///
    /// A verified withdrawn record on the instance the holder was found
    /// under reports through `onWithdrawn` instead, at once; a holder that
    /// merely vanishes still reports through `onChange`.
    @preconcurrency
    public init(
      following: Set<String>,
      classifyingRecord classify:
        @escaping @Sendable ([String: String], String) -> Classification?,
      onChange: @escaping @Sendable (Bool, String?) -> Void,
      onWithdrawn: @escaping @Sendable (String) -> Void
    ) {
      self.matchingNames = following
      self.classify = classify
      self.onChange = onChange
      self.onWithdrawn = onWithdrawn
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

    private func matchedName(in results: Set<NWBrowser.Result>) -> (name: String, instance: String)?
    {
      for result in results {
        guard case .service(let serviceName, _, _, _) = result.endpoint else {
          continue
        }
        if let classify {
          guard case .bonjour(let record) = result.metadata,
            case .holder(let holder)? = classify(record.dictionary, serviceName)
          else { continue }
          return (holder, serviceName)
        }
        if matchingNames.contains(serviceName) {
          return (serviceName, serviceName)
        }
      }
      return nil
    }

    /// The holder a verified withdrawn record names on the instance the
    /// holder was last found under.
    private func withdrawal(in results: Set<NWBrowser.Result>) -> String? {
      guard let classify, let currentInstance else { return nil }
      for result in results {
        guard case .service(let serviceName, _, _, _) = result.endpoint,
          serviceName == currentInstance,
          case .bonjour(let record) = result.metadata,
          case .withdrawn(let holder)? = classify(record.dictionary, serviceName)
        else { continue }
        return holder
      }
      return nil
    }

    private func apply(_ results: Set<NWBrowser.Result>) {
      if let withdrawn = withdrawal(in: results) {
        isPresent = false
        currentMatchedName = nil
        currentInstance = nil
        onWithdrawn(withdrawn)
        return
      }
      guard !matchingNames.isEmpty || classify != nil else {
        if isPresent {
          isPresent = false
          currentMatchedName = nil
          onChange(false, nil)
        }
        return
      }
      let match = matchedName(in: results)
      let matchedName = match?.name
      let found = matchedName != nil
      if let match {
        currentInstance = match.instance
      }
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
