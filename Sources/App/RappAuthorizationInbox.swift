// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation
  import SwiftUI
  import UIKit
  import UserNotifications

  /// Main-actor rendezvous between the authenticated proxy and SwiftUI.
  ///
  /// There is no automatic approval, timeout, or queue. A second operation is
  /// denied while one is visible; expiry and disconnect arrive from the RAPP
  /// state machine and explicitly cancel the matching request.
  @MainActor
  internal final class RappAuthorizationInbox: ObservableObject {
    internal static let shared = RappAuthorizationInbox()

    @Published internal private(set) var request: RappAuthorizationRequest?
    private var continuation: CheckedContinuation<RappAuthorizationDecision, Never>?

    private init() {
      // The authorization prompt waits for the holder's opt-in: asking
      // here would put it on the very first launch, before any remote
      // use was ever chosen.
    }

    /// Asks for the notification authorization the prompts need.
    ///
    /// Called after the notifications explanation is confirmed. The
    /// approval alert shows in the app regardless; the notification
    /// carries it when backgrounded, so declining only costs the
    /// backgrounded case.
    internal func ensureAuthorization() {
      guard SupportedCardTransports.offersNearField else { return }
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge]
      ) { _, _ in
        // Notification authorization requested for an opted-in holder.
      }
    }

    internal func ask(
      _ offered: RappAuthorizationRequest
    ) async -> RappAuthorizationDecision {
      guard request == nil, continuation == nil else { return .denied }
      playPromptFeedback()
      postNotification(for: offered)
      return await withCheckedContinuation { continuation in
        self.request = offered
        self.continuation = continuation
      }
    }

    private func playPromptFeedback() {
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(.warning)
      UISoundLibrary.play(named: "Handoff-EncoreInfinitum")
    }

    internal func approve(_ requestID: String) {
      complete(requestID, with: .approved)
    }

    internal func approveBrowserAuthentication(
      _ requestID: String,
      pin1: String
    ) {
      guard let pin1Digits = Pin1AuthorizationDigits(digits: pin1) else { return }
      complete(requestID, with: .approvedBrowserAuthentication(pin1: pin1Digits))
    }

    internal func approveDocumentSignature(
      _ requestID: String,
      pin2: String
    ) {
      guard let pin2Digits = Pin2AuthorizationDigits(digits: pin2) else { return }
      complete(requestID, with: .approvedDocumentSignature(pin2: pin2Digits))
    }

    internal func deny(_ requestID: String) {
      complete(requestID, with: .denied)
    }

    /// Cancels only the operation the protocol named.
    ///
    /// A late cancellation cannot dismiss or decide a newer request.
    internal func cancel(_ requestID: String) {
      complete(requestID, with: .denied)
    }

    internal func cancelAll() {
      guard let request else { return }
      complete(request.requestID, with: .denied)
    }

    private func complete(
      _ requestID: String,
      with decision: RappAuthorizationDecision
    ) {
      guard request?.requestID == requestID, let continuation else { return }
      removeNotification(for: requestID)
      self.request = nil
      self.continuation = nil
      continuation.resume(returning: decision)
    }

    private func postNotification(for request: RappAuthorizationRequest) {
      guard SupportedCardTransports.offersNearField else { return }
      let center = UNUserNotificationCenter.current()
      let content = UNMutableNotificationContent()
      content.title = "RefineID"
      switch request.action {
      case .browserAuthentication:
        content.body = String(
          localized: "Sign-in requested by \(request.requester). Tap to approve & present card."
        )
      case .documentSignature:
        content.body = String(
          localized:
            "Document signature requested by \(request.requester). Tap to approve & present card."
        )
      case .shareCardInformation:
        content.body = String(
          localized: "Card information requested by \(request.requester). Tap to approve."
        )
      }
      content.sound = .default
      let notificationRequest = UNNotificationRequest(
        identifier: "rapp-auth-\(request.requestID)",
        content: content,
        trigger: nil
      )
      center.add(notificationRequest)
    }

    private func removeNotification(for requestID: String) {
      let identifier = "rapp-auth-\(requestID)"
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
  }
#endif
