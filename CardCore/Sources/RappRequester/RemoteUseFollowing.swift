// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What follows the remote-use switch as it moves.
///
/// The app's token registry follows the paired phone, offers the code entry,
/// or forgets every pairing; a test records the moves instead. The switch
/// knows only this interface, so its decision core needs neither a registry
/// nor a transport.
@preconcurrency
@MainActor
public protocol RemoteUseFollowing: AnyObject {
  /// The switch moved: follow the paired phone, offer the code entry, forget
  /// every pairing, or stop keeping them as they are.
  func remoteUseChanged(_ move: RemoteUseSwitch.Move)
}
