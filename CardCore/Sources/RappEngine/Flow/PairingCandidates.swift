// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodians in pairing mode a requester tries with one typed code
/// (RAPP v26.10.22 §4.2, "Trying Each Custodian in Pairing Mode").
///
/// Nothing a custodian advertises tells which one shows the typed code, so
/// the requester tries them in turn. A candidate is an endpoint discovery
/// found in pairing mode: a `mode=pairing` service instance, or a BLE
/// peripheral of the RAPP service, which shows its mode only by serving an
/// offer.
///
/// One ledger serves one typed code; a new code starts a new ledger. It
/// opens each endpoint at most once and at most
/// ``PairingCandidateLimit/connections`` in all, one at a time; it lets
/// CPace run at most once per `offer_id`, so a custodian found on two
/// transports receives one guess; and it reports the code as not accepted
/// only once every custodian tried refused it. `Endpoint` is the platform's
/// name for an endpoint. No outcome names one, and the ledger holds no code.
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
    /// Every custodian tried refused the code and no endpoint is left.
    case notAccepted
  }

  /// Endpoints found, in the order found; the first `opened` were opened.
  private var endpoints: [Endpoint] = []
  private var opened = 0
  /// The `offer_id`s CPace ran on.
  private var tried: [Data] = []
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
    guard !isSettled, endpoints.count < PairingCandidateLimit.connections,
      !endpoints.contains(endpoint)
    else { return }
    endpoints.append(endpoint)
  }

  /// The next endpoint to open a pairing connection to, in the order found,
  /// or nil when every endpoint recorded is opened.
  ///
  /// - Throws: ``CandidateError/connectionOpen`` while a pairing connection
  ///   is open, and ``CandidateError/settled`` once the code is accepted or
  ///   refused.
  internal mutating func nextEndpoint() throws(CandidateError) -> Endpoint? {
    switch phase {
    case .closed:
      break

    case .opened, .trying:
      throw .connectionOpen

    case .accepted, .notAccepted:
      throw .settled
    }
    guard opened < endpoints.count else { return nil }
    let endpoint = endpoints[opened]
    opened += 1
    phase = .opened
    return endpoint
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

  /// The open connection closed without its custodian taking the code: the
  /// connection was refused or closed, it served no offer or one the
  /// requester rejects or already tried, CPace step 2 did not arrive within
  /// the attempt deadline, or `T_B` did not verify.
  ///
  /// - Throws: ``CandidateError/noConnection`` when no connection is open,
  ///   and ``CandidateError/settled`` once the code is accepted or refused.
  internal mutating func closed() throws(CandidateError) -> NextCandidate {
    switch phase {
    case .opened, .trying:
      break

    case .closed:
      throw .noConnection

    case .accepted, .notAccepted:
      throw .settled
    }
    if opened < endpoints.count {
      phase = .closed
      return .tryNext
    }
    if tried.isEmpty {
      phase = .closed
      return .noneTried
    }
    phase = .notAccepted
    return .notAccepted
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
}
