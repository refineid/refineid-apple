// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore
@testable import RefineIDTestHost

/// Serves bytes by location and counts the fetches; an offline
/// network fails every fetch as URL loading does without a
/// connection.
internal final class TrustedListFakeNetwork: @unchecked Sendable {
  private let served: [String: Data]
  private let offline: Bool
  internal private(set) var fetches: [String] = []

  internal init(served: [String: Data], offline: Bool) {
    self.served = served
    self.offline = offline
  }

  internal func fetch(_ location: String) throws -> Data {
    fetches.append(location)
    if offline { throw URLError(.notConnectedToInternet) }
    guard let bytes = served[location] else { throw TrustedListError.notFetched }
    return bytes
  }
}
