// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// The card's exclusive session with the application selected and PACE
  /// done on it, kept between operations.
  ///
  /// `@unchecked Sendable`: both members are set once and read from the
  /// holder's own serial order.
  internal final class RappHeldCardChannel: @unchecked Sendable {
    internal let session: SmartCardChannel.OpenSession
    internal let operations: CardOperations

    internal init(session: SmartCardChannel.OpenSession, operations: CardOperations) {
      self.session = session
      self.operations = operations
    }
  }
#endif
