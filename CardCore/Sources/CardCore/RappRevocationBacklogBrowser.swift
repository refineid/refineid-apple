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
    private let queue = DispatchQueue(label: "fi.refineid.revocation-backlog")
    private var followed: Set<String>
    private var classify: @Sendable ([String: String], String) -> String?
    private var onAppeared: @Sendable (String) -> Void
    private var browser: NWBrowser?
    private var listed: Set<NWBrowser.Result> = []
    private var hasListing = false
    private var inSight: Set<String> = []

    /// What the browser follows, so an owner can tell whether a running
    /// browser still matches its backlog.
    public var following: Set<String> {
      queue.sync { followed }
    }

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
      self.followed = following
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

    /// Follows `following` from now on, without starting over: a pairing
    /// still followed whose record stays listed is not a new appearance,
    /// and one newly followed whose record is listed already appears now.
    @preconcurrency
    public func update(
      following: Set<String>,
      classifyingRecord classify: @escaping @Sendable ([String: String], String) -> String?,
      onAppeared: @escaping @Sendable (String) -> Void
    ) {
      queue.sync {
        followed = following
        self.classify = classify
        self.onAppeared = onAppeared
        inSight.formIntersection(following)
      }
      queue.async { [weak self] in
        guard let self, hasListing else { return }
        apply(listed)
      }
    }

    /// Stops browsing.
    public func cancel() {
      queue.async {
        self.browser?.cancel()
        self.browser = nil
      }
    }

    /// Reads `results` on the browser's queue.
    private func apply(_ results: Set<NWBrowser.Result>) {
      listed = results
      hasListing = true
      var named: Set<String> = []
      for result in results {
        guard case .service(let serviceName, _, _, _) = result.endpoint,
          case .bonjour(let record) = result.metadata,
          let pairing = classify(record.dictionary, serviceName)
        else { continue }
        named.insert(pairing)
      }
      sighted(named)
    }

    /// Takes the followed pairings whose records are listed now.
    ///
    /// Each one not in sight before appears. Internal so a test can hand
    /// listings in without a network; it runs on the browser's queue
    /// otherwise.
    internal func sighted(_ named: Set<String>) {
      let current = named.intersection(followed)
      let appeared = current.subtracting(inSight)
      inSight = current
      for pairing in appeared.sorted() {
        onAppeared(pairing)
      }
    }
  }
#endif
