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
          authorizationInbox.removeStaleNotifications()
        }
      }
      .alert(
        authorizationInbox.request?.title ?? "",
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
        Text(
          ([req.notice, req.message] as [String?])
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n"))
      }
    }

    @ViewBuilder
    private func alertActions(for req: RappAuthorizationRequest) -> some View {
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
    }

    /// Turns the text field's value into a zeroizing PIN entry and clears
    /// the field; no `String` of the digits outlives this call.
    private func submitPin(for req: RappAuthorizationRequest) {
      switch req.action {
      case .browserAuthentication:
        let entry = Pin1Entry(digits: enteredPin)
        enteredPin = ""
        if let entry {
          authorizationInbox.approveBrowserAuthentication(req.requestID, pin1: entry)
        } else {
          authorizationInbox.deny(req.requestID)
        }

      case .documentSignature:
        let entry = Pin2Entry(digits: enteredPin)
        enteredPin = ""
        if let entry {
          authorizationInbox.approveDocumentSignature(req.requestID, pin2: entry)
        } else {
          authorizationInbox.deny(req.requestID)
        }
      }
    }

    private func isPinValid(_ pin: String, for action: RappAuthorizationRequest.Action) -> Bool {
      switch action {
      case .browserAuthentication:
        Pin1(digits: pin) != nil
      case .documentSignature:
        Pin2(digits: pin) != nil
      }
    }
  }

#endif
