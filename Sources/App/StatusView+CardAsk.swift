// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Observation
  import SwiftUI

  /// What the token driver learnt the card on the antenna needs, as the
  /// status window sees it.
  ///
  /// The driver has no window: it leaves its answer in the shared
  /// keychain group, and this follows it while an unread card rests on
  /// the antenna.
  @MainActor
  @Observable
  internal final class CardAskWatch {
    // MARK: Static Properties

    internal static let shared = CardAskWatch()

    /// The pause between looks at the driver's answer, in milliseconds.
    private static let pollMilliseconds = 250

    // MARK: Properties

    internal private(set) var ask: CardDriverAsk?

    // MARK: Functions

    /// Follows the driver's answer until cancelled.
    internal func follow() async {
      while !Task.isCancelled {
        let asked = await Task.detached(priority: .utility) {
          CardCredentialStore.cardAsk()
        }.value
        if asked != ask {
          ask = asked
        }
        try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
      }
    }

    /// Clears the answer for a card that left the antenna.
    internal func forget() {
      ask = nil
      Task.detached(priority: .utility) {
        CardCredentialStore.clearCardAsk()
      }
    }
  }

  extension StatusView {
    /// Whether an unread card rests on the antenna, which is when the
    /// driver's answer is followed.
    internal var watchesCardAsk: Bool {
      #if FEATURE_CONTACTLESS
        availability == .cardWithoutIdentity && cardPresence.isContactlessCardPresent
      #else
        false
      #endif
    }

    /// Whether an unready card on the antenna asked for an access number.
    ///
    /// That is the one state that shows the CAN line; a card that
    /// refuses without asking, such as an organisation card, does not.
    internal var awaitingAccessNumber: Bool {
      watchesCardAsk && CardAskWatch.shared.ask == .cardAccessNumber
    }

    /// Whether the card on the antenna can be read only in the
    /// reader's card slot.
    internal var asksForCardSlot: Bool {
      watchesCardAsk && CardAskWatch.shared.ask == .cardSlot
    }

    /// The one line for a card the antenna cannot read.
    @ViewBuilder internal var cardSlotSection: some View {
      Section {
        Text("Put the card in the reader's card slot.")
          .foregroundStyle(.secondary)
      }
    }

    /// Follows the driver's answer while an unread card rests on the
    /// antenna.
    internal func watchCardAsk() async {
      guard watchesCardAsk else { return }
      await CardAskWatch.shared.follow()
    }

    /// Clears the answer for a card that left the antenna.
    internal func forgetCardAsked() {
      CardAskWatch.shared.forget()
    }
  }

#endif
