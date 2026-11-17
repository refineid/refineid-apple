// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Foundation
  import SwiftUI
  import Testing

  @testable import RefineIDTestHost

  /// Walks the AppKit accessibility hierarchy of every macOS MVP journey
  /// inside an off-screen window so VoiceOver labels, values, identifiers,
  /// reading order, and enabled states are verified without taking the
  /// workstation's screen.
  @MainActor
  @Suite(.serialized)
  internal struct MacVoiceOverJourneysTests {
    internal enum WindowMetrics {
      internal static let width: CGFloat = 560
      internal static let height: CGFloat = 640
      internal static let settleNanoseconds: UInt64 = 150_000_000
    }

    internal enum SampleCount {
      internal static let pristineRetries: UInt8 = 5
      internal static let reducedRetries: UInt8 = 4
      internal static let lowRetries: UInt8 = 2
      internal static let blockedRetries: UInt8 = 0
      internal static let singleDocument = 1
      internal static let twoDocuments = 2
      internal static let credentialCount = 3
    }

    /// A snapshot of one node in the AppKit accessibility tree.
    internal struct AccessibleNode: CustomStringConvertible {
      internal let role: NSAccessibility.Role?
      internal let identifier: String
      internal let label: String
      internal let title: String
      internal let value: String
      internal let isEnabled: Bool
      internal let frame: NSRect

      internal var spokenText: String {
        [label, title, value]
          .filter { !$0.isEmpty }
          .joined(separator: " | ")
      }

      internal var description: String {
        let roleName = role?.rawValue ?? "none"
        return
          "role=\(roleName) id=\(identifier) label=\(label) title=\(title) value=\(value) enabled=\(isEnabled)"
      }
    }

    internal static func noOp() {
      _ = ()
    }

    internal static func ignoreURL(_ url: URL) {
      _ = url
    }

    internal static func acceptURLs(_ urls: [URL]) -> Bool {
      !urls.isEmpty
    }

    internal static func inspect<Content: View>(_ view: Content) async -> [AccessibleNode] {
      await inspect(view, localeIdentifier: "en")
    }

    /// Hosts `view` in an off-screen buffered window, lets SwiftUI tasks
    /// settle, and returns the flattened accessibility tree in traversal order.
    internal static func inspect<Content: View>(
      _ view: Content,
      localeIdentifier: String
    ) async -> [AccessibleNode] {
      NSApp?.setValue(true, forKey: "accessibilityEnhancedUserInterface")
      let localizedView = view.environment(\.locale, Locale(identifier: localeIdentifier))
      let hosting = NSHostingView(rootView: localizedView)
      let frame = NSRect(
        x: .zero,
        y: .zero,
        width: WindowMetrics.width,
        height: WindowMetrics.height
      )
      hosting.frame = frame
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      defer {
        window.contentView = nil
        window.close()
      }

      hosting.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      try? await Task.sleep(nanoseconds: WindowMetrics.settleNanoseconds)
      hosting.layoutSubtreeIfNeeded()
      window.displayIfNeeded()

      var collected: [AccessibleNode] = []
      var visited = Set<ObjectIdentifier>()
      collectNodes(from: hosting, into: &collected, visited: &visited)
      return collected
    }

    private static func collectNodes(
      from element: AnyObject,
      into nodes: inout [AccessibleNode],
      visited: inout Set<ObjectIdentifier>
    ) {
      let identity = ObjectIdentifier(element)
      guard visited.insert(identity).inserted else { return }

      let role = element.accessibilityRole?()
      let identifier = element.accessibilityIdentifier?() ?? ""
      let label = element.accessibilityLabel?() ?? ""
      let title = element.accessibilityTitle?() ?? ""
      let valueSelector = #selector(NSAccessibilityProtocol.accessibilityValue)
      let rawValue: Any? =
        (element as? any NSAccessibilityProtocol)?.accessibilityValue()
        ?? (element.responds(to: valueSelector)
          ? element.perform(valueSelector)?.takeUnretainedValue()
          : nil)
      let value = (rawValue as? String) ?? (rawValue.map { String(describing: $0) } ?? "")
      let enabled = element.isAccessibilityEnabled?() ?? true
      let frame = element.accessibilityFrame?() ?? .zero

      if role != nil || !identifier.isEmpty || !label.isEmpty || !title.isEmpty || !value.isEmpty {
        nodes.append(
          AccessibleNode(
            role: role,
            identifier: identifier,
            label: label,
            title: title,
            value: value,
            isEnabled: enabled,
            frame: frame
          )
        )
      }

      let childrenSelector = #selector(NSAccessibilityProtocol.accessibilityChildren)
      let children: [AnyObject] =
        (element.responds(to: childrenSelector)
          ? element.perform(childrenSelector)?.takeUnretainedValue() as? [AnyObject]
          : nil)
        ?? []
      for child in children {
        collectNodes(from: child, into: &nodes, visited: &visited)
      }
      if let view = element as? NSView {
        for subview in Array(view.subviews) {
          collectNodes(from: subview, into: &nodes, visited: &visited)
        }
      }
    }

    @Test("CredentialOutcomeText exposes its message as the accessibility label in every tone")
    internal func credentialOutcomeTextExposesSpokenLabel() async {
      let failureNodes = await Self.inspect(
        CredentialOutcomeText(
          message: "Signature PIN 2 is incorrect.\n4 attempts remaining.",
          tone: .failure
        )
      )
      #expect(
        failureNodes.contains { node in
          node.spokenText.contains("Signature PIN 2 is incorrect.")
            && node.spokenText.contains("4 attempts remaining.")
        }
      )

      let noticeNodes = await Self.inspect(
        CredentialOutcomeText(
          message: "Basic PIN 1 is blocked. Reset it with the PUK.",
          tone: .notice
        )
      )
      #expect(noticeNodes.speaks("Basic PIN 1 is blocked. Reset it with the PUK."))

      let successNodes = await Self.inspect(
        CredentialOutcomeText(
          message: "Basic PIN 1 changed.",
          tone: .success
        )
      )
      #expect(successNodes.speaks("Basic PIN 1 changed."))
    }

    @Test("No-card status window speaks reader guidance and hides card controls")
    internal func noCardJourneySpeaksReaderGuidance() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .absent)
      defer { demo.deactivate() }

      let nodes = await Self.inspect(StatusView())
      #expect(nodes.speaks("Connect a card reader."))
      #expect(!nodes.hasIdentifier("manageCard"))
      #expect(!nodes.hasIdentifier("documentDropArea"))
      #expect(!nodes.hasIdentifier("remoteUseSwitch"))
      #expect(!nodes.hasIdentifier("pairingCodeField"))
    }

    @Test("Ready local card window exposes holder, PIN Codes key, and document chooser")
    internal func readyLocalCardJourneyExposesHolderAndDropInvitation() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let statusNodes = await Self.inspect(StatusView())
      let holderIndex = statusNodes.firstIndex { node in
        node.spokenText.contains("DOE JANE")
          || node.spokenText.contains("ESIMERKKI ERJA")
          || node.spokenText.contains("EXEMPEL EVA")
      }
      let dropIndex = statusNodes.firstIndex { node in
        node.identifier == "documentDropArea"
          || node.spokenText.contains("Drop documents here to sign them.")
      }
      #expect(holderIndex != nil, "holder identity is spoken")
      #expect(dropIndex != nil, "document drop area is spoken")
      if let holderIndex, let dropIndex {
        #expect(holderIndex < dropIndex, "holder identity precedes document drop area")
      }
      #expect(
        statusNodes.hasIdentifier("signChooseDocument") || statusNodes.speaks("Choose…"),
        "keyboard and VoiceOver file chooser button is reachable"
      )

      let buttonNodes = await Self.inspect(PinCodesButton())
      #expect(buttonNodes.containsSpokenControl(identifier: "manageCard", spoken: "PIN Codes"))
    }

    @Test("Document signing pile and format picker expose queue controls")
    internal func documentSigningQueueJourneyExposesControls() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let firstDocument = URL(filePath: "/documents/Agreement.pdf")
      let secondDocument = URL(filePath: "/documents/Appendix.pdf")
      let nonPdfDocument = URL(filePath: "/documents/Notes.txt")

      let pileNodes = await Self.inspect(
        SignDocumentPile(
          documents: [firstDocument, secondDocument],
          remove: Self.ignoreURL,
          add: Self.noOp,
          clear: Self.noOp
        )
      )
      #expect(pileNodes.speaks("Documents to sign"))
      #expect(pileNodes.speaks("Agreement.pdf"))
      #expect(pileNodes.speaks("Remove Agreement.pdf"))
      #expect(pileNodes.speaks("Appendix.pdf"))
      #expect(pileNodes.speaks("Remove Appendix.pdf"))
      #expect(pileNodes.speaks("Add…"))
      #expect(pileNodes.speaks("Clear"))

      let queuedSigning = SignDocumentModel()
      queuedSigning.accept([firstDocument, secondDocument])
      let sectionNodes = await Self.inspect(
        Form {
          StatusDocumentSection(
            signing: queuedSigning,
            format: .constant(.pades),
            offersSigning: true,
            onChoose: Self.noOp,
            onAccept: Self.acceptURLs
          )
        }
      )
      #expect(sectionNodes.hasIdentifier("documentDropArea"))
      #expect(sectionNodes.speaks("Remove Agreement.pdf"))
      #expect(sectionNodes.containsSpokenControl(identifier: "signChooseDocument", spoken: "Add…"))
      #expect(sectionNodes.speaks("Clear"))

      let pdfFormatNodes = await Self.inspect(
        SignatureFormatRow(documents: [firstDocument, secondDocument], format: .constant(.pades))
      )
      #expect(pdfFormatNodes.containsFormatControl(isEnabled: true))

      let mixedFormatNodes = await Self.inspect(
        SignatureFormatRow(documents: [firstDocument, nonPdfDocument], format: .constant(.asice))
      )
      #expect(mixedFormatNodes.containsFormatControl(isEnabled: false))
    }
  }

  extension Array where Element == MacVoiceOverJourneysTests.AccessibleNode {
    internal func speaks(_ substring: String) -> Bool {
      contains { $0.spokenText.contains(substring) }
    }

    internal func hasIdentifier(_ identifier: String) -> Bool {
      contains { $0.identifier == identifier }
    }

    internal func containsSpokenControl(identifier: String, spoken: String) -> Bool {
      contains { node in
        node.identifier == identifier && node.spokenText.contains(spoken)
      }
    }

    internal func containsDisabledControl(identifier: String) -> Bool {
      contains { node in
        node.identifier == identifier && !node.isEnabled
      }
    }

    internal func containsDisabledSpokenControl(identifier: String, spoken: String) -> Bool {
      contains { node in
        node.identifier == identifier && node.spokenText.contains(spoken) && !node.isEnabled
      }
    }

    internal func containsFormatControl(isEnabled: Bool) -> Bool {
      contains { node in
        (node.identifier == "signatureFormat" || node.role == .popUpButton)
          && node.isEnabled == isEnabled
      }
    }
  }

#endif
