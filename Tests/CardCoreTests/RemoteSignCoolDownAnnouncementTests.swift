// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Every pause the cool-down begins or ends is announced to other processes.
@Suite(.serialized)
internal struct RemoteSignCoolDownAnnouncementTests {
  private enum Fixture {
    static let poll: Duration = .milliseconds(10)
    static let patience = 200
    static let announcements = AnnouncementCount()
  }

  private static func wait(until condition: () -> Bool) async throws {
    for _ in 0..<Fixture.patience where !condition() {
      try await Task.sleep(for: Fixture.poll)
    }
  }

  /// Beginning and ending a pause each post the change notification.
  @Test
  internal func pauseAndResumeAreAnnounced() async throws {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = UnsafeRawPointer(bitPattern: 1)
    CFNotificationCenterAddObserver(
      center, observer, { _, _, _, _, _ in Fixture.announcements.increment() },
      RemoteSignCoolDown.changeNotificationName as CFString, nil, .deliverImmediately)
    defer { CFNotificationCenterRemoveEveryObserver(center, observer) }
    let start = Fixture.announcements.total
    let coolDown = RemoteSignCoolDown(
      defaultsSuite: "fi.refineid.tests.coolDown.\(UUID().uuidString)")
    coolDown.record(.unattended, at: Date())
    try await Self.wait { Fixture.announcements.total >= start + 1 }
    coolDown.resume()
    try await Self.wait { Fixture.announcements.total >= start + 2 }
    #expect(Fixture.announcements.total >= start + 2)
  }
}
