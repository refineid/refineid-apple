// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Who carries an operation the token extension hands over.
internal enum HandoffCarrier: Equatable, Sendable {
  /// The app, on its Bluetooth session: the extension cannot open a link
  /// of its own beside it.
  case app
  /// The extension, dialing the stream itself.
  case extensionOverStream
}
