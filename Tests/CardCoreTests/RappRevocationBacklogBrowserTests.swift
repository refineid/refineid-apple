// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(Network)
  /// The revocation backlog's browser reports each forgotten pairing coming
  /// into sight once (RAPP v26.11.8 §4.6 item 6), also across a change of
  /// what it follows.
  @Suite("RAPP revocation backlog browser")
  internal struct RappRevocationBacklogBrowserTests {
    /// The appearances a browser reported.
    private final class Appearances: @unchecked Sendable {
      private let lock = NSLock()
      private var seen: [String] = []

      var all: [String] {
        lock.withLock { seen }
      }

      func record(_ pairing: String) {
        lock.withLock { seen.append(pairing) }
      }
    }

    private static let held = "held pairing"
    private static let newlyForgotten = "newly forgotten pairing"

    @Test("A listing that stays is not a new appearance when another pairing is followed")
    internal func followingMoreKeepsWhatIsInSight() {
      let appearances = Appearances()
      let browser = RappRevocationBacklogBrowser(
        following: [Self.held], classifyingRecord: { _, _ in nil },
        onAppeared: { appearances.record($0) })
      browser.sighted([Self.held])
      browser.sighted([Self.held])
      #expect(appearances.all == [Self.held])

      browser.update(
        following: [Self.held, Self.newlyForgotten], classifyingRecord: { _, _ in nil },
        onAppeared: { appearances.record($0) })
      browser.sighted([Self.held])
      #expect(appearances.all == [Self.held], "the phone that stayed in sight is not dialed again")
      browser.sighted([Self.held, Self.newlyForgotten])
      #expect(appearances.all == [Self.held, Self.newlyForgotten])
      #expect(browser.following == [Self.held, Self.newlyForgotten])
    }

    @Test("A pairing no longer followed is not reported")
    internal func unfollowedPairingIsIgnored() {
      let appearances = Appearances()
      let browser = RappRevocationBacklogBrowser(
        following: [Self.held], classifyingRecord: { _, _ in nil },
        onAppeared: { appearances.record($0) })
      browser.update(
        following: [], classifyingRecord: { _, _ in nil }, onAppeared: { appearances.record($0) })
      browser.sighted([Self.held])
      #expect(appearances.all.isEmpty)
    }
  }
#endif
