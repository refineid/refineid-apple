// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodians in pairing mode a requester tries with one typed code
/// (RAPP v26.10.29 §4.2, "Trying Each Custodian in Pairing Mode").
///
/// Nothing a custodian advertises tells which one shows the typed code, so
/// the requester tries them in turn. A candidate is an endpoint discovery
/// found in pairing mode: a `mode=pairing` service instance, or a BLE
/// peripheral of the RAPP service, which shows its mode only by serving an
/// offer or a `pairing-busy`. A custodian that answers busy is asked again
/// after its wait, quietly, within the connection limit.
///
/// One ledger serves one typed code; a new code starts a new ledger. It
/// opens each endpoint once, and again after each busy answer once the
/// endpoint's wait has passed and no other endpoint waits to be opened; it
/// opens at most ``PairingCandidateLimit/connections`` connections in all,
/// reopenings included, one at a time; it lets CPace run at most once per
/// `offer_id`, so a custodian found on two transports receives one guess;
/// and it reports the code as not accepted only once every custodian tried
/// refused it, a custodian still busy at the connection limit counting as
/// one that refused it. `Endpoint` is the platform's name for an endpoint.
/// No outcome names one, and the ledger holds no code.
internal struct PairingCandidates<Endpoint: Equatable> {
  /// Where the tries of one typed code stand.
  private enum Phase {
    /// No pairing connection is open.
    case closed
    /// A pairing connection is open and no CPace runs on it yet.
    case opened
    /// CPace runs on the open connection's offer.
    case trying
    /// A custodian's `T_B` verified: it holds the code.
    case accepted
    /// Every custodian tried refused the code, or answered busy at the
    /// connection limit, and no endpoint is left.
    case notAccepted
  }

  /// Where one endpoint stands for the typed code.
  private enum Status: Equatable {
    /// Found and not yet opened.
    case waiting
    /// The pairing connection to it is open.
    case open
    /// Its last answer was `pairing-busy`: it is opened again no sooner
    /// than this monotonic time, after every endpoint still waiting.
    case deferred(notBefore: UInt64)
    /// Its connection closed without a busy answer; it is not opened again
    /// for this code.
    case done
  }

  /// One endpoint found in pairing mode and where it stands.
  private struct Candidate {
    let endpoint: Endpoint
    var status: Status
  }

  /// Endpoints found, in the order found.
  private var candidates: [Candidate] = []
  /// Pairing connections opened, reopenings included.
  private var openings = 0
  /// The `offer_id`s CPace ran on.
  private var tried: [Data] = []
  /// Whether any custodian answered `pairing-busy` for this code.
  private var busyAnswered = false
  private var phase = Phase.closed

  /// Whether the code is accepted or refused.
  private var isSettled: Bool {
    switch phase {
    case .accepted, .notAccepted:
      true

    case .closed, .opened, .trying:
      false
    }
  }

  /// The ledger of a code the user has just submitted.
  internal init() {
    // Nothing found, opened or tried yet.
  }

  /// Records an endpoint discovery found in pairing mode.
  ///
  /// An endpoint already recorded, one beyond the limit, and one found once
  /// the code is accepted or refused are not tried with this code.
  internal mutating func found(_ endpoint: Endpoint) {
    guard !isSettled, candidates.count < PairingCandidateLimit.connections,
      !candidates.contains(where: { $0.endpoint == endpoint })
    else { return }
    candidates.append(Candidate(endpoint: endpoint, status: .waiting))
  }

  /// The next endpoint to open a pairing connection to at the monotonic
  /// time `nowMilliseconds`: the first found and not yet opened, otherwise
  /// the one that answered busy whose wait passed first.
  ///
  /// An endpoint whose wait has not passed is not handed out; the answer
  /// then names the earliest time one will be.
  ///
  /// - Throws: ``CandidateError/connectionOpen`` while a pairing connection
  ///   is open, and ``CandidateError/settled`` once the code is accepted or
  ///   refused.
  internal mutating func nextEndpoint(
    nowMilliseconds: UInt64
  ) throws(CandidateError) -> NextEndpoint<Endpoint> {
    switch phase {
    case .closed:
      break

    case .opened, .trying:
      throw .connectionOpen

    case .accepted, .notAccepted:
      throw .settled
    }
    guard openings < PairingCandidateLimit.connections else { return .exhausted }
    let index: Int
    if let waiting = candidates.firstIndex(where: { $0.status == .waiting }) {
      index = waiting
    } else if let deferred = earliestDeferred() {
      guard deferred.notBefore <= nowMilliseconds else { return .notBefore(deferred.notBefore) }
      index = deferred.index
    } else {
      return .exhausted
    }
    candidates[index].status = .open
    openings += 1
    phase = .opened
    return .open(candidates[index].endpoint)
  }

  /// Admits the offer the open connection served, before CPace step 1.
  ///
  /// - Throws: ``CandidateError/offerAlreadyTried`` when CPace already ran
  ///   on this `offer_id` with the code, ``CandidateError/noConnection`` when
  ///   no connection awaits an offer, and ``CandidateError/settled`` once the
  ///   code is accepted or refused. The caller closes the connection and
  ///   calls ``closed()``.
  internal mutating func beginTry(_ offer: PairingOffer) throws(CandidateError) {
    switch phase {
    case .opened:
      break

    case .closed, .trying:
      throw .noConnection

    case .accepted, .notAccepted:
      throw .settled
    }
    guard !tried.contains(offer.offerIdentifier) else { throw .offerAlreadyTried }
    tried.append(offer.offerIdentifier)
    phase = .trying
  }

  /// The open connection closed without its custodian taking the code.
  ///
  /// The connection was refused or closed, it served no offer or one the
  /// requester rejects or already tried, CPace step 2 did not arrive within
  /// the attempt deadline, or `T_B` did not verify. The endpoint is not
  /// opened again for this code.
  ///
  /// - Throws: ``CandidateError/noConnection`` when no connection is open,
  ///   and ``CandidateError/settled`` once the code is accepted or refused.
  internal mutating func closed() throws(CandidateError) -> NextCandidate {
    try endConnection(leaving: .done)
    return afterConnection(.tryNext)
  }

  /// The open connection's custodian answered `pairing-busy` at the
  /// monotonic time `nowMilliseconds`, asking for a wait of
  /// `retryAfterMilliseconds`: at bootstrap, in place of CPace step 2, or,
  /// on BLE, by refusing step 1 and then serving its offer (a wait of zero).
  ///
  /// A busy answer is not a try: a CPace begun on the connection gives its
  /// `offer_id` back, and the endpoint is kept for another opening no
  /// sooner than `nowMilliseconds + retryAfterMilliseconds`.
  ///
  /// - Throws: ``CandidateError/noConnection`` when no connection is open,
  ///   and ``CandidateError/settled`` once the code is accepted or refused.
  internal mutating func busy(
    retryAfterMilliseconds: UInt64, nowMilliseconds: UInt64
  ) throws(CandidateError) -> NextCandidate {
    let trying = phase == .trying
    let (notBefore, overflow) = nowMilliseconds.addingReportingOverflow(retryAfterMilliseconds)
    try endConnection(leaving: .deferred(notBefore: overflow ? UInt64.max : notBefore))
    if trying {
      tried.removeLast()
    }
    busyAnswered = true
    return afterConnection(.deferred)
  }

  /// The custodian tried proved it holds the code: its `T_B` verified.
  ///
  /// No other custodian is tried with the code.
  ///
  /// - Throws: ``CandidateError/noTry`` when no CPace runs, and
  ///   ``CandidateError/settled`` once the code is accepted or refused.
  internal mutating func accepted() throws(CandidateError) {
    switch phase {
    case .trying:
      phase = .accepted

    case .closed, .opened:
      throw .noTry

    case .accepted, .notAccepted:
      throw .settled
    }
  }

  /// The deferred endpoint whose wait passes first, with that time.
  private func earliestDeferred() -> (notBefore: UInt64, index: Int)? {
    var earliest: (notBefore: UInt64, index: Int)?
    for (index, candidate) in candidates.enumerated() {
      guard case .deferred(let notBefore) = candidate.status else { continue }
      if let current = earliest, current.notBefore <= notBefore { continue }
      earliest = (notBefore, index)
    }
    return earliest
  }

  /// Closes the open connection, leaving its endpoint at `status`.
  private mutating func endConnection(leaving status: Status) throws(CandidateError) {
    switch phase {
    case .opened, .trying:
      break

    case .closed:
      throw .noConnection

    case .accepted, .notAccepted:
      throw .settled
    }
    if let open = candidates.firstIndex(where: { $0.status == .open }) {
      candidates[open].status = status
    }
    phase = .closed
  }

  /// What follows a closed connection: `next` while an endpoint is left to
  /// open within the connection limit, otherwise the report.
  ///
  /// A search that tried no custodian and received no busy answer found
  /// none in pairing mode; otherwise the code is not accepted, a custodian
  /// that answered busy counting as one that refused it.
  private mutating func afterConnection(_ next: NextCandidate) -> NextCandidate {
    let left = candidates.contains { $0.status != .done }
    if left, openings < PairingCandidateLimit.connections {
      return next
    }
    if tried.isEmpty, !busyAnswered {
      return .noneTried
    }
    phase = .notAccepted
    return .notAccepted
  }
}
