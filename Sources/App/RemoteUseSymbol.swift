// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The SF Symbols for remote use, shared by the Mac switch and the iPhone
/// row so the two cannot diverge again: the slash means off.
internal enum RemoteUseSymbol: Sendable {
  /// Remote use is on.
  internal static let enabled = "key.radiowaves.forward"

  /// Remote use is off.
  internal static let disabled = "key.radiowaves.forward.slash"
}
