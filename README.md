# RefineID for Apple platforms

RefineID makes Finnish identity cards usable through Apple platform security frameworks. 

## Apple App Store Version

Available at https://apps.apple.com/fi/app/refineid/id6796444289

## PIN codes

RefineID remembers PIN 1 in memory while the identity card stays in the
reader or on the phone, so a login that signs several times asks for it
once. It keeps PIN 1 only while the card reports all of its PIN 1 tries
left, and forgets it when the card leaves, when the card refuses it, and
when the app quits. PIN 2 is asked for every signature, or once for a
batch of documents signed together, and is never kept. Neither PIN is
written to storage, and neither leaves the device that holds the card.

Remembering PIN 1 is a deliberate deviation from the FINEID profile
(FINEID S4-1 v4.2, sections 4.1 and 8.1.7), which asks for PIN 1 to be
entered for every authentication. It never applies to PIN 2 or to
qualified signatures.

## Building

Requires Xcode 26 on macOS 26. From a fresh clone, no other setup:

```sh
xcodebuild -project RefineID.xcodeproj -scheme RefineID build
xcodebuild -project RefineID.xcodeproj -scheme RefineID test
```

For an iPhone timing build, use the optimized `Profile` configuration and
override Xcode's Swift-package coverage injection:

```sh
xcodebuild build \
  -project RefineID.xcodeproj \
  -scheme RefineID \
  -configuration Profile \
  -destination 'generic/platform=iOS' \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO
```

The override matters even though the project configuration disables coverage:
Xcode 26 otherwise adds `-profile-generate -profile-coverage-mapping` while
building the local `CardCore` package.
