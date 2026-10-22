// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Synchronization

/// Names each authenticated message the engine refuses to a receiver the
/// host installs, so a development build can show it among its errors.
///
/// A line names the message type and the rule its body broke, never a
/// field's value. Nothing is said until a receiver is installed, and a
/// host installs one only in its development builds.
public enum RappRefusalLog {
  private static let receiver = Mutex<(@Sendable (String) -> Void)?>(nil)

  /// Sends every later refusal to `receiver`.
  @preconcurrency
  public static func install(_ receiver: @escaping @Sendable (String) -> Void) {
    Self.receiver.withLock { $0 = receiver }
  }

  /// Names the refusal of a received `messageType` whose body broke
  /// `rule`.
  internal static func refused(_ messageType: MessageType, because rule: any Error) {
    guard let deliver = receiver.withLock({ $0 }) else { return }
    deliver("\(messageType.rawValue): \(rule)")
  }
}
