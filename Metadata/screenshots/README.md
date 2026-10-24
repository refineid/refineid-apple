# App Store Marketing Screenshots

## The command

```sh
Scripts/apple-app-store-connect-release-manager.swift capture-screenshots
```

It refreshes every App Store screenshot: **macOS (`APP_DESKTOP`)**, **iPhone
(`APP_IPHONE_67`)** and **iPad (`APP_IPAD_PRO_3GEN_129`)**, in **Finnish
`fi`**, **English `en-US`** and **Swedish `sv`**. Narrow a run with
`--platform macos|ios|ipad|all` and `--locale fi|en-US|sv|all` (both default
to `all`):

```sh
Scripts/apple-app-store-connect-release-manager.swift capture-screenshots --platform macos --locale fi
```

For each chosen platform, locale and screen it:

1. Builds the Debug app into `build/store-screenshots/`.
2. Launches it in the screen's demonstration state: a virtual card with the
   synthetic identity, the locale forced with `-AppleLanguages` and
   `-AppleLocale`, and `--hide-diagnostics`.
3. Captures the screen into `assets/` once it shows content and three
   captures a second apart are identical, so no launch screen or animation
   frame is kept.
4. Composes the store images into `<locale>/<DISPLAY_TYPE>/` with
   `Scripts/generate-store-screenshots.swift`, and checks each one's size, that
   it has no alpha channel, and that there is one image per screen.

No step is manual.

- **Mac.** The Mac window is captured from a second copy of the app, built
  from this checkout and launched beside any installed copy, which keeps
  running: a virtual-card launch holds no card session, uses in-memory stores,
  and restores no saved window state. Its token extensions are
  unregistered when the captures are done. The launch pins dark appearance and
  standard contrast and transparency, whatever this Mac's accessibility
  settings are. The terminal needs Screen Recording permission, and the window
  must be on a Retina display.
- **iPhone and iPad.** The captures run on two simulators of their own,
  `RefineID Store iPhone` (iPhone 16 Plus) and `RefineID Store iPad` (iPad Pro
  12.9-inch, 6th generation), created on first use. Each starts from a fresh
  install, in dark appearance with standard contrast and text size, with the
  status bar at `9:41` in the locale's format, full Wi-Fi and cellular signal
  and a charged battery. The simulator restarts for each locale, since its
  status bar reads the region once per boot. The iPad status bar's date and app name
  are painted over, keeping the time.

## Screens

| Platform | Store image | Raw capture | Demonstration state |
| :--- | :--- | :--- | :--- |
| macOS | `01-authentication.png` | `window-card-<lang>.png` | Card in this Mac's reader: the holder's name, PIN Codes in the toolbar (`--virtual-card activated-reader`) |
| macOS | `02-phone.png` | `window-phone-<lang>.png` | Paired phone serving the card, remote use on and connected (`--virtual-card activated-reader --mock-remote-connected`) |
| iPhone | `01-app-main.png` | `iphone-main-<lang>.png` | Main screen, remote access connected (`--virtual-card registered-nfc --mock-remote-connected`) |
| iPhone | `02-documents.png` | `iphone-documents-<lang>.png` | Signing a document (`--virtual-card registered-nfc --open-document-signing`) |
| iPad | `01-main.png` | `ipad-main-<lang>.png` | Main screen, remote access connected (`--virtual-card activated-reader --mock-remote-connected`) |
| iPad | `02-documents.png` | `ipad-documents-<lang>.png` | Signing a document (`--virtual-card activated-reader --open-document-signing`) |

`<lang>` is `fi`, `en` or `sv`. The holder is the virtual card's synthetic
identity: `ESIMERKKI ERJA` in Finnish, `EXEMPEL EVA` in Swedish and `DOE JANE`
in English. The demonstration flags exist in Debug builds only.

## Specifications and Display Types

| Platform | App Store `DISPLAY_TYPE` | Target Device | Canvas Resolution | Aspect Ratio | Color Space & Alpha |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **macOS** | `APP_DESKTOP` | Mac Desktop / Laptop | **2880 × 1800 px** | 16:10 | sRGB, 0% alpha (`noneSkipLast`) |
| **iOS** | `APP_IPHONE_67` | iPhone 6.7″ / 6.9″ Pro Max & Plus | **1290 × 2796 px** | 19.5:9 | sRGB, 0% alpha (`noneSkipLast`) |
| **iPadOS** | `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9″ / 13″ (6th gen) | **2048 × 2732 px** | 4:3 | sRGB, 0% alpha (`noneSkipLast`) |

App Store Connect rejects screenshots with an alpha channel. The generator
allocates 32-bit bitmaps with `CGImageAlphaInfo.noneSkipLast.rawValue` to
guarantee `hasAlpha: no`.

---

## Visual Architecture & Design System

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

## Directory Layout

```
Metadata/screenshots/
├── README.md                                    # This documentation
├── assets/                                      # Raw captures and the wallpaper the composer reads
│   ├── golden-gate-dark.png                     # Dark Golden Gate wallpaper canvas
│   ├── window-card-{fi,en,sv}.png               # macOS 01 (card in this Mac's reader)
│   ├── window-phone-{fi,en,sv}.png              # macOS 02 (paired phone)
│   ├── iphone-main-{fi,en,sv}.png               # iPhone 01 (main screen)
│   ├── iphone-documents-{fi,en,sv}.png          # iPhone 02 (document signing)
│   ├── ipad-main-{fi,en,sv}.png                 # iPad 01 (main screen)
│   └── ipad-documents-{fi,en,sv}.png            # iPad 02 (document signing)
├── fi/                                          # Finnish App Store screenshots
│   ├── APP_DESKTOP/                             # 2880x1800 macOS (01-authentication, 02-phone)
│   ├── APP_IPHONE_67/                           # 1290x2796 iPhone (01-app-main, 02-documents)
│   └── APP_IPAD_PRO_3GEN_129/                   # 2048x2732 iPad (01-main, 02-documents)
├── en-US/                                       # English App Store screenshots (same hierarchy)
└── sv/                                          # Swedish App Store screenshots (same hierarchy)
```

---

## Localized Slides Content Catalog

The captions live in `Scripts/generate-store-screenshots.swift`.

| Platform | Locale | Slide | Title | Subtitle |
| :--- | :--- | :--- | :--- | :--- |
| macOS | **fi** | 01 | **Tunnistaudu henkilökortilla verkkopalveluihin** | Liitä kortinlukija Maciin. |
| macOS | **fi** | 02 | **Käytä puhelinta kortinlukijana** | (none) |
| macOS | **en-US** | 01 | **Log in to web services with your identity card** | Connect a card reader to your Mac. |
| macOS | **en-US** | 02 | **Use your phone as a card reader** | (none) |
| macOS | **sv** | 01 | **Identifiera dig till e-tjänster med identitetskort** | Anslut en kortläsare till din Mac. |
| macOS | **sv** | 02 | **Använd telefonen som kortläsare** | (none) |
| iPhone, iPad | **fi** | 01 | **Tunnistaudu henkilökortilla verkkopalveluihin** | Voit käyttää myös puhelinta langattomana kortinlukijana. |
| iPhone, iPad | **fi** | 02 | **Allekirjoita asiakirjoja** | Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia. |
| iPhone, iPad | **en-US** | 01 | **Log in to web services with your identity card** | You can also use your phone as a wireless card reader. |
| iPhone, iPad | **en-US** | 02 | **Sign documents** | Create and verify qualified electronic signatures. |
| iPhone, iPad | **sv** | 01 | **Identifiera dig till e-tjänster med identitetskort** | Du kan även använda telefonen som trådlös kortläsare. |
| iPhone, iPad | **sv** | 02 | **Underteckna dokument** | Skapa och granska kvalificerade elektroniska underskrifter. |

---

## Composing Only

After changing a caption or the layout, compose from the raw captures
already in `assets/` without capturing again:

```sh
swift Scripts/generate-store-screenshots.swift --platform all --locale all
swift Scripts/generate-store-screenshots.swift --platform macos --locale sv
```

The composer refuses to write a slide whose raw capture is missing.

---

## Verifying Compliance Before Submission

`capture-screenshots` checks every composed image. To check by hand:

```sh
find Metadata/screenshots -name "*.png" ! -path "*/assets/*" | xargs sips -g pixelWidth -g pixelHeight -g hasAlpha
```

Every screenshot must return `hasAlpha: no` and match the standard resolution for its display type folder.

---

## Uploading to App Store Connect

Upload screenshots through the automated release manager:

```sh
# Upload iOS & iPadOS screenshots:
Scripts/apple-app-store-connect-release-manager.swift screenshots ios <version>

# Upload macOS screenshots:
Scripts/apple-app-store-connect-release-manager.swift screenshots macos <version>
```
