# App Store Marketing Screenshots

RefineID uses automated, high-fidelity marketing screenshots for **macOS (`APP_DESKTOP`)**, **iOS (`APP_IPHONE_67`)**, and **iPadOS (`APP_IPAD_PRO_3GEN_129`)** across all supported store locales (**Finnish `fi`**, **English `en-US`**, and **Swedish `sv`**).

All marketing screenshots are generated with zero alpha channel, top-anchored typographical rhythm, realistic device frames, ambient shadows, and an official dark Golden Gate wallpaper matching Apple Human Interface Guidelines and App Store Review Guidelines.

---

## macOS MVP

The macOS catalog contains one screenshot per locale: `01-authentication.png`.
It shows a local card and reader. SCS, phone pairing, and wireless-reader claims
must not appear. iOS and iPadOS retain their two-image catalogs.
Recapture the macOS window from this build before composing the final assets;
older `window-card-*` inputs can contain remote connection indicators.

## 1. Specifications and Display Types

| Platform | App Store `DISPLAY_TYPE` | Target Device | Canvas Resolution | Aspect Ratio | Color Space & Alpha |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **macOS** | `APP_DESKTOP` | Mac Desktop / Laptop | **2880 × 1800 px** | 16:10 | sRGB, 0% alpha (`noneSkipLast`) |
| **iOS** | `APP_IPHONE_67` | iPhone 6.7″ / 6.9″ Pro Max & Plus | **1290 × 2796 px** | 19.5:9 | sRGB, 0% alpha (`noneSkipLast`) |
| **iPadOS** | `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9″ / 13″ (6th gen) | **2048 × 2732 px** | 4:3 | sRGB, 0% alpha (`noneSkipLast`) |

### Strict Apple Store Standards Enforced:
1. **0% Alpha Channel**: Apple Store Connect rejects screenshots with an alpha channel. The generator allocates 32-bit bitmaps with `CGImageAlphaInfo.noneSkipLast.rawValue` to guarantee `hasAlpha: no`.
2. **Pristine Status Bar**: 
   - Status bar time is frozen at `9:41`.
   - Full Wi-Fi (3 bars) and Cellular (4 bars) signal.
   - Battery state: `100% charged`.
3. **Timeless iPad Status Bar**:
   - Standard iPad simulator captures display a localized calendar date (e.g. `Sat 26. Sep`), causing screenshots to visually date quickly.
   - The capture tooling programmatically patches out the calendar date with an exact dark background fill while keeping the `9:41` clock and system indicators intact.
4. **Clean Production State**:
   - Apps launch with `--hide-diagnostics` to suppress debug overlays, telemetry footers, and diagnostic buttons.
5. **Data Privacy**:
   - Synthetic citizen identities only (`ESIMERKKI ERJA 12345678N` / `DOE JANE 12345678N`). Never capture or display real credentials or real personal data.

---

## 2. Visual Architecture & Design System

The screenshot design system provides visual consistency when users swipe through the App Store carousel:

```
+-------------------------------------------------------+
|  Golden Gate Dark Wallpaper + Gradient Top Veil       |
|                                                       |
|  [TOP MARGIN: 236px iPhone / 280px iPad]              |
|  TITLE: Top-Anchored Headline (Bold SF Pro)           |
|                                                       |
|  [GAP: 56-64px iPhone / 64-72px iPad]                 |
|  SUBTITLE: Value Proposition (Medium SF Pro)          |
|                                                       |
|  [GAP: 170-176px iPhone / 265-280px iPad]             |
|  +-------------------------------------------------+  |
|  | Device Bezel & Ambient Drop Shadow (50pt blur)  |  |
|  | +---------------------------------------------+ |  |
|  | |                                             | |  |
|  | | App Screen Capture (Clipped Corner Radius)   | |  |
|  | | - Pristine 9:41 Dark Mode Status Bar        | |  |
|  | | - Real Application UI Content               | |  |
|  | |                                             | |  |
|  | +---------------------------------------------+ |  |
|  +-------------------------------------------------+  |
|  [BOTTOM MARGIN: Balanced Breathing Room ~250px]      |
+-------------------------------------------------------+
```

### Top-Anchored Typography Alignment
- **Problem**: When slide 01 has a 2-line title and slide 02 has a 1-line title, bottom-up anchoring causes the 2-line title to jump upwards into the canvas top edge, breaking visual continuity.
- **Solution**: The Swift renderer anchors the **top baseline of the headline** at a fixed distance from the canvas top (`titleTopMargin = 236 px` on iPhone, `280 px` on iPad).
- **Harmonized Rhythm**:
  - `titleToSubGap`: 56 px (for 2-line titles) or 64 px (for 1-line titles).
  - `subToCardGap`: Balanced at ~170 px (for 2-line titles) and ~176 px (for 1-line titles).
  - `phoneY`: 250 px (for 2-line titles) and 330 px (for 1-line titles), creating balanced top and bottom breathing room.

### Hardware Framing Aesthetics
- **Bezel**: Dark metallic border (`#1F1F24`) with an outer subtle highlight stroke (`#52545C`, 1.5 pt).
- **Corner Radii**: `56.0 pt` on iPhone, `44.0 pt` on iPad, perfectly matching device physical aesthetics.
- **Shadow**: Deep ambient drop shadow (`NSShadow`, blur radius 50–55 pt, Y offset -22 to -24 pt, opacity 0.65).
- **Cropping & Bleed**: Bottom non-interactive empty space is trimmed (`1920 px` out of 2796 on iPhone, `1340 px` out of 2048 on iPad) to focus on the key UI features and give headroom to the typography.

---

## 3. Directory Layout

```
Metadata/screenshots/
├── README.md                                    # This documentation
├── assets/                                      # Source assets used by the Swift generator
│   ├── golden-gate-dark.png                     # Dark Golden Gate wallpaper canvas
│   ├── iphone-main-{fi,en,sv}.png               # iPhone Screen 01 (Authentication & card)
│   ├── iphone-documents-{fi,en,sv}.png          # iPhone Screen 02 (Document signing)
│   ├── ipad-main-{fi,en,sv}.png                 # iPad Screen 01 (Authentication & card)
│   ├── ipad-documents-{fi,en,sv}.png            # iPad Screen 02 (Document signing)
│   ├── window-card-{fi,en,sv}.png               # macOS Screen 01 (Authentication window)
│   └── window-documents-{fi,en,sv}.png          # macOS Screen 02 (Document signing window)
├── fi/                                          # Finnish App Store Screenshots
│   ├── APP_DESKTOP/                             # 2880x1800 macOS (01-authentication)
│   ├── APP_IPHONE_67/                           # 1290x2796 iPhone (01-app-main, 02-documents)
│   └── APP_IPAD_PRO_3GEN_129/                   # 2048x2732 iPad (01-main, 02-documents)
├── en-US/                                       # English App Store Screenshots (same hierarchy)
└── sv/                                          # Swedish App Store Screenshots (same hierarchy)
```

---

## 4. Localized Slides Content Catalog

| Locale | Slide | Title | Subtitle |
| :--- | :--- | :--- | :--- |
| **fi** | 01 | **Tunnistaudu henkilökortilla verkkopalveluihin** | Voit käyttää myös puhelinta langattomana kortinlukijana. |
| **fi** | 02 | **Allekirjoita asiakirjoja** | Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia. |
| **en-US**| 01 | **Log in to web services with your identity card** | You can also use your phone as a wireless card reader. |
| **en-US**| 02 | **Sign documents** | Create and verify qualified electronic signatures. |
| **sv** | 01 | **Identifiera dig till e-tjänster med identitetskort** | Du kan även använda telefonen som trådlös kortläsare. |
| **sv** | 02 | **Underteckna dokument** | Skapa och granska kvalificerade elektroniska underskrifter. |

---

## 5. Tooling & Execution

### Composing Marketing Screenshots (`generate-store-screenshots.swift`)

The Swift generator is the primary tool that renders marketing screenshots from the raw assets:

```sh
# Generate all platforms and all locales (macOS, iOS, iPadOS for fi, en-US, sv):
swift Scripts/generate-store-screenshots.swift --platform all --locale all

# Or target a specific platform and locale:
swift Scripts/generate-store-screenshots.swift --platform ios --locale fi
swift Scripts/generate-store-screenshots.swift --platform ipad --locale en-US
swift Scripts/generate-store-screenshots.swift --platform macos --locale sv
```

### Capturing Simulator UI Assets (`store-screenshot-ios.sh`)

When the application's visual interface changes, use `store-screenshot-ios.sh` to update simulator assets and immediately regenerate store screenshots:

```sh
# Capture all iPhone and iPad simulator screens and rebuild marketing screenshots:
Scripts/store-screenshot-ios.sh --capture-assets --all

# Or capture for a specific locale:
Scripts/store-screenshot-ios.sh --capture-assets --locale fi

# Or capture raw simulator screenshots into a custom directory without marketing framing:
Scripts/store-screenshot-ios.sh --all --output-dir /tmp/raw-screenshots
```

**Simulator Launch Arguments automated by the script:**
- **Main Screen (01)**:
  `-AppleLanguages "($LANG)" -AppleLocale "$LOCALE" --hide-diagnostics --mock-remote-connected --virtual-card registered-nfc`
- **Document Signing (02)**:
  `-AppleLanguages "($LANG)" -AppleLocale "$LOCALE" --hide-diagnostics --open-document-signing --virtual-card registered-nfc`

### Capturing macOS Window Assets (`store-screenshot.sh`)

To update macOS window assets when the Mac UI changes:
1. Launch RefineID in Debug mode with synthetic demo state:
   ```sh
   # Main card window:
   build/Build/Products/Debug/RefineID.app/Contents/MacOS/RefineID --hide-diagnostics --mock-remote-connected --virtual-card registered-nfc -AppleLanguages '(fi)' -AppleLocale fi
   ```
2. Capture the window:
   ```sh
   Scripts/store-screenshot.sh window-card-fi
   mv ~/Desktop/refineid-store-screenshots/window-card-fi.png Metadata/screenshots/assets/window-card-fi.png
   ```
3. Re-run `swift Scripts/generate-store-screenshots.swift --platform macos --locale fi`.

---

## 6. Verifying Compliance Before Submission

To verify all output files comply with Apple requirements, run:

```sh
# Verify resolutions and confirm hasAlpha: no across all files:
find Metadata/screenshots -name "*.png" ! -path "*/assets/*" | xargs sips -g pixelWidth -g pixelHeight -g hasAlpha
```

Every screenshot must return `hasAlpha: no` and match the standard resolution for its display type folder.

---

## 7. Uploading to App Store Connect

Upload screenshots through the automated release manager:

```sh
# Upload iOS & iPadOS screenshots:
Scripts/apple-app-store-connect-release-manager.swift screenshots ios <version>

# Upload macOS screenshots:
Scripts/apple-app-store-connect-release-manager.swift screenshots macos <version>
```
