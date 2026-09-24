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
    /// The sideways nudge a refusal draws.
    private struct Shake: GeometryEffect {
      /// How far the row swings, in points.
      private static let amplitude: CGFloat = 8

      /// Sine phase per refusal, in half-turns: six half-turns is
      /// three full swings.
      private static let halfTurns: CGFloat = 6

      /// Counts refusals; animating to the next integer plays one
      /// shake.
      var animatableData: CGFloat

      func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(
          CGAffineTransform(
            translationX: Self.amplitude
              * sin(animatableData * Self.halfTurns * .pi),
            y: 0))
      }
    }

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

    private static let boxCount = CardAccessNumber.digitCount
    private static let boxSpacing: CGFloat = 6
    private static let boxWidth: CGFloat = 32
    private static let boxHeight: CGFloat = 40
    private static let boxCorner: CGFloat = 6
    private static let boxBorder: CGFloat = 1

    /// The heavier border on the box the next digit lands in.
    private static let activeBoxBorder: CGFloat = 2

    /// How long a submitted number is watched for its verdict.
    ///
    /// Nonisolated: the watching runs off the main actor. Long,
    /// because the verdict waits for the holder to take the card off
    /// and put it back, plus card PACE delay on NFC readers (which can
    /// take 40-50+ seconds); the watch ends early with the verdict.
    nonisolated private static let verdictPolls = 240

    /// The pause between looks, in milliseconds.
    nonisolated private static let refusalPollMilliseconds = 500

    /// Whether a submitted number is awaiting the card's verdict.
    ///
    /// Owned by the status window: while this stands, the window
    /// shows only the card instruction, and it must survive the card
    /// leaving the reader - which is a step of the flow, not its end.
    @Binding internal var offering: Bool

    @State private var number = ""
    /// Whether the holder has asked the system for less movement.
    ///
    /// The shake is the one thing in this app that moves. A holder who
    /// turns motion down has said they do not want it, and the refusal
    /// still reads without it: the row turns red and says so.
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var refused = false
    @State private var refusedOnce = false
    @State private var step: Step?
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Bool

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
            .modifier(Shake(animatableData: shakes))

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

    /// The label, the boxes, and the invisible field beneath them.
    ///
    /// The field is the only thing that reads the keyboard or a
    /// paste; the boxes draw its contents. Focus lands on it when
    /// the section appears and returns on any click.
    @ViewBuilder private var entry: some View {
      ZStack {
        TextField("", text: $number)
          .textFieldStyle(.plain)
          .opacity(0)
          .focused($focused)
          .onChange(of: number) { previous, typed in
            react(from: previous, to: typed)
          }
          .accessibilityIdentifier("sealedCardAccessNumber")
        HStack(spacing: Self.boxSpacing) {
          Text(verbatim: "CAN")
            .foregroundStyle(.secondary)
          Spacer()
          ForEach(0..<Self.boxCount, id: \.self) { index in
            box(at: index)
          }
        }
      }
      .contentShape(.rect)
      .onTapGesture { focused = true }
      .onAppear { focused = true }
    }

    /// Takes the offered number back: at launch, and at quit.
    ///
    /// Not when the card leaves. A contactless card leaves the field
    /// between taps, the offer exists to serve the next tap, and
    /// every contactless session - PIN management included - runs
    /// PACE again and needs it. The app run is the offer's lifetime.
    internal static func withdrawOfferedNumber() {
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

    /// One digit's box: its frame, and the digit once typed.
    ///
    /// The box the next digit lands in carries the accent color -
    /// focus is shown in the accent, never in a verdict color, so
    /// where to type and how it went stay two different signals.
    @ViewBuilder
    private func box(at index: Int) -> some View {
      ZStack {
        RoundedRectangle(cornerRadius: Self.boxCorner)
          .strokeBorder(
            borderStyle(at: index),
            lineWidth: borderWidth(at: index)
          )
          .frame(width: Self.boxWidth, height: Self.boxHeight)
        if let digit = digit(at: index) {
          Text(digit)
            .font(.title3.monospacedDigit())
            .foregroundStyle(
              refused ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
      }
    }

    /// The border for `index`: red when refused, the accent where
    /// the next digit lands, and quiet otherwise.
    private func borderStyle(at index: Int) -> AnyShapeStyle {
      if refused {
        AnyShapeStyle(.red)
      } else if focused, index == number.count {
        AnyShapeStyle(.tint)
      } else {
        AnyShapeStyle(.quaternary)
      }
    }

    /// The border weight for `index`, heavier where the accent is.
    private func borderWidth(at index: Int) -> CGFloat {
      if focused, !refused, index == number.count {
        Self.activeBoxBorder
      } else {
        Self.boxBorder
      }
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

    /// The typed digit for `index`, once there is one.
    private func digit(at index: Int) -> String? {
      guard index < number.count else { return nil }
      return String(Array(number)[index])
    }

    /// Keeps the entry digits, clears a refusal on any edit, and
    /// submits when the sixth digit lands.
    private func react(from previous: String, to typed: String) {
      let digits = LimitedDigits.cardAccessNumber(typed)
      if digits != typed {
        number = digits
      }
      if refused, digits != previous {
        refused = false
      }
      if digits.count == Self.boxCount, previous.count < Self.boxCount {
        submit(digits)
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
              if !reduceMotion {
                withAnimation { shakes += 1 }
              }
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
