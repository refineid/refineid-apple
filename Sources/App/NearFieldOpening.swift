// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How a field's channel is prepared for the card the phone serves.
internal enum NearFieldOpening: Equatable, Sendable {
  /// A personal card: PACE with this card access number, once per channel.
  case cardAccessNumber(String)

  /// An organization card: the channel stays plain, and each operation
  /// runs PACE with the PIN it spends.
  case organizationCard
}
