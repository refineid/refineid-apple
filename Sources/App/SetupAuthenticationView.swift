// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import SwiftUI

  /// The setup authentication prompt: the entry, then the hold.
  ///
  /// A personal card's six digits start the hold on their own, typed or
  /// scanned, with the entry field accompanied by card specimen guidance.
  /// An organization card's PIN 1 runs four to twelve digits and keeps its
  /// start button; only its longest length starts by itself. The prompt
  /// always opens empty, so every completion is a fresh edit that
  /// starts the hold, and dismisses itself as the hold starts, leaving
  /// the hold instruction behind the system sheet.
  internal struct SetupAuthenticationView: View {
    private enum Layout {
      static let buttonHeight: CGFloat = 50
      static let canButtonSize = 44.0
      static let canButtonOuterPadding = -10.0
      static let cardCornerRadius: CGFloat = 10
      static let contentSpacing: CGFloat = 16
      static let disabledActionOpacity = 0.3
      static let horizontalInsetCount: CGFloat = 2
      static let horizontalPadding: CGFloat = 16
      static let totalHorizontalPadding: CGFloat = horizontalPadding * horizontalInsetCount
      static let minimumScale = 0.6
      static let rowHorizontalPadding: CGFloat = 16
      static let rowVerticalPadding: CGFloat = 12
    }

    /// The digits bound to the mode displayed by this prompt.
    @Binding internal var entry: String

    /// Whether the entry is an organization card's PIN 1.
    internal let organizationMode: Bool

    /// Whether the hold can start right now.
    internal let canStart: Bool

    /// Starts the hold; the prompt is already dismissing.
    internal let onStart: () -> Void

    @State private var isScanning = false
    @State private var scannerTorchEnabled = false
    @FocusState private var isEntryFocused: Bool
    @Environment(\.dismiss)
    private var dismiss

    /// What the field takes: a PIN 1 in organization mode, the printed
    /// digits otherwise.
    private var fieldName: String {
      if organizationMode {
        CredentialLabels.name(for: .pin1)
      } else {
        String(localized: "Card Access Number (CAN)")
      }
    }

    internal var body: some View {
      GeometryReader { geometry in
        ScrollView(.vertical) {
          VStack(spacing: Layout.contentSpacing) {
            if organizationMode {
              Spacer(minLength: 0)
              entryCard
              startButton
              Spacer(minLength: 0)
            } else {
              entryCard
                .padding(.top, Layout.contentSpacing)
              Spacer(minLength: Layout.contentSpacing)
              CardAccessNumberGuidanceView(
                containerWidth: max(0, geometry.size.width - Layout.totalHorizontalPadding)
              )
              .padding(.bottom, Layout.contentSpacing)
            }
          }
          .frame(minHeight: geometry.size.height)
          .padding(.horizontal, Layout.horizontalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(String(localized: "Login website"))
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        isEntryFocused = true
        // A complete entry opens empty: whatever is typed next starts
        // the hold, and no reopened prompt can strand the holder with
        // digits that start nothing.
        if SetupAuthenticationFlow.shouldBeginHold(
          entry: entry,
          organizationMode: organizationMode
        ) {
          entry = ""
        }
      }
      .onValueChange(of: entry) { typed in
        entry =
          organizationMode
          ? LimitedDigits.pin(typed)
          : LimitedDigits.cardAccessNumber(typed)
        guard
          SetupAuthenticationFlow.shouldBeginHold(
            entry: entry,
            organizationMode: organizationMode
          )
        else {
          return
        }
        start()
      }
      #if REFINEID_LOCAL_CARD
        .sheet(isPresented: $isScanning) {
          ScannerSheet(
            torchEnabled: $scannerTorchEnabled,
            isScanning: $isScanning
          ) { digits in
            entry = digits
          }
        }
      #endif
    }

    private var entryCard: some View {
      entryRow
        .padding(.horizontal, Layout.rowHorizontalPadding)
        .padding(.vertical, Layout.rowVerticalPadding)
        .background(
          Color(.systemBackground),
          in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
        )
    }

    private var entryRow: some View {
      HStack {
        PersonRowLabel.cardIcon(
          systemName: "person.text.rectangle",
          lit: canStart
        )
        CredentialSecretField(
          name: fieldName,
          text: $entry,
          revealIdentifier: "cardAccessNumberReveal"
        ) {
          SecureField(fieldName, text: $entry)
            .font(.body)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isEntryFocused)
            .accessibilityLabel(Text(verbatim: fieldName))
            .accessibilityIdentifier("cardAccessNumberField")
        }
        .lineLimit(1)
        .minimumScaleFactor(Layout.minimumScale)
        #if REFINEID_LOCAL_CARD
          if !organizationMode {
            canScanButton
          }
        #endif
      }
      .buttonStyle(.borderless)
    }

    private var startButton: some View {
      Button {
        start()
      } label: {
        Label(
          String(localized: "Read Identity Card"),
          systemImage: "person.badge.key.fill"
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.buttonHeight)
        .background(
          canStart
            ? Color.accentColor : Color.secondary.opacity(Layout.disabledActionOpacity),
          in: Capsule()
        )
        .contentShape(Capsule())
      }
      .buttonStyle(.borderless)
      .disabled(!canStart)
      .accessibilityIdentifier("primeStartButton")
    }

    #if REFINEID_LOCAL_CARD
      @ViewBuilder private var canScanButton: some View {
        if CardAccessNumberScanner.isAvailable {
          Button {
            scannerTorchEnabled = false
            isScanning = true
          } label: {
            Label("Scan", systemImage: "camera")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .frame(width: Layout.canButtonSize, height: Layout.canButtonSize)
          .contentShape(Rectangle())
          .padding(Layout.canButtonOuterPadding)
        }
      }
    #endif

    private func start() {
      dismiss()
      onStart()
    }
  }
#endif
