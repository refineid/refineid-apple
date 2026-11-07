// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import RappEngine
  import Testing

  /// The notices a requester session posts stay on this process's own
  /// notification center.
  @Suite("Requester notices")
  internal struct RappRequesterNoticesTests {
    private final class Heard: @unchecked Sendable {
      var names: [Notification.Name] = []
    }

    private func names(postedBy post: () -> Void) -> [Notification.Name] {
      let heard = Heard()
      let watched = [
        RappRequesterNotices.cardNeeded, RappRequesterNotices.unlockNeeded,
        RappRequesterNotices.cardWaitEnded,
        RappRequesterNotices.serviceWithdrawn, RappRequesterNotices.pairingRevoked,
      ]
      let observers = watched.map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
          heard.names.append(name)
        }
      }
      defer { observers.forEach(NotificationCenter.default.removeObserver) }
      post()
      return heard.names
    }

    @Test("Waiting for the card posts the card-needed notice")
    internal func waitingForCardPostsCardNeeded() {
      #expect(
        names { RappRequesterNotices.post(progress: .waitingForCard) }
          == [RappRequesterNotices.cardNeeded])
    }

    @Test("The end of the wait posts the card-wait-ended notice")
    internal func cardWaitEndedPostsDismiss() {
      #expect(
        names { RappRequesterNotices.post(progress: .cardWaitEnded) }
          == [RappRequesterNotices.cardWaitEnded])
    }

    @Test("Waiting for the unlock posts the unlock notice")
    internal func waitingForUnlockPostsUnlockNeeded() {
      #expect(
        names { RappRequesterNotices.post(progress: .waitingForUnlock) }
          == [RappRequesterNotices.unlockNeeded])
    }

    @Test("The consent screen ends the wait")
    internal func consentShownEndsTheWait() {
      #expect(
        names { RappRequesterNotices.post(progress: .consentShown) }
          == [RappRequesterNotices.cardWaitEnded])
    }

    @Test("Queued progress posts nothing")
    internal func queuedPostsNothing() {
      #expect(names { RappRequesterNotices.post(progress: .queued) }.isEmpty)
    }

    @Test("A pairing's end is posted under its own name")
    internal func pairingEndNotices() {
      #expect(
        names { RappRequesterNotices.post(RappRequesterNotices.pairingRevoked) }
          == [RappRequesterNotices.pairingRevoked])
      #expect(
        names { RappRequesterNotices.post(RappRequesterNotices.serviceWithdrawn) }
          == [RappRequesterNotices.serviceWithdrawn])
    }
  }
#endif
