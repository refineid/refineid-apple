# macOS accessibility and VoiceOver assessment

Checked 2026-09-30 against source commit `83544ca2cc671668f52427ea69a477fb6e22469d`. Environment: Apple silicon, macOS 27.0; Debug app with macOS remote features excluded. This is an assessment of the current implementation and test evidence, not approval of a TestFlight artifact.

**Assessment: useful accessibility foundations, but insufficient evidence for complete VoiceOver support.** The recorded accessibility test run failed. A concrete missing success announcement and gaps in the test coverage need attention.

## Findings

1. **Successful document signing has no explicit VoiceOver completion announcement.** StatusView observes failure and notice messages for announcements, but successful completion sets `signed`, clears the queue, and removes signing controls without observing those changes for an announcement. Batch outcomes are recorded but not presented in StatusView. This is a source-confirmed missing notification path; actual spoken behavior and cursor movement were not measured. Add a concise completion message, including partial batch failures, and verify focus remains useful after the controls disappear. See [StatusView announcements](https://github.com/refineid/refineid-apple/blob/83544ca2cc671668f52427ea69a477fb6e22469d/Sources/App/StatusView.swift#L126) and [completion handling](https://github.com/refineid/refineid-apple/blob/83544ca2cc671668f52427ea69a477fb6e22469d/Sources/App/StatusView.swift#L333).

2. **The existing accessibility tests do not reach their intended windows.** The baseline run had 3 passes, 4 failures and 3 skips. All three localized MacMvp checks passed. Four accessibility tests failed before auditing the target screen: main window missing, settings main window missing, activation takeover missing, and enlarged-text main window missing. The document-pile audit and both keyboard tests skipped. The existing audit relies on `app.windows["status"]`; the working MVP test explicitly opens the Window-menu item and finds the live window. Fix the launch/window-selection harness and use deterministic virtual-card states for card-dependent checks. The keyboard test named "EveryControl" currently checks only one management button.

3. **Current audit filtering is too broad to establish full accessibility.** It omits contrast, all disabled elements, findings with no element, and action findings for pop-up/menu buttons. Disabled controls and static content can still need meaningful screen-reader descriptions. Parent/child errors with no element should be retained for investigation. The enlarged-text test sets launch arguments but does not assert that font size or rendered geometry changed. See [audit filters](https://github.com/refineid/refineid-apple/blob/83544ca2cc671668f52427ea69a477fb6e22469d/Tests/RefineIDUITests/AccessibilityAuditUITests.swift#L48).

4. **The document-queue audit requires investigation.** A temporary probe using the working window-opening path collected every audit type, including contrast. Across English, Finnish and Swedish, the simple local-card screen reported unnamed group and Touch Bar elements only. With four fictional documents queued, the audit consistently reported a parent/child mismatch without an identified element, an unnamed disabled group, a missing action on the disabled format pop-up, and an unnamed Touch Bar. These are raw findings, not confirmed user barriers. A later English probe additionally reported six contrast findings; the earlier queue probes did not, so contrast is not cleared and needs element identification and rendered-color measurement. Settings-inclusive audits timed out in all three languages. A follow-up attempt to close the main window first failed to open Settings. Neither timeout nor launch failure is evidence that the app is inherently inaccessible or that auditing it is impossible.

5. **macOS document verification is absent from the inspected UI.** VerifyDocumentView and VerifyDocumentModel are compiled only for iOS, and no macOS route to DocumentVerification was found. Consequently, macOS verification accessibility could not be audited. See [platform guard](https://github.com/refineid/refineid-apple/blob/83544ca2cc671668f52427ea69a477fb6e22469d/Sources/App/VerifyDocumentView.swift#L3).

## What is already present

- Native SwiftUI/AppKit controls and native file dialogs; choosing files is an alternative to drag and drop.
- Document filenames retained in spoken labels; each removal button identifies its document.
- Secure input fields, localized reveal/hide labels, validation descriptions, and form focus/Return handling.
- Retry indicators combine credential names with spoken remaining/blocked/unknown states and do not rely on color alone.
- Card-management and signing failure/notice paths post accessibility announcements.
- Reduced Motion is respected by the contactless refusal shake and retry-health animation.
- A probe verified that the signing secure field exists and has a nonempty accessibility label in English, Finnish and Swedish. No credential value was entered or recorded.

These implementation facts support accessibility, but do not prove correct speech, reading order, menu operation or modal focus behavior.

## Evidence and limits

The following summaries preserve the recorded outcomes. Raw result bundles,
recordings and temporary probe instrumentation are retained locally rather than
versioned. They contain machine-specific metadata. The application source was
unchanged; temporary probe edits to MacMvpUITests were restored after inspection.

| Run | Passed | Failed | Skipped | Scope and outcome |
| --- | ---: | ---: | ---: | --- |
| Unchanged baseline | 3 | 4 | 3 | Localized MVP checks passed; accessibility windows were not reached; document-pile and keyboard checks skipped. |
| Simple-screen probe | 3 | 0 | 0 | All audit types collected in English, Finnish and Swedish; unnamed group and Touch Bar findings. |
| Document queue and Settings probe | 0 | 3 | 0 | Named signing field checked in all three languages; queue findings collected; Settings-inclusive audits timed out. |
| Settings isolation attempt | 0 | 1 | 0 | English queue findings collected, including six contrast findings; Settings did not open after closing the main window. |

The unchanged baseline can be rerun at the assessed commit with:

```sh
xcodebuild test -scheme RefineID -destination 'platform=macOS' \
  -only-testing:RefineIDUITests/AccessibilityAuditUITests \
  -only-testing:RefineIDUITests/KeyboardOperationUITests \
  -only-testing:RefineIDUITests/MacMvpUITests \
  -resultBundlePath build/accessibility-audit.xcresult -quiet
```

The temporary probes opened the main window through its Window-menu item,
launched the `activated-reader` virtual scenario with diagnostics hidden, and
collected `.all` audit findings without filtering. The queued-document variant
also used `--seed-document-pile`, checked the signing secure field's nonempty
label, and opened Settings using Command-comma. No credential values were entered.
Raw findings recorded audit type, element type, enabled state and intersection
with the selected window, without recording credential contents.


The probes collect findings rather than asserting that findings are absent, so their successful test status is not an accessibility pass. The window query used by the temporary multi-window probe was not pinned to a stable window identity, which further limits per-window attribution. This assessment is historical evidence for the named commit, not a claim about subsequent commits. The automated audits cover only the scenarios stated above. Light appearance, increased contrast, effective larger text, activation/recovery/confirmation journeys, real-card system prompts, and an exact shipping candidate remain unverified in this assessment.

A live VoiceOver journey was not completed: native inspection through the available computer-use tool timed out. This is a tooling observation, not a platform or app-impossibility claim. A proficient VoiceOver pass must still check reading order, format selection, secure-field labels, file dialogs, confirmation/cancellation, retry-floor guidance, errors, completion and cursor placement using fictional state.

[Apple's VoiceOver evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/) require users to complete common tasks using VoiceOver without sighted assistance; automated labels and audit results alone do not establish that standard. [Apple's audit guidance](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app/) likewise distinguishes audit checks from complete assistive-technology testing.
