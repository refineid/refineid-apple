// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation
  import SwiftUI
  import UIKit
  import UserNotifications

  /// Main-actor rendezvous between the authenticated proxy and SwiftUI.
  ///
  /// There is no automatic approval, timeout, or queue: only the operation
  /// holding the card asks (RAPP v26.10.22 §8.2 item 2), and a second
  /// request is denied while one is visible. Expiry and disconnect arrive
  /// from the RAPP state machine and explicitly cancel the matching
  /// request, also one cancelled on its way to the screen. Every request
  /// is a PIN prompt, and entering the PIN is the holder's consent; reads
  /// never come here (§8.2 items 3 and 6).
  @MainActor
  internal final class RappAuthorizationInbox: ObservableObject {
    internal static let shared = RappAuthorizationInbox()

    private static let notificationPrefix = "rapp-auth-"

    /// How many requests withdrawn before they reached the screen are
    /// remembered; one request is on its way at a time, the card turn
    /// holder's.
    private static let withdrawalMemory = 8

    @Published internal private(set) var request: RappAuthorizationRequest?
    private var continuation: CheckedContinuation<RappAuthorizationDecision, Never>?

    /// Requests cancelled before they reached the screen, newest last, so
    /// one that arrives after its own cancellation is never shown.
    private var withdrawn: [String] = []

    private init() {
      // The authorization prompt waits for the holder's opt-in: asking
      // here would put it on the very first launch, before any remote
      // use was ever chosen.
    }

    internal func ask(
      _ offered: RappAuthorizationRequest
    ) async -> RappAuthorizationDecision {
      if let index = withdrawn.firstIndex(of: offered.requestID) {
        withdrawn.remove(at: index)
        return .denied
      }
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
    /// A late cancellation cannot dismiss or decide a newer request; one
    /// that comes before its request reached the screen keeps it off.
    internal func cancel(_ requestID: String) {
      guard request?.requestID == requestID else {
        withdrawn.append(requestID)
        if withdrawn.count > Self.withdrawalMemory { withdrawn.removeFirst() }
        return
      }
      complete(requestID, with: .denied)
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
      }
      content.sound = .default
      // The paired computer is waiting now; a Focus may still silence
      // it, since the holder can turn Time Sensitive off per Focus.
      content.interruptionLevel = .timeSensitive
      let notificationRequest = UNNotificationRequest(
        identifier: Self.notificationPrefix + request.requestID,
        content: content,
        trigger: nil
      )
      center.add(notificationRequest)
    }

    /// Clears card requests left from an earlier run.
    ///
    /// A request lives only as long as the session that asked, so any
    /// delivered one without a request on screen is stale.
    internal func removeStaleNotifications() {
      guard request == nil else { return }
      Task {
        let center = UNUserNotificationCenter.current()
        let stale = await center.deliveredNotifications()
          .map(\.request.identifier)
          .filter { $0.hasPrefix(Self.notificationPrefix) }
        guard !stale.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: stale)
      }
    }

    /// Tells the holder something about a request that ended without a
    /// prompt, such as a retry-floor refusal (RAPP v26.10.22 §10.2).
    internal func inform(_ message: String) {
      let content = UNMutableNotificationContent()
      content.title = "RefineID"
      content.body = message
      content.interruptionLevel = .timeSensitive
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(
          identifier: Self.notificationPrefix + UUID().uuidString, content: content, trigger: nil))
    }

    private func removeNotification(for requestID: String) {
      let identifier = Self.notificationPrefix + requestID
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
  }
#endif
