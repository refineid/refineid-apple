// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// A read-only technical report for support and development.
///
/// A native list owns scrolling, safe areas, and Dynamic Type. Report
/// actions live in the navigation toolbar; card removal belongs on setup.
internal struct DiagnosticsView: View {
  // Two seconds is long enough to notice without leaving stale feedback.
  private static let copyFeedbackDuration: Duration =
    .seconds(1) + .seconds(1)

  @State private var snapshot: DiagnosticsSnapshot?
  @State private var reportCopied = false
  @State private var clearMessage: String?
  @State private var clearSucceeded = true
  @State private var showsClearConfirmation = false
  @State private var capabilityLines: [String] = []
  @State private var isProbingCapabilities = false

  internal var body: some View {
    List {
      if let clearMessage {
        Section {
          Label(
            clearMessage,
            systemImage: clearSucceeded
              ? "checkmark.circle" : "exclamationmark.triangle"
          )
          .foregroundStyle(clearSucceeded ? Color.secondary : Color.red)
        }
      }
      #if REFINEID_LOCAL_CARD && os(iOS)
        capabilitySection
      #endif
      if let snapshot {
        ForEach(snapshot.sections, id: \.title) { section in
          reportSection(section)
        }
      } else {
        Section {
          HStack {
            ProgressView()
            Text("Reading report")
          }
        }
      }
      clearLogsSection
      testCredentialsSection
      experimentSection
    }
    // The list is the window's whole content and takes keyboard focus
    // on open, so without a name of its own VoiceOver announces the
    // focused element as an unnamed outline.
    .accessibilityLabel("Diagnostic report")
    .navigationTitle("Diagnostics")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar { toolbarContent }
    .task { refresh() }
    // An alert, not a confirmation dialog: a dialog is presented as a
    // popover anchored to its source, which drops the cancel action and
    // was measured landing over the navigation bar, far from the button
    // that opened it. An alert is centered and always keeps both.
    .alert(
      "Clear diagnostic logs?",
      isPresented: $showsClearConfirmation
    ) {
      Button("Clear", role: .destructive) {
        clearLogs()
      }
      Button("Cancel", role: .cancel) {
        // The system dismisses the alert.
      }
    } message: {
      Text(
        """
        This clears RefineID's diagnostic trace. It does not remove your \
        card details or Safari identity.
        """)
    }
  }

  /// Refresh stays a button; the two report exports share one menu, so
  /// the bar keeps two controls instead of three and the title fits.
  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        refresh()
      } label: {
        Label("Refresh report", systemImage: "arrow.clockwise")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Button {
          copyReport()
        } label: {
          Label("Copy report", systemImage: "doc.on.doc")
        }
        ShareLink(item: reportText) {
          Label("Share report", systemImage: "square.and.arrow.up")
        }
      } label: {
        Label(
          reportCopied ? "Report copied" : "Report actions",
          systemImage: reportCopied ? "checkmark" : "square.and.arrow.up")
      }
      // Measured through the accessibility API: the menu was announced
      // as "Share", a name the system took from the share symbol and
      // the ShareLink inside it. The menu offers copying as well, and a
      // control that names one of the two things it does sends anyone
      // looking for the other one past it.
      .accessibilityLabel("Report actions")
      .disabled(snapshot == nil)
    }
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// Asks the card what suites it supports and times the one in use.
    ///
    /// A card operation, so it is a deliberate action rather than part
    /// of collecting the report: it opens an NFC field and asks the
    /// holder to hold the card.
    @ViewBuilder private var capabilitySection: some View {
      Section {
        Button {
          probeCapabilities()
        } label: {
          if isProbingCapabilities {
            HStack {
              ProgressView()
              Text("Reading the card")
            }
          } else {
            Label("Read card capabilities", systemImage: "wave.3.right")
          }
        }
        .disabled(isProbingCapabilities)
        .accessibilityIdentifier("capabilityProbeButton")
        if !capabilityLines.isEmpty {
          ScrollView(.horizontal) {
            Text(verbatim: capabilityLines.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
          .scrollIndicators(.hidden)
        }
      } header: {
        Text("Card capabilities")
      } footer: {
        Text("Reads EF.CardAccess and times one PACE handshake.")
      }
    }
  #endif

  /// Trace removal is separate from report reading and requires
  /// confirmation because it removes evidence from the previous attempt.
  private var clearLogsSection: some View {
    Section {
      Button("Clear diagnostic logs", role: .destructive) {
        showsClearConfirmation = true
      }
    } footer: {
      Text("Clears only RefineID's diagnostic trace.")
    }
  }

  private var testCredentialsSection: some View {
    Section {
      Button("Prime Mock Test Card (DOE JANE)") {
        MockCardCertificate.primeSyntheticIdentity()
        clearMessage = "Primed mock test certificate (DOE JANE 12345678N)."
        clearSucceeded = true
        refresh()
      }
      Button("Forget All Primed Cards", role: .destructive) {
        _ = CardStateReset.perform()
        CardCredentialStore.forgetAll()
        clearMessage = "Cleared all primed card credentials."
        clearSucceeded = true
        refresh()
      }
    } header: {
      Text("Test Credentials")
    } footer: {
      Text(
        "Primes a synthetic test identity for remote card pairing and testing without a physical card."
      )
    }
  }

  private var experimentSection: some View {
    Section {
      Toggle(
        "On-Demand PIN 1 Experiment",
        isOn: Binding(
          get: { OnDemandPinExperiment.isEnabled },
          set: { enabled in
            _ = OnDemandPinExperiment.setEnabled(enabled)
            refresh()
          }
        )
      )
      .accessibilityIdentifier("onDemandPinExperimentToggle")
    } header: {
      Text("Experimental Features")
    } footer: {
      Text(
        "Collects PIN 1 on demand via native sheet during Safari authentication instead of storing it."
      )
    }
  }

  /// What the share and copy actions carry.
  ///
  /// The capability probe's answer is evidence like every other section,
  /// and a section that can only be photographed off the screen is a
  /// section nobody can paste into a report.
  private var reportText: String {
    let collected = snapshot?.text ?? ""
    guard !capabilityLines.isEmpty else { return collected }
    let probed = (["== Card capabilities =="] + capabilityLines).joined(separator: "\n")
    return collected.isEmpty ? probed : collected + "\n\n" + probed
  }

  /// One selectable, monospaced report block.
  ///
  /// The block scrolls sideways rather than wrapping: these are fixed
  /// columns of status words and identifiers, and a wrapped line reads
  /// as two records instead of one.
  private func reportSection(_ section: DiagnosticsSnapshot.Section) -> some View {
    Section {
      ScrollView(.horizontal) {
        Text(verbatim: section.lines.joined(separator: "\n"))
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
      .scrollIndicators(.hidden)
    } header: {
      Text(verbatim: section.title)
    }
  }

  private func refresh() {
    snapshot = DiagnosticsSnapshot.collect()
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    /// Runs the capability probe, then refreshes so the new trace lines
    /// it wrote are on screen with it.
    private func probeCapabilities() {
      guard !isProbingCapabilities else { return }
      isProbingCapabilities = true
      capabilityLines = []
      Task {
        capabilityLines = await CardCapabilityProbe.run()
        isProbingCapabilities = false
        refresh()
      }
    }
  #endif

  private func copyReport() {
    guard snapshot != nil else { return }
    DiagnosticsClipboard.copy(reportText)
    reportCopied = true
    Task {
      try? await Task.sleep(for: Self.copyFeedbackDuration)
      reportCopied = false
    }
  }

  private func clearLogs() {
    let status = ExtensionTrace.clear()
    clearSucceeded = status == errSecSuccess || status == errSecItemNotFound
    clearMessage =
      clearSucceeded
      ? String(localized: "Diagnostic logs cleared.")
      : String(localized: "The keychain refused to clear the logs (\(Int(status))).")
    refresh()
  }
}

#Preview {
  NavigationStack {
    DiagnosticsView()
  }
}
