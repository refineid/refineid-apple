# Virtual ID Card test framework

## Purpose

Virtual ID Card is the deterministic card and device harness for the RefineID
Apple platforms (iOS, iPadOS, and macOS) UI. It exists for three jobs:

1. Exercise state-machine behavior without spending attempts on a physical card.
2. Give App Store Review an explicit, fictional card whose state can be edited.
3. Run repeatable unit and UI tests on local simulators, Macs, and Xcode Cloud.

It is not a second product UI. Demo-mode CardMaintenance calls are routed to a
VirtualIDCard actor and the normal activation, PIN-change, PIN-reset, retry-floor,
and outcome views consume the resulting production types.

## Isolation boundary

Virtual mode is opt-in for one process. The App Store build enters it through:
- iOS: the Demonstration Home Screen quick action.
- macOS: the "Explore with a Virtual Demo Card" action in the empty-state window
  or "Demo Mode" menu item.
- Debug UI tests: `--virtual-card <scenario>`.

The physical path remains the default. While virtual mode is active:

- CardMaintenance never falls through to CryptoTokenKit or Core NFC.
- No CAN or PIN is written to Keychain.
- No PrimeStore identity is written.
- No CryptoTokenKit token is registered.
- No production diagnostics or log is created.
- Quitting the process destroys virtual card and device state.

Every built-in name, identifier, serial, CAN, PIN, PUK, activation entry, and
certificate status is fictional.

## State model

Card state and device state are separate.

Card state contains:

- Transport, reader connection, and card presence.
- Card generation and activation method.
- CAN and activation entry.
- PIN 1, PIN 2, and PUK values and independent retry counters.
- Independent PIN 1 and PIN 2 factory flags.
- Holder name, electronic client identifier (SATU/PEUIN), and token serial.
- Authentication and signature certificate states.

Device state contains:

- Stored CAN and the connection-validated, session-only CAN.
- Whether PIN 1 has been accepted for storage.
- Whether identity metadata is cached.
- Whether the virtual token is registered.
- Whether a signing request is pending.

Missing stored CAN means only that this device is not configured. A successful
connection determines whether the card is activated. An already activated card
stores the virtual CAN immediately. A factory card keeps only a session
connection and stores the virtual CAN after both required activation writes
succeed.

## Operation contract

VirtualIDCard implements the operations currently exposed by iOS:

- First connection and wrong-CAN classification.
- Side-effect-free retry probing.
- PIN 1 and PIN 2 change.
- PIN 1 and PIN 2 reset with PUK.
- Independent PIN 1 and PIN 2 activation.
- Authentication-certificate setup with PIN 1.
- Qualified document-signature authorization with PIN 2.

The retry-floor policy is shared in behavior with the product:

- 0 means blocked.
- 1 or 2 is refused without transmitting a credential.
- 3, 4, and 5 may operate.
- A wrong transmitted credential decrements only the credential the card checks.
- A correct change or reset restores the target allowance.

Activation is deliberately non-atomic. PIN 1 and PIN 2 are separate writes and
their factory flags change separately. A fault after PIN 1 executes but before
its reply reaches the app leaves PIN 1 changed and PIN 2 in factory state. The
next connection must therefore offer only the unfinished PIN.

## Fault injection

A fault names:

- The operation that triggers it.
- Whether it happens before a command or after card execution.
- Its effect.
- How many matching occurrences remain.

Before-command faults never mutate card state. After-execution faults preserve
the card mutation while returning transport failure to the app. This distinction
is mandatory for partial activation, retry consumption, and ambiguous NFC-loss
tests.

Initial named effects cover connection loss, reader disconnection, card removal,
timeout, malformed response, and token publication failure. Initial presets
cover:

- NFC loss before connection.
- Reader failure during counter query.
- Card removal before PIN change.
- Lost reply after PIN 1 activation.
- Lost reply after PIN 2 activation.
- Certificate read failure.
- Token publication failure.
- Card removal before a qualified signature command.
- Lost reply after the card authorizes a qualified signature.

Tests use named deterministic presets. Random faults are not accepted in the
required suite because an unreproducible failure is not a useful release gate.

## Test layers

The required harness contract is every modeled scenario, operation, retry
boundary, fault phase, and user-visible language. CardCore supplies exhaustive
transition evidence; XCUITest supplies representative end-to-end UI evidence.
This is deliberately stronger than multiplying every equivalent model state by
every screen and language, which would add runtime without testing another
decision.

### CardCore transition tests

Tests/CardCoreTests/VirtualIDCardTests.swift owns the state-transition matrix.
The initial matrix covers CAN validation, certificate-independent activation
classification, retry values 0 through 5, partial activation, before-command
and after-execution faults, reset behavior, and device/card isolation. This is
the fast layer for adding combinations. It has no SwiftUI, simulator, reader,
NFC, Keychain, or credential dependency.

### XCUITest

Tests/RefineIDUITests/VirtualIDCardUITests.swift enters an empty virtual mode,
opens the floating card, and configures scenarios, faults, credentials, and
retry counters through the visible editor. It then drives the production UI
through activation, authentication, every PIN change/reset operation, reader
identity, qualified document signing, and recovery routing. The signing matrix
covers success, malformed PIN 2 input, wrong PIN 2 with one-attempt
consumption, the retry floor, every unavailable signature-certificate state,
card removal before authorization, and a lost reply after authorization.
Launch arguments enter virtual mode only; they do not inject the finished state
used by these journeys.

Every named scenario and fault preset is selected through the GUI. Exhaustive
counter and fault-phase combinations remain in CardCore because repeating the
same screen journey for every equivalent model permutation would make the UI
suite slower without adding UI evidence.

Automation waits for accessibility state. Production code contains no test
delay, and tests do not synchronize by sleeping.

### Localization and accessibility

The editor has its own string catalog because none of its copy is product card
data. Every entry has English, Finnish, and Swedish localizations. A catalog
gate compares every `virtualCardLocalized` key used by code with the catalog
and rejects a missing key or locale. XCUITest also launches the real app in
Finnish and Swedish and proves that localized accessibility labels reach the
running process. A separate full accessibility audit covers the editor's
labels, traits, hit regions, Dynamic Type, clipping, and contrast without
multiplying the same audit by language.

The floating card is a labeled button rather than an unlabeled visual overlay.
Its accessibility value summarizes transport, card presence, activation, and
retry state. Every editor control has a stable language-independent identifier,
while its VoiceOver label and value remain localized. Tests use identifiers,
never translated visible text, except where the translation itself is the
assertion.

### Physical-card tests

Physical reader and NFC suites remain separate evidence. They verify Apple
transport behavior and real APDU compatibility, which a virtual card cannot
prove. They are not a pull-request prerequisite and never use repository
credentials.

### Extension boundary

The app's qualified document-signing journey is wired end to end through the
same document signer, retry policy, outcome model, and SwiftUI screens as a real
card. Only the physical transport and cryptographic result are simulated; demo
mode never fabricates a file that could be mistaken for a genuine card
signature. Browser and CryptoTokenKit extension virtualization remains outside
this harness, so it does not claim to test Safari signing or the token-extension
lifecycle.

## App Store demonstration

The Demonstration quick action starts a factory-fresh NFC card. A red floating
Virtual ID Card control opens the editor. Reviewers can select named states,
edit all UI-relevant card and device values, choose one deterministic fault,
and apply it. A pending document-signing request supplies a fictional local PDF
so reviewers can exercise the complete signing UI without the Files picker.
The permanent DEMO MODE footer prevents fictional identity data or signing
outcomes from being mistaken for a real card result.

## Xcode Cloud

The shared RefineID scheme already selects RefineID.xctestplan, which contains
CardCoreTests, RefineIDTests, and RefineIDUITests. A Cloud workflow can therefore
run the framework without hardware:

1. Add a Test action for iOS Simulator and the RefineID scheme.
2. Use Scheme Settings so the checked-in test plan controls targets.
3. Run CardCore and one representative iPhone simulator on every pull request.
4. Run the wider simulator/device and accessibility matrix on a schedule.
5. Keep physical-card verification as a separately initiated device run.

Apple documents that Xcode Cloud test actions can use a scheme's settings and
that Cloud runs tests on Simulator. Workflows can start from branch changes,
pull requests, tags, or schedules:

- https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions
- https://developer.apple.com/documentation/xcode/about-continuous-integration-and-delivery-with-xcode-cloud
- https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference

The Cloud workflow itself is configured initially in Xcode or App Store Connect;
the repository supplies the shared scheme, test plan, deterministic scenarios,
and tests it executes.

## Local physical-device execution

An unlocked development iPhone connected by USB, with Developer Mode enabled
and automation trusted, is sufficient. Removing the device passcode is neither
required nor desirable: it changes Keychain protection and makes a security-
sensitive run less representative. Virtual-card tests do not contact the real
card, do not require a reader, and cannot consume a real PIN attempt or activate
a physical card.
