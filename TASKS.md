# Apple release task list

Last reviewed: 2026-11-17. This file holds only outcomes still required for
the next App Store submission or protocol milestone; completed work is
removed. The steps every submission takes, from the hardware smoke check of
the exact candidate to metadata and review notes, are in the
[release runbook](Documentation/release-runbook.md). Release history is in
[Documentation/releases](Documentation/releases).

## Before the next App Store submission

- [ ] Complete the live human VoiceOver and off-screen `RefineIDUITests`
  verification pass on the shipping candidate. Off-screen AppKit accessibility
  tree journeys (`MacVoiceOverJourneysTests`) pass in `RefineIDTests` across
  English, Finnish, and Swedish for no-card, ready local card, document signing
  queue and outcomes, card activation takeover, and the PIN Codes window, and
  end-to-end UI journey suites (`MacActivationJourneyUITests`,
  `MacPinManagementJourneyUITests`, `MacSigningJourneyUITests`,
  `MacDemoModeJourneyUITests`, `AccessibilityAuditUITests`, and
  `KeyboardOperationUITests`) are wired in `RefineIDUITests`. See the
  [September 30 assessment](Documentation/macos-accessibility-assessment-2026-09-30.md)
  for background and remaining live VoiceOver evaluation criteria.

## Engineering references

The [release plan](Documentation/release-plan.md#release-evidence-reconciliation)
records established release evidence. The
[RAPP handoff](Documentation/rapp-implementation-handoff.md) retains protocol
architecture and verification details.
