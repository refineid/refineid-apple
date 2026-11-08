// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// One session that delivers a requester's `pairing_revoked` close for a
  /// pairing in its revocation backlog (RAPP v26.11.2 §4.6 item 6).
  ///
  /// The owner opens one each time the custodian appears for the pairing,
  /// never on a timer. The session completes the handshake, sends the close
  /// as its first message and waits for the echo (§7.1 item 7). It offers no
  /// identity and starts no operation.
  public enum RappRevocationNotice {
    /// How the session for a forgotten pairing ended.
    public enum Delivery: Sendable, Equatable {
      /// The custodian echoed the close, or closed with its own
      /// `pairing_revoked`: it forgot the pairing, so the requester destroys
      /// the key and the record now.
      case acknowledged
      /// The close left without its echo: it is not known to have arrived,
      /// and the pairing stays in the backlog until the custodian next
      /// appears.
      case unacknowledged
      /// The session ended before the close left: the custodian was not
      /// reached over this route.
      case unreached
    }

    /// The delivery's answer, settled once, by the session's end.
    private final class Outcome: @unchecked Sendable {
      private let lock = NSLock()
      private var settled: Delivery?
      private var waiting: CheckedContinuation<Delivery, Never>?

      fileprivate var delivery: Delivery {
        get async {
          await withCheckedContinuation { continuation in
            lock.lock()
            guard let settled else {
              waiting = continuation
              lock.unlock()
              return
            }
            lock.unlock()
            continuation.resume(returning: settled)
          }
        }
      }

      fileprivate func settle(_ delivery: Delivery) {
        lock.lock()
        guard settled == nil else {
          lock.unlock()
          return
        }
        settled = delivery
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(returning: delivery)
      }
    }

    /// Opens one session for `pair`, a forgotten record, along `route` with
    /// `policy`, and answers how it ended.
    public static func deliver(
      _ pair: RappPairRecord,
      route: RappHeldRequesterSession.Route,
      policy: RappRequesterPolicy = .interactive
    ) async -> Delivery {
      guard pair.metadata().forgottenAtMs != nil else { return .unreached }
      let outcome = Outcome()
      let session = RappHeldRequesterSession(pair: pair, route: route, policy: policy) { report in
        guard case .closed(let reason) = report else { return }
        if reason == .handshake(.revocationNoticeDelivered) || reason.peerRevokedPairing {
          outcome.settle(.acknowledged)
        } else if reason == .handshake(.revocationNoticeUnacknowledged) {
          outcome.settle(.unacknowledged)
        } else {
          outcome.settle(.unreached)
        }
      }
      session.start()
      return await outcome.delivery
    }
  }
#endif
