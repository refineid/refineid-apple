// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The entry a sealed contactless card is waiting for: one box per
  /// printed digit.
  ///
  /// Shown only when the slot's answer proves the card is on the
  /// antenna, so it needs no explaining - the card face says CAN over
  /// six digits, and the row shows CAN beside six boxes. The sixth
  /// digit submits on its own: the driver tries a number once, and a
  /// refused number is latched by fingerprint and never re-tried by
  /// itself, so the automatic try spends exactly one of the card's
  /// attempts per number entered. A refusal shakes the row and turns
  /// it red; typing again clears it. The boxes draw what the hidden
  /// field holds, and nothing can be selected or copied back out of
  /// them.
  internal struct SealedCardSection: View {
    /// The step a submitted number's service is on.
    ///
    /// One direction only: the card leaves, the card returns, the
    /// verdict arrives. Deriving the line from card presence alone
    /// flashed "take the card off" again the moment the card came
    /// back, which is the opposite of what the holder just did.
    private enum Step {
      case liftCard
      case layCard
      case verdict
    }

    /// What the section shows, as a pure function for tests.
    nonisolated internal enum Display {
      case instruction
      case entry
      case trying
    }

    /// How long a submitted number is watched for its verdict.
    ///
    /// Nonisolated: the watching runs off the main actor. Long,
    /// because the verdict waits for the holder to take the card off
    /// and put it back, plus card PACE delay on NFC readers (which can
    /// take 40-50+ seconds); the watch ends early with the verdict.
    nonisolated private static let verdictPolls = 240

    /// The pause between looks, in milliseconds.
    nonisolated private static let refusalPollMilliseconds = 500

    /// Whether this run already took back an earlier run's number.
    @MainActor private static var withdrewEarlierOffer = false

    /// Whether a submitted number is awaiting the card's verdict.
    ///
    /// Owned by the status window: while this stands, the window
    /// shows only the card instruction, and it must survive the card
    /// leaving the reader - which is a step of the flow, not its end.
    @Binding internal var offering: Bool

    @State private var number = ""
    @State private var refused = false
    @State private var refusedOnce = false
    @State private var step: Step?

    /// Whether a stored number exists to try before asking for one.
    ///
    /// Owned by the status window, which refreshes it whenever the
    /// card set changes.
    internal var tryingStored = false

    internal var body: some View {
      Section {
        switch Self.display(
          offering: offering,
          refused: refused,
          refusedOnce: refusedOnce,
          tryingStored: tryingStored)
        {
        case .instruction:
          instruction

        case .entry:
          entry

        case .trying:
          trying
        }
      }
      .onChange(of: CardPresence.shared.isContactlessCardPresent) { _, present in
        advance(cardPresent: present)
      }
    }

    /// The line while a remembered number is tried: no boxes, so no
    /// typing disturbs the attempt.
    private var trying: some View {
      Text("Trying the remembered number. Hold the card still.")
        .foregroundStyle(.secondary)
    }

    /// The step the flow is on, forward only.
    ///
    /// The system looks at a card when it arrives, so the entered
    /// number is served by taking the card off and putting it back.
    /// Once the card is back the line does not return; the quiet
    /// indicator stands for the verdict being fetched.
    @ViewBuilder private var instruction: some View {
      switch step {
      case .liftCard:
        Text("Take the card off the reader")
          .foregroundStyle(.secondary)

      case .layCard:
        Text("Put the card back")
          .foregroundStyle(.secondary)

      case .verdict, nil:
        ProgressView()
          .controlSize(.small)
      }
    }

    /// The label and one box per printed digit; the sixth digit
    /// submits.
    private var entry: some View {
      CodeBoxesField(
        label: String(localized: "Card Access Number (CAN)"),
        identifier: "sealedCardAccessNumber",
        caption: "CAN",
        length: CardAccessNumber.digitCount,
        groupSize: nil,
        text: $number,
        refused: $refused,
        filter: LimitedDigits.cardAccessNumber,
        onComplete: submit
      )
    }

    /// Takes back the number an earlier run offered, once per run;
    /// quitting takes back the current one.
    ///
    /// Not when the card leaves. A contactless card leaves the field
    /// between taps, the offer exists to serve the next tap, and
    /// every contactless session - PIN management included - runs
    /// PACE again and needs it. Not when the window opens again
    /// either: the app outlives its window. The app run is the
    /// offer's lifetime.
    @MainActor
    internal static func withdrawOfferedNumber() {
      guard !withdrewEarlierOffer else { return }
      withdrewEarlierOffer = true
      Task.detached(priority: .utility) {
        CardCredentialStore.withdrawCardAccessNumberFromDriver()
      }
    }

    /// Entry appears only when nothing is stored or the stored
    /// numbers just failed; otherwise the remembered number is
    /// tried first and typing would disturb the attempt.
    nonisolated internal static func display(
      offering: Bool,
      refused: Bool,
      refusedOnce: Bool,
      tryingStored: Bool
    ) -> Display {
      if offering {
        return .instruction
      }
      if refused || refusedOnce || !tryingStored {
        return .entry
      }
      return .trying
    }

    /// Moves the flow forward on the reader's answer, never back.
    private func advance(cardPresent: Bool) {
      guard offering else { return }
      if step == .liftCard, !cardPresent {
        step = .layCard
      } else if step == .layCard, cardPresent {
        step = .verdict
      }
    }

    /// Offers the number and watches for the card's verdict while
    /// the instruction walks the holder through serving it.
    ///
    /// The system looks at a card when it arrives - a warm reset
    /// proved invisible to it - so the offer is served by the card
    /// leaving and returning. The driver then tries the number once:
    /// a refusal brings the boxes back red and shaking, and a mint
    /// that succeeds publishes the identity, which ends the flow and
    /// this section with it.
    ///
    /// Off the main actor: the offer, the reset and the marker are
    /// file and PC/SC calls, which must not block the window.
    private func submit(_ digits: String) {
      offering = true
      step = CardPresence.shared.isContactlessCardPresent ? .liftCard : .layCard
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver(digits: digits)
        _ = SlotCardReset.resetContactlessCards()
        for _ in 0..<Self.verdictPolls {
          try? await Task.sleep(for: .milliseconds(Self.refusalPollMilliseconds))
          if CardCredentialStore.offeredNumberWasRefused() {
            await MainActor.run {
              offering = false
              step = nil
              refused = true
              refusedOnce = true
            }
            return
          }
          let published = await MainActor.run { LoginIdentityModel.shared.isReady }
          if published {
            await MainActor.run {
              offering = false
              step = nil
            }
            return
          }
        }
        await MainActor.run {
          offering = false
          step = nil
        }
      }
    }
  }

#endif
