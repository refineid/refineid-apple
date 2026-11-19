# RefineID for Apple platforms

RefineID makes Finnish identity cards usable through Apple platform security frameworks.

## Current capabilities

On macOS, RefineID uses cards inserted into an attached contact reader for
CryptoTokenKit authentication, card activation, PIN management, and local
PDF (PAdES) and file-package (ASiC-E) signing. Contactless reader use, RAPP
remote-card use, signed document verification UI, and Settings panes are
compiled out in every macOS configuration. Mac signatures have no visible
stamp.

The iPhone and iPad app retains remote-card use, signed document
verification, visible PDF stamps, and a configurable timestamp authority.
iPhone built-in NFC remains enabled; local card use follows the available
[card transports](Documentation/card-transports.md). The localhost signing
service (SCS) and organization-card operations are gated off. The checked-in
[feature configuration](Config/Features.xcconfig) and
[feature-gate guide](Documentation/feature-gates.md) define the platform split.
Code behind a gate does not establish a shipping capability or hardware
acceptance for every card and reader combination.

The card and RAPP engines are independent Swift implementations in
[CardCore](CardCore/Package.swift), following the specifications and
conformance vectors shared with refineid-core. The Apple app does not bind
to its Rust runtime. The [Mac](Documentation/design/macos.md),
[iPhone/iPad](Documentation/design/ios.md), and
[document-verification](Documentation/design/document-verification.md)
designs describe the implementation in more detail.

## Apple App Store Version

Available at https://apps.apple.com/fi/app/refineid/id6796444289

## PIN codes

RefineID remembers PIN 1 in memory, so a login that signs several times
asks for it once. It keeps PIN 1 only while the card reports all of its
PIN 1 tries left, and forgets it when the card refuses it. Otherwise:

- On a Mac with a card reader, the token extension holds it until the card
  leaves the reader or macOS ends the extension; quitting the app does
  not end it.
- On an iPhone or iPad serving a computer, the app holds it until the card
  leaves, another card takes its place, the card's setup is forgotten, or
  the app ends.
- For Safari on an iPhone or iPad, with the card held against it, the
  token extension holds it after the card leaves, until iOS ends the
  extension.

PIN 2 is asked for every signature, or once for a batch of documents
signed together, and is never kept. Neither PIN is written to storage,
and neither leaves the device that holds the card.

Remembering PIN 1 is a deliberate deviation from the FINEID profile
(FINEID S4-1 v4.2, sections 4.1 and 8.1.7), which asks for PIN 1 to be
entered for every authentication. It never applies to PIN 2 or to
qualified signatures.

## Development

Use macOS 26 and an Xcode toolchain supporting Swift 6.3, as required by the
[CardCore](CardCore/Package.swift) and
[PKCS11Bridge](PKCS11Bridge/Package.swift) package manifests. Select that
Xcode for command-line tools and install an iPhone simulator runtime for
the cross-platform test gate. The full gates also use Python 3 and
SwiftLint; the DSS signature-validation gate needs JDK 17 or later.

From the repository root, activate the tracked hooks once per clone:

```sh
git config core.hooksPath Scripts/githooks
```

Package tests can run independently:

```sh
swift test --package-path CardCore
swift test --package-path PKCS11Bridge
```

[Testing strategy](Documentation/testing-strategy.md) describes the
scope-selected commit and push gates, `Scripts/test.py pr`, simulator
requirements, and separate UI-test workflow. UI tests run off the
workstation's screen.

Signed builds and development installs go through the
[release manager](Scripts/apple-app-store-connect-release-manager.swift),
which owns signing, provisioning, version stamps, and installation:

```sh
Scripts/apple-app-store-connect-release-manager.swift install-macos
Scripts/apple-app-store-connect-release-manager.swift install-ios
```

The [release runbook](Documentation/release-runbook.md) covers credentials,
candidate inspection, and distribution. For the optimized iPhone NFC
timing sample, the release manager provides `install-nfc-timing`.

### Optional Rust tools for shared protocol work

Building the Swift app does not require Rust. Cross-repository work such
as regenerating refineid-core's RAPP conformance vectors uses the Rust
toolchain required by that repository. One setup on a Mac with Homebrew is:

```sh
brew install rustup
"$(brew --prefix rustup)/bin/rustup-init" -y --default-toolchain stable
. "$HOME/.cargo/env"
rustup component add clippy rustfmt
```

Install additional audit tools only as needed by the owning repository's
checks; they are not prerequisites for the Swift app.
