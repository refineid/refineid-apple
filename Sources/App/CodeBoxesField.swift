// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// A short code typed one character per box.
  ///
  /// A text field reads the keyboard and pastes; the boxes draw what it
  /// holds. The field stays visible to VoiceOver and Full Keyboard
  /// Access under its own label, and the boxes are drawing only. The
  /// last character submits on its own. A refusal turns the boxes red
  /// and, unless motion is reduced, shakes them; any edit clears it.
  internal struct CodeBoxesField: View {
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

    /// What one edit leaves in the field.
    internal struct Edit: Equatable {
      /// The characters kept.
      internal let text: String

      /// Whether this edit filled the last box.
      internal let completes: Bool
    }

    private static let boxSpacing: CGFloat = 6
    private static let groupGap: CGFloat = 14
    private static let boxCorner: CGFloat = 6
    private static let boxBorder: CGFloat = 1
    private static let disabledOpacity: Double = 0.5

    /// The heavier border on the box the next character lands in.
    private static let activeBoxBorder: CGFloat = 2

    /// The spoken name of the field.
    internal let label: String

    /// The field's identifier for tests.
    internal let identifier: String

    /// What the row shows before the boxes, if anything.
    internal let caption: String?

    /// How many characters the code holds.
    internal let length: Int

    /// Boxes per group; groups are drawn apart, as the code is printed.
    internal let groupSize: Int?

    @Binding internal var text: String

    /// Whether the last code was refused.
    @Binding internal var refused: Bool

    /// What a typed string keeps.
    internal let filter: (String) -> String

    /// Called once with the code when the last box fills.
    internal let onComplete: (String) -> Void

    /// Called on Return.
    internal var onSubmit: (() -> Void)?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.isEnabled)
    private var isEnabled

    @ScaledMetric(relativeTo: .title3)
    private var boxWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .title3)
    private var boxHeight: CGFloat = 40

    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Bool

    internal var body: some View {
      HStack(spacing: Self.boxSpacing) {
        if let caption {
          Text(verbatim: caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Spacer()
        }
        boxes
          .overlay {
            // The field draws nothing: its text, caret and selection
            // highlight would cover the boxes. It keeps focus, input
            // and its accessibility element.
            TextField(label, text: $text)
              .textFieldStyle(.plain)
              .labelsHidden()
              .opacity(0)
              .autocorrectionDisabled()
              .focused($focused)
              .accessibilityLabel(Text(label))
              .accessibilityIdentifier(identifier)
              .accessibilityHint(Text(String(localized: "\(length) characters")))
              .onChange(of: text) { previous, typed in
                apply(Self.edit(from: previous, to: typed, length: length, filter: filter))
              }
              .onSubmit { onSubmit?() }
          }
      }
      .modifier(Shake(animatableData: shakes))
      .contentShape(.rect)
      .onTapGesture { focused = true }
      .onAppear {
        focused = true
        if refused, !reduceMotion {
          withAnimation { shakes += 1 }
        }
      }
      .onChange(of: refused) { _, isRefused in
        guard isRefused else { return }
        focused = true
        if !reduceMotion {
          withAnimation { shakes += 1 }
        }
      }
    }

    private var boxes: some View {
      HStack(spacing: Self.boxSpacing) {
        ForEach(0..<length, id: \.self) { index in
          if index > 0, let groupSize, index.isMultiple(of: groupSize) {
            Spacer()
              .frame(width: Self.groupGap - Self.boxSpacing)
          }
          box(at: index)
        }
      }
      .accessibilityHidden(true)
    }

    // MARK: Static Functions

    /// What an edit from `previous` to `typed` keeps, and whether it
    /// fills the last box.
    nonisolated internal static func edit(
      from previous: String,
      to typed: String,
      length: Int,
      filter: (String) -> String
    ) -> Edit {
      let kept = String(filter(typed).prefix(length))
      return Edit(text: kept, completes: kept.count == length && previous.count < length)
    }

    // MARK: Functions

    private func apply(_ edit: Edit) {
      if edit.text != text {
        text = edit.text
      }
      if refused {
        refused = false
      }
      if edit.completes {
        onComplete(edit.text)
      }
    }

    /// One box: its frame, and the character once typed.
    ///
    /// The box the next character lands in carries the accent color -
    /// focus is shown in the accent, never in a verdict color, so
    /// where to type and how it went stay two different signals.
    private func box(at index: Int) -> some View {
      ZStack {
        RoundedRectangle(cornerRadius: Self.boxCorner)
          .strokeBorder(borderStyle(at: index), lineWidth: borderWidth(at: index))
          .frame(width: boxWidth, height: boxHeight)
        if let character = character(at: index) {
          Text(verbatim: character)
            .font(.title3.monospacedDigit())
            .foregroundStyle(refused ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
      }
      .opacity(isEnabled ? 1 : Self.disabledOpacity)
    }

    /// Red when refused, the accent where the next character lands,
    /// and the secondary color otherwise, which keeps every box edge
    /// visible against the window.
    private func borderStyle(at index: Int) -> AnyShapeStyle {
      if refused {
        AnyShapeStyle(.red)
      } else if focused, index == text.count {
        AnyShapeStyle(.tint)
      } else {
        AnyShapeStyle(.secondary)
      }
    }

    private func borderWidth(at index: Int) -> CGFloat {
      if focused, !refused, index == text.count {
        Self.activeBoxBorder
      } else {
        Self.boxBorder
      }
    }

    private func character(at index: Int) -> String? {
      guard index < text.count else { return nil }
      return String(Array(text)[index])
    }
  }

#endif
