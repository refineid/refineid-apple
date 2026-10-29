// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import RappEngine

extension RappPairingModel {
  internal func makeTransport(
    relay: PairingRelay
  ) -> RappClosureFrameTransport {
    RappClosureFrameTransport(
      sender: { [weak relay] frame in
        guard let relay else {
          throw PersistentRelayTransportError.disconnected
        }
        try relay.send(frame)
      },
      closer: { [weak relay] in relay?.cancel() },
      connectionEnder: { [weak relay] frame in
        relay?.endConnection(answering: frame) ?? false
      }
    )
  }
}
