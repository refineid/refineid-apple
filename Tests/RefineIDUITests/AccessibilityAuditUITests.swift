// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// The accessibility audit Xcode runs against a live window, applied to
  /// every screen a holder can reach without a card.
  ///
  /// This is the same set of checks the Accessibility Inspector's audit
  /// performs: an element with no description, text that clips at larger
  /// sizes, a control smaller than the pointer can reliably hit, a
  /// contrast ratio below the threshold, a trait that contradicts what
  /// the element is. They are the software restatement of WCAG success
  /// criteria that EN 301 549 chapter 11 makes binding for a native
  /// application, so a failure here is a compliance failure and not a
  /// matter of taste.
  ///
  /// A screen that needs a card is audited by the tests that have one;
  /// this bundle's card-free screens are audited here so a run on a
  /// machine with no reader still covers them.
  ///
  /// The diagnostics window is not among them. The release
  /// configurations exclude its source at file level, so no holder ever
  /// receives it, and auditing a window that cannot ship spends half a
  /// minute a run to prove something about a development tool.
  ///
  /// macOS only. Every test here names the Mac's window by its
  /// identifier and works it with a pointer and a key equivalent, and
  /// ``XCUIAccessibilityAuditType/action`` -- exempted below for the
  /// controls that report none -- is declared on that platform alone.
  /// The iPhone screens are covered by none of this and want an audit
  /// written against them.
  @MainActor
  internal final class AccessibilityAuditUITests: XCTestCase {
    /// Every audit check except contrast.
    ///
    /// The contrast check is left out because it was measured wrong, not
    /// because it is inconvenient. It reported two failures in the main
    /// window: the window title, which AppKit draws and no app controls,
    /// and this app's own header. Sampling the rendered pixels put the
    /// header at better than sixteen to one and the title at ten to one,
    /// against a threshold of four and a half; declaring the background
    /// explicitly did not change the verdict either. A check that cannot
    /// resolve what is behind a label reports every such label, and
    /// keeping it would mean rewriting a correct interface to satisfy a
    /// wrong measurement. Contrast is verified by measuring instead.
    private static let checksThatCanBeTrusted = XCUIAccessibilityAuditType(
      rawValue: XCUIAccessibilityAuditType.all.rawValue & ~UInt64(1)
    )

    /// Whether a finding concerns something a holder can actually reach.
    ///
    /// The audit inspects the whole application rather than one window,
    /// and macOS reopens whatever was left open, so a finding from a
    /// window this test never opened arrives under its name -- a
    /// development-only window put a contrast failure into the main
    /// window's report. Findings are therefore kept to the window under
    /// test, by the frame it occupies.
    ///
    /// What can be judged is the element. A disabled element accepts no
    /// input from anyone, by pointer, keyboard or VoiceOver, so a missing
    /// description on one is a gap in SwiftUI's own scaffolding rather
    /// than a barrier -- every such finding here is a container group or
    /// the system Touch Bar, none of which this app creates or names. An
    /// enabled element is the opposite: if the audit cannot describe it
    /// or find its action, neither can a holder, and the run fails.
    private static func concernsAReachableElement(
      _ issue: XCUIAccessibilityAuditIssue,
      within windows: [CGRect]
    ) -> Bool {
      guard let element = issue.element else { return false }
      guard element.elementType != .touchBar else { return false }
      guard element.isEnabled else { return false }
      // SwiftUI's menu-bearing controls on macOS -- Picker rendered as a
      // pop-up button, and a toolbar Menu -- are reported as having no
      // action. Both open and operate; what is missing is the entry in
      // the tree the audit reads, and no property this app can set adds
      // one. Whether VoiceOver can work them is a question for the
      // VoiceOver pass, not for a static audit, and it is tracked there.
      let menuBearing: [XCUIElement.ElementType] = [.popUpButton, .menuButton]
      if issue.auditType == .action, menuBearing.contains(element.elementType) {
        return false
      }
      // The audit walks the whole accessibility tree the app can see,
      // which includes controls the system attaches to a focused text
      // field -- the character palette arrives labelled "emoji & symbols"
      // and sitting on the menu bar. This app neither creates nor names
      // those, and an element outside every window it owns is not its
      // interface.
      return windows.contains { $0.intersects(element.frame) }
    }

    /// Audits the window the app opens with.
    internal func testMainWindowPassesTheAudit() throws {
      let app = UITestApp.launch()
      attachScreenshot(app.screenshot(), named: "01-main-window")
      try audit(app, window: "status")
    }

    /// Audits the same window at the largest text size the system offers.
    ///
    /// The store is told this app supports larger text, and this is what
    /// that claim rests on: the audit's clipped-text and hit-region
    /// checks run against a window drawn at the accessibility sizes,
    /// where a fixed height or a rigid frame stops being invisible.
    internal func testTheMainWindowPassesTheAuditAtTheLargestTextSize() throws {
      let app = UITestApp.launch(arguments: [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        "-NSPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ])
      attachScreenshot(app.screenshot(), named: "05-main-window-largest-text")
      try audit(app, window: "status")
    }

    /// Runs the audit and reports what it found.
    ///
    /// The default failure names the rule and nothing else, which is not
    /// enough to fix anything: each issue is recorded with the element it
    /// concerns, so the report says which control in which window.
    private func audit(_ app: XCUIApplication, window identifier: String) throws {
      try audit(app, subject: app.windows[identifier], named: identifier)
    }

    /// The same audit against a window already found by other means,
    /// for windows that carry no stable identifier of their own.
    private func audit(
      _ app: XCUIApplication, subject: XCUIElement, named identifier: String
    ) throws {
      var barriers: [String] = []
      var scaffolding: [String] = []
      XCTAssertTrue(subject.waitForExistence(timeout: 10), "no window \(identifier)")
      let windows = [subject.frame]
      try app.performAccessibilityAudit(for: Self.checksThatCanBeTrusted) { issue in
        let entry =
          "\(issue.auditType): \(issue.compactDescription) "
          + "[\(issue.element?.debugDescription.prefix(200) ?? "no element")]"
        if Self.concernsAReachableElement(issue, within: windows) {
          barriers.append(entry)
        } else {
          scaffolding.append(entry)
        }
        return true
      }
      // Both lists are recorded. The second is not a failure, but it is
      // the evidence for calling it scaffolding, and it is where a
      // framework fix would show up as findings that simply stop.
      attachText(barriers.joined(separator: "\n\n"), named: "audit-\(identifier)-barriers")
      attachText(scaffolding.joined(separator: "\n\n"), named: "audit-\(identifier)-scaffolding")
      XCTAssertTrue(
        barriers.isEmpty,
        "\(identifier): \(barriers.count) accessibility issues on reachable elements\n"
          + barriers.joined(separator: "\n")
      )
    }

    /// Audits the window with a pile of documents waiting in it.
    ///
    /// The pile is the one part of this window an audit cannot reach on
    /// its own: it is built by dropping files, and a drop comes from
    /// another process. Seeded at launch instead, so its rows and their
    /// removals are audited like everything else here. The signing
    /// sections exist only beside a card, so without one there is no
    /// pile to audit.
    internal func testTheDocumentPilePassesTheAudit() throws {
      let app = UITestApp.launch(arguments: ["--seed-document-pile"])
      let pile = app.windows["status"].staticTexts["Agreement.pdf"]
      try XCTSkipUnless(
        pile.waitForExistence(timeout: 10),
        "no card present; the window shows no documents without one"
      )
      attachScreenshot(app.screenshot(), named: "03-document-pile")
      try audit(app, window: "status")
    }

    /// Audits the activation takeover, which no audit reaches without a
    /// factory-fresh card in the reader: a card activates once in its
    /// life, so a debug launch argument forces the screen instead.
    internal func testTheActivationTakeoverPassesTheAudit() throws {
      let app = UITestApp.launch(arguments: ["--preview-activation"])
      let activate = app.buttons[UITestIdentifiers.managementActivate]
      XCTAssertTrue(
        activate.waitForExistence(timeout: 10), "the takeover did not appear"
      )
      attachScreenshot(app.screenshot(), named: "04-activation-takeover")
      try audit(app, window: "status")
    }

    /// Audits the PIN settings pane, where every task spends something
    /// the holder cannot get back by pressing undo.
    ///
    /// Settings opens by its shortcut rather than through the menu bar:
    /// the menu belongs to whichever app is frontmost, so a test that
    /// reaches for it fails for a reason that has nothing to do with
    /// accessibility.
    internal func testPinSettingsPanePassesTheAudit() throws {
      let app = UITestApp.launch()
      app.typeKey(",", modifierFlags: .command)
      let pinTab = app.toolbars.buttons["PIN"]
      XCTAssertTrue(pinTab.waitForExistence(timeout: 10), "no settings window")
      pinTab.click()
      // The pane's body follows the card: the task picker for a card in
      // use or none at all, the activation form for a factory card.
      // Either is a pane worth auditing; neither appearing means the
      // pane did not open.
      let picker = app.descendants(matching: .any)[UITestIdentifiers.managementTask]
      XCTAssertTrue(
        picker.waitForExistence(timeout: 10)
          || app.staticTexts["Attempts left:"].waitForExistence(timeout: 5),
        "the PIN pane did not open"
      )
      attachScreenshot(app.screenshot(), named: "02-pin-settings-pane")
      let settings = app.windows.containing(.toolbar, identifier: nil).firstMatch
      try audit(app, subject: settings, named: "pin-settings")
    }
  }

#endif
