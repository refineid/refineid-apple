// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine

/// What the custodian last told each session it serves in `card.status`
/// (RAPP v26.10.29 §8.4 item 1, STPA CC-61 and CC-81).
///
/// A session hears the custodian's word once right after `session.ready`,
/// and again whenever the word changed since that session was last told: a
/// card arriving, leaving or changing, or a contact card reader attached or
/// detached. No session hears the same word twice in a row.
internal struct CardStatusReports<Session: Hashable> {
  /// What each session was last told.
  private var told: [Session: RappCardStatus] = [:]

  /// The sessions among `established` that must hear `status` now, each
  /// recorded as told it.
  internal mutating func sessions(
    toTell status: RappCardStatus, among established: [Session]
  ) -> [Session] {
    var due: [Session] = []
    for session in established where told[session] != status {
      told[session] = status
      due.append(session)
    }
    return due
  }

  /// Forgets what `session` was told, so it hears the word next: on its
  /// `session.ready`, and once it ended.
  internal mutating func forget(_ session: Session) {
    told[session] = nil
  }
}
