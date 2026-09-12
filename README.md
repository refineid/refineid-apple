# RefineID for Apple platforms

RefineID makes Finnish identity cards usable through Apple platform security frameworks. 

## Apple App Store Version

Available at https://apps.apple.com/fi/app/refineid/id6796444289

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
