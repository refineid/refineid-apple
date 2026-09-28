// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import SwiftUI

  /// Hosts the one credentials surface and the reader identity model
  /// that lights up its reader states.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var model = ReaderIdentityModeModel()
    @StateObject private var remoteModel = RemoteCardModel()
    @ObservedObject private var authorizationInbox = RappAuthorizationInbox.shared

    @State private var enteredPin = ""

    internal var body: some View {
      NavigationStack {
        CardCredentialsView(
          readerModel: model,
          remoteModel: remoteModel
        )
      }
      .onAppear {
        model.refresh()
        remoteModel.refresh()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification)
      ) { _ in
        remoteModel.refresh()
      }
      .onValueChange(of: scenePhase) { _ in
        if scenePhase == .active {
          model.refresh()
          remoteModel.refresh()
          #if os(iOS) && REFINEID_LOCAL_CARD
            HolderCardServing.availabilityChanged()
          #endif
        }
      }
      .alert(
        promptTitle(for: authorizationInbox.request?.action),
        isPresented: Binding(
          get: { authorizationInbox.request != nil },
          set: { shown in
            if !shown, let pending = authorizationInbox.request {
              enteredPin = ""
              authorizationInbox.deny(pending.requestID)
            }
          }
        ),
        presenting: authorizationInbox.request
      ) { req in
        alertActions(for: req)
      } message: { req in
        if let displayContext = req.displayContext, !displayContext.isEmpty {
          Text("\(req.requester)\n\(displayContext)")
        } else {
          Text(req.requester)
        }
      }
    }

    @ViewBuilder
    private func alertActions(for req: RappAuthorizationRequest) -> some View {
      if req.action == .browserAuthentication || req.action == .documentSignature {
        SecureField(
          req.action == .documentSignature ? "PIN 2" : "PIN 1",
          text: Binding(
            get: { enteredPin },
            set: { enteredPin = LimitedDigits.pin($0) }
          )
        )
        .keyboardType(.numberPad)
        .textContentType(.none)
        .accessibilityIdentifier(req.action == .documentSignature ? "rappPin2" : "rappPin1")

        Button("OK") {
          submitPin(for: req)
        }
        .disabled(!isPinValid(enteredPin, for: req.action))
        .accessibilityIdentifier("rappApprove")

        Button("Cancel", role: .cancel) {
          enteredPin = ""
          authorizationInbox.deny(req.requestID)
        }
        .accessibilityIdentifier("rappDeny")
      } else {
        Button("Allow") {
          authorizationInbox.approve(req.requestID)
        }
        .accessibilityIdentifier("rappApprove")

        Button("Cancel", role: .cancel) {
          authorizationInbox.deny(req.requestID)
        }
        .accessibilityIdentifier("rappDeny")
      }
    }

    private func submitPin(for req: RappAuthorizationRequest) {
      let pin = enteredPin
      enteredPin = ""
      if req.action == .browserAuthentication {
        if Pin1(digits: pin) != nil {
          authorizationInbox.approveBrowserAuthentication(req.requestID, pin1: pin)
        } else {
          authorizationInbox.deny(req.requestID)
        }
      } else if req.action == .documentSignature {
        if Pin2(digits: pin) != nil {
          authorizationInbox.approveDocumentSignature(req.requestID, pin2: pin)
        } else {
          authorizationInbox.deny(req.requestID)
        }
      }
    }

    private func promptTitle(for action: RappAuthorizationRequest.Action?) -> String {
      switch action {
      case .browserAuthentication:
        "PIN 1"
      case .documentSignature:
        "PIN 2"
      case .shareCardInformation:
        String(localized: "Allow card read?")
      case nil:
        ""
      }
    }

    private func isPinValid(_ pin: String, for action: RappAuthorizationRequest.Action) -> Bool {
      switch action {
      case .browserAuthentication:
        Pin1(digits: pin) != nil
      case .documentSignature:
        Pin2(digits: pin) != nil
      case .shareCardInformation:
        true
      }
    }
  }

#endif
