// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import SwiftUI

  /// System-modal holder authorization.
  ///
  /// It uses the app's shared secret-field control and native buttons;
  /// no parallel visual language is introduced.
  internal struct RappAuthorizationView: View {
    internal let request: RappAuthorizationRequest
    internal let inbox: RappAuthorizationInbox

    @State private var pin1 = ""
    @State private var pin2 = ""
    @FocusState private var pin1Focused: Bool
    @FocusState private var pin2Focused: Bool

    private var title: LocalizedStringKey {
      switch request.action {
      case .browserAuthentication:
        "Browser authentication"

      case .documentSignature:
        "Document signature"

      case .shareCardInformation:
        "Share card information"
      }
    }

    internal var body: some View {
      NavigationStack {
        Form {
          requesterSection
          if request.action == .browserAuthentication {
            authPin1Section
          }
          if request.action == .documentSignature {
            signPin2Section
          }
          actionsSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .onAppear {
          switch request.action {
          case .browserAuthentication:
            pin1Focused = true

          case .documentSignature:
            pin2Focused = true

          case .shareCardInformation:
            break
          }
        }
        .onDisappear {
          pin1 = ""
          pin2 = ""
        }
      }
    }

    private var requesterSection: some View {
      Section {
        LabeledContent("Requester") {
          Text(request.requester)
            .multilineTextAlignment(.trailing)
        }
        if let displayContext = request.displayContext, !displayContext.isEmpty {
          LabeledContent(request.action == .documentSignature ? "Document" : "Origin") {
            Text(displayContext)
              .multilineTextAlignment(.trailing)
          }
        }
      }
    }

    private var authPin1Section: some View {
      Section("Authentication") {
        CredentialSecretField(
          name: CredentialLabels.name(for: .pin1),
          text: $pin1,
          revealIdentifier: "rappPin1Reveal"
        ) {
          SecureField(CredentialLabels.name(for: .pin1), text: $pin1)
            .keyboardType(.numberPad)
            .textContentType(.none)
            .onValueChange(of: pin1) { typed in
              pin1 = LimitedDigits.pin(typed)
            }
            .focused($pin1Focused)
            .accessibilityIdentifier("rappPin1")
        }
      }
    }

    private var signPin2Section: some View {
      Section("Signature authorization") {
        CredentialSecretField(
          name: CredentialLabels.name(for: .pin2),
          text: $pin2,
          revealIdentifier: "rappPin2Reveal"
        ) {
          SecureField(CredentialLabels.name(for: .pin2), text: $pin2)
            .keyboardType(.numberPad)
            .textContentType(.none)
            .onValueChange(of: pin2) { typed in
              pin2 = LimitedDigits.pin(typed)
            }
            .focused($pin2Focused)
            .accessibilityIdentifier("rappPin2")
        }
      }
    }

    private var actionsSection: some View {
      Section {
        Button {
          approve()
        } label: {
          Text("Approve")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canApprove)
        .accessibilityIdentifier("rappApprove")

        Button(role: .destructive) {
          deny()
        } label: {
          Text("Deny")
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("rappDeny")
      }
    }

    private var canApprove: Bool {
      switch request.action {
      case .browserAuthentication:
        Pin1(digits: pin1) != nil

      case .documentSignature:
        Pin2(digits: pin2) != nil

      case .shareCardInformation:
        true
      }
    }

    private func approve() {
      switch request.action {
      case .browserAuthentication:
        inbox.approveBrowserAuthentication(request.requestID, pin1: pin1)
        pin1 = ""

      case .documentSignature:
        inbox.approveDocumentSignature(request.requestID, pin2: pin2)
        pin2 = ""

      case .shareCardInformation:
        inbox.approve(request.requestID)
      }
    }

    private func deny() {
      pin1 = ""
      pin2 = ""
      inbox.deny(request.requestID)
    }
  }
#endif
