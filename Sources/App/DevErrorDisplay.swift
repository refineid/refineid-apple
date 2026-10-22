// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import SwiftUI

  /// The development error display for the window it modifies.
  ///
  /// On the Mac the errors have a floating window of their own,
  /// ``DevErrorWindow``, and nothing is drawn over this one. On the iPhone
  /// and iPad a small panel floats over the content: a pill with the count
  /// and the newest error while it is new, a dot with the count otherwise.
  /// It can be dragged anywhere, settles against the nearer side edge,
  /// remembers where it was left, and takes taps only where it is drawn.
  /// A tap opens every error in full.
  ///
  /// Development builds only, and developer-facing: its text is not
  /// localised.
  internal struct DevErrorDisplay: ViewModifier {
    // MARK: Nested Types

    #if os(iOS)
      /// The panel's measurements.
      private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let spacing: CGFloat = 8
        static let padding: CGFloat = 8
        static let badgePadding: CGFloat = 6
        static let edgeMargin: CGFloat = 8
        static let messageWidth: CGFloat = 240
        static let messageLineLimit = 3
        static let dotDiameter: CGFloat = 32
        static let shadowRadius: CGFloat = 4
        /// How far a touch moves before it drags rather than taps.
        static let dragThreshold: CGFloat = 8
        /// Where the panel starts: down the screen, clear of the title.
        static let defaultVerticalPosition = 0.75
        static let verticalRange = 0.0...1.0
      }
    #endif

    // MARK: Static Properties

    #if os(iOS)
      /// Names the floating panel for a UI test that opted in.
      internal static let accessibilityIdentifier = "dev-error-panel"

      /// The setting the panel's side is kept under.
      private static let trailingEdgeKey = "DevErrorPanelOnTrailingEdge"

      /// The setting its height is kept under, from top to bottom of the
      /// space it can travel.
      private static let verticalPositionKey = "DevErrorPanelVerticalPosition"
    #endif

    // MARK: SwiftUI Properties

    @Bindable private var model = DevErrorModel.shared
    @Environment(\.scenePhase)
    private var scenePhase

    #if os(iOS)
      @AppStorage(Self.trailingEdgeKey)
      private var isOnTrailingEdge = true
      @AppStorage(Self.verticalPositionKey)
      private var verticalPosition = Layout.defaultVerticalPosition
      @State private var area: CGSize = .zero
      @State private var dragTranslation: CGSize = .zero
      @State private var panelSize: CGSize = .zero
    #endif

    // MARK: Computed Properties

    #if os(iOS)
      /// The panel at its place, while there is anything to show and the
      /// list is not open.
      @ViewBuilder private var floating: some View {
        if !model.entries.isEmpty, !model.isListShown {
          let position = Self.moved(origin, by: dragTranslation)
          panel
            .onGeometryChange(for: CGSize.self) { geometry in
              geometry.size
            } action: { size in
              panelSize = size
            }
            .contentShape(.rect)
            .onTapGesture { model.isListShown = true }
            .gesture(drag)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(Self.accessibilityIdentifier)
            .offset(x: position.x, y: position.y)
            .transition(.opacity)
        }
      }

      @ViewBuilder private var panel: some View {
        if model.isExpanded, let newest = model.entries.first {
          pill(newest)
        } else {
          dot
        }
      }

      private var badge: some View {
        Text(verbatim: "\(model.entries.count)")
          .font(.caption.bold())
          .monospacedDigit()
          .foregroundStyle(.white)
          .padding(.horizontal, Layout.badgePadding)
          .background(.red, in: Capsule())
      }

      private var dot: some View {
        Text(verbatim: "\(model.entries.count)")
          .font(.caption.bold())
          .monospacedDigit()
          .foregroundStyle(.white)
          .frame(width: Layout.dotDiameter, height: Layout.dotDiameter)
          .background {
            Circle()
              .fill(.red)
              .shadow(radius: Layout.shadowRadius)
          }
          .accessibilityLabel(Text(verbatim: "\(model.entries.count) errors"))
      }

      /// Moves the panel with the finger, then settles it against the
      /// nearer side edge at the height it was let go.
      ///
      /// Measured in the global space: the panel's own space moves with
      /// the panel, and a translation read in it would chase itself.
      private var drag: some Gesture {
        DragGesture(minimumDistance: Layout.dragThreshold, coordinateSpace: .global)
          .onChanged { value in
            dragTranslation = value.translation
          }
          .onEnded { value in
            let bounds = Self.travel(in: area)
            let start = origin
            let thrown = CGRect(
              origin: Self.moved(start, by: value.predictedEndTranslation), size: panelSize)
            let height = bounds.height - panelSize.height
            let top = start.y + value.translation.height - bounds.minY
            withAnimation(.spring) {
              isOnTrailingEdge = thrown.midX > bounds.midX
              if height > 0 {
                verticalPosition = min(
                  max(top / height, Layout.verticalRange.lowerBound),
                  Layout.verticalRange.upperBound)
              }
              dragTranslation = .zero
            }
          }
      }

      /// Where the panel's top leading corner rests.
      private var origin: CGPoint {
        let bounds = Self.travel(in: area)
        let height = max(bounds.height - panelSize.height, 0)
        return CGPoint(
          x: isOnTrailingEdge ? bounds.maxX - panelSize.width : bounds.minX,
          y: bounds.minY + height * verticalPosition)
      }
    #endif

    // MARK: Static Functions

    #if os(iOS)
      /// The space the panel moves in: `area` short of its edges.
      private static func travel(in area: CGSize) -> CGRect {
        CGRect(origin: .zero, size: area).insetBy(dx: Layout.edgeMargin, dy: Layout.edgeMargin)
      }

      /// `point` moved by `translation`.
      private static func moved(_ point: CGPoint, by translation: CGSize) -> CGPoint {
        CGPoint(x: point.x + translation.width, y: point.y + translation.height)
      }
    #endif

    // MARK: Functions

    internal func body(content: Content) -> some View {
      #if os(macOS)
        content
          .task { DevErrorWindow.shared.start() }
          .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.reload()
          }
      #else
        content
          .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
          } action: { size in
            area = size
          }
          .overlay(alignment: .topLeading) {
            floating
              .animation(.spring, value: model.isExpanded)
              .animation(.easeInOut, value: model.entries.isEmpty)
          }
          .sheet(isPresented: $model.isListShown) {
            DevErrorList(model: model)
              .presentationDetents([.medium, .large])
          }
          .task { model.start() }
          .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.reload()
          }
      #endif
    }

    #if os(iOS)
      /// The newest error with the count, and a way to fold it away.
      private func pill(_ newest: DevErrorLog.Entry) -> some View {
        HStack(alignment: .top, spacing: Layout.spacing) {
          badge
          Text(verbatim: newest.text)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(Layout.messageLineLimit)
            .frame(maxWidth: Layout.messageWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
          Button {
            model.collapse()
          } label: {
            Image(systemName: "chevron.compact.down")
              .foregroundStyle(.secondary)
              .accessibilityLabel(Text(verbatim: "Collapse"))
          }
          .buttonStyle(.plain)
        }
        .padding(Layout.padding)
        .background {
          RoundedRectangle(cornerRadius: Layout.cornerRadius)
            .fill(.regularMaterial)
            .stroke(.separator)
            .shadow(radius: Layout.shadowRadius)
        }
      }
    #endif
  }
#endif
