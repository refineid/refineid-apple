// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Browses for the custodians of a requester's forgotten pairings and
  /// reports each appearance (RAPP v26.11.2 §4.6 item 6, §8.3).
  ///
  /// A pairing appears when a `mode=session` record carrying its discovery
  /// hint is listed while none was before. Every pairing in sight is
  /// followed on its own, so several forgotten pairings resolve side by
  /// side. A record that stays listed is not a new appearance.
  public final class RappRevocationBacklogBrowser: @unchecked Sendable {
    /// What the browser follows, so an owner can tell whether a running
    /// browser still matches its backlog.
    public let following: Set<String>

    private let classify: @Sendable ([String: String], String) -> String?
    private let onAppeared: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.revocation-backlog")
    private var browser: NWBrowser?
    private var inSight: Set<String> = []

    /// Follows `following`; `classify` names the followed pairing whose
    /// hint a record published under an instance name carries, or nil, and
    /// `onAppeared` hears each pairing that comes into sight, on the
    /// browser's queue.
    @preconcurrency
    public init(
      following: Set<String>,
      classifyingRecord classify: @escaping @Sendable ([String: String], String) -> String?,
      onAppeared: @escaping @Sendable (String) -> Void
    ) {
      self.following = following
      self.classify = classify
      self.onAppeared = onAppeared
    }

    /// Starts browsing.
    public func start() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let made = NWBrowser(
        for: .bonjourWithTXTRecord(type: StreamRelayListener.serviceType, domain: nil),
        using: parameters)
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

    private func apply(_ results: Set<NWBrowser.Result>) {
      var listed: Set<String> = []
      for result in results {
        guard case .service(let serviceName, _, _, _) = result.endpoint,
          case .bonjour(let record) = result.metadata,
          let pairing = classify(record.dictionary, serviceName)
        else { continue }
        listed.insert(pairing)
      }
      let appeared = listed.subtracting(inSight)
      inSight = listed
      for pairing in appeared.sorted() {
        onAppeared(pairing)
      }
    }
  }
#endif
