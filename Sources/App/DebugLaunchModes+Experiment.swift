// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation

  extension DebugLaunchModes {
    /// Dispatches on-demand PIN1 experiment debug modes.
    internal static func experimentReport(for mode: DebugLaunchMode) -> DebugModeReport {
      switch mode {
      case .forgetPin1:
        forgetPin1()
      case .enableOnDemandPin:
        enableOnDemandPin()
      case .disableOnDemandPin:
        disableOnDemandPin()
      case .statusOnDemandPin:
        statusOnDemandPin()
      default:
        DebugModeReport(lines: [], succeeded: false)
      }
    }

    /// Drops stored PIN1, returning to on-demand collection for logins.
    private static func forgetPin1() -> DebugModeReport {
      CardCredentialStore.forgetPin1()
      let remains = CardCredentialStore.contents().hasPin1
      return DebugModeReport(
        lines: ["forget-pin1: " + (remains ? "stored PIN1 remains" : "PIN1 cleared")],
        succeeded: !remains)
    }

    /// Enables the experimental on-demand PIN1 authentication flow.
    private static func enableOnDemandPin() -> DebugModeReport {
      let saved = OnDemandPinExperiment.setEnabled(true)
      let enabled = OnDemandPinExperiment.isEnabled
      return DebugModeReport(
        lines: ["enable-ondemand-pin: " + (saved && enabled ? "enabled" : "failed to enable")],
        succeeded: saved && enabled)
    }

    /// Disables the experimental on-demand PIN1 authentication flow.
    private static func disableOnDemandPin() -> DebugModeReport {
      let saved = OnDemandPinExperiment.setEnabled(false)
      let enabled = OnDemandPinExperiment.isEnabled
      return DebugModeReport(
        lines: ["disable-ondemand-pin: " + (saved && !enabled ? "disabled" : "failed to disable")],
        succeeded: saved && !enabled)
    }

    /// Reports current on-demand PIN1 experiment status.
    private static func statusOnDemandPin() -> DebugModeReport {
      let enabled = OnDemandPinExperiment.isEnabled
      let contents = CardCredentialStore.contents()
      return DebugModeReport(
        lines: [
          "status-ondemand-pin: enabled=\(enabled)",
          "hasCardAccessNumber: \(contents.hasCardAccessNumber)",
          "hasPin1: \(contents.hasPin1)",
        ],
        succeeded: true)
    }
  }

#endif
