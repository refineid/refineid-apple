# App Store screenshots

Screenshots are the one part of a submission that cannot live in
`appstore.json`: they are captures of the running app, so they are PNG
files on disk. `apple-app-store-connect-release-manager.swift screenshots <ios|macos> <version>`
uploads everything under here.

## Layout

```
Metadata/screenshots/<locale>/<DISPLAY_TYPE>/<name>.png
```

Files upload in filename order, so name them `01.png`, `02.png`, ….
The folder name is the App Store display type, verbatim. A locale with
no folder is skipped; a display type with no PNGs is skipped.

## Display types and pixel sizes

| Platform | `DISPLAY_TYPE`          | Device            | Portrait px |
|----------|-------------------------|-------------------|-------------|
| macOS    | `APP_DESKTOP`           | Mac               | 2880×1800   |
| iOS      | `APP_IPHONE_67`         | iPhone 6.9″/6.7″  | 1290×2796   |
| iPadOS   | `APP_IPAD_PRO_3GEN_129` | iPad Pro 13″/12.9″| 2048×2732   |

macOS accepts 1280×800, 1440×900, 2560×1600 or 2880×1800. iPhone and
iPad want the sizes above (landscape captures use the transposed size).

## Locales

`en-US` is the primary and is required. `fi` and `sv` may reuse the same
PNGs — copy the folders, or leave them out and the store shows the
primary locale's screenshots.

## Standards

- **Pristine Status Bar**: Time must be `9:41`, battery state `100% charged`, with full Wi-Fi and cellular signal bars.
- **Production Appearance**: No debug diagnostics UI or development footer buttons (launch with `--hide-diagnostics`).
- **Privacy and Data Integrity**: Screenshots carry synthetic or redacted data only; never capture real citizen identities or personal credentials.
- **Correct Aspect and Resolutions**: Match App Store specifications exactly (e.g. `1290×2796` for `APP_IPHONE_67`, `2880×1800` for `APP_DESKTOP`).

## Capturing and Tooling

### iOS (Automated via Simulator)

Automate capture using either the release manager Swift tool or the underlying script:

```sh
# Via the release manager:
Scripts/apple-app-store-connect-release-manager.swift capture-screenshots --all

# Or directly via the iOS capture script:
Scripts/store-screenshot-ios.sh --all
```

Options:
- `--all`: Captures and updates screenshots for all supported locales (`en-US`, `fi`, `sv`).
- `--locale <loc>`: Captures for a specific locale (`en-US`, `fi`, or `sv`).
- `--scenario <name>`: Drives a specific Virtual ID Card scenario (e.g., `registered-nfc`, `factory-fresh-nfc`).
- `--output-dir <path>`: Directs outputs to a custom directory instead of `Metadata/screenshots/`.

### Marketing Screenshots Generation (macOS, iOS & iPadOS)

```sh
# Generate marketing screenshots for all supported platforms and locales:
swift Scripts/generate-store-screenshots.swift --locale all

# Or for a specific platform and locale:
swift Scripts/generate-store-screenshots.swift --platform ios --locale fi
swift Scripts/generate-store-screenshots.swift --platform ipad --locale fi
swift Scripts/generate-store-screenshots.swift --platform macos --locale fi
```

Produces:
- macOS (`APP_DESKTOP`): 2880×1800 (16:10)
- iOS (`APP_IPHONE_67`): 1290×2796 (iPhone 6.7"/6.9")
- iPadOS (`APP_IPAD_PRO_3GEN_129`): 2048×2732 (iPad Pro 12.9"/13")
with strict 0% alpha channel matching App Store Connect specifications.

```sh
# Or raw single window capture onto canvas:
Scripts/store-screenshot.sh NAME
```

## Uploading to App Store Connect

```sh
Scripts/apple-app-store-connect-release-manager.swift screenshots <ios|macos> <version>
```

