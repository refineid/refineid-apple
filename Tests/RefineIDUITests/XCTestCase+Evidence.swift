// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// Attaching evidence, because a failure that says nothing costs a device
/// round trip.
///
/// Every attachment is `keepAlways`. A result bundle that discarded the
/// captures of a passing run would be no use for the question the holder
/// actually asked -- not "did it pass" but "was it smooth" -- and that
/// question can only be answered by watching the run back.
extension XCTestCase {
  /// Attaches a screenshot under a name that sorts in run order.
  ///
  /// Names are numbered by the caller rather than timestamped: a result
  /// bundle lists attachments alphabetically, and a reader wants them in
  /// the order the run made them.
  internal func attachScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Attaches plain text: a summary, or the app's own diagnostics.
  ///
  /// Nothing passed here may carry a card access number, a PIN, a serial
  /// or a holder name. Sizes, states, counts and typed reasons only.
  internal func attachText(_ text: String, named name: String) {
    let attachment = XCTAttachment(string: text)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
