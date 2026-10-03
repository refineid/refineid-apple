# RAPP Transport & Discovery Hierarchy (Apple Ecosystem)

- **Document Version**: `26.10.3`
- **Normative Status**: Active Project Standard
- **Applies To**: `RefineID-Apple` (iOS, iPadOS, macOS)
- **Supersedes**: Prior architecture drafts assuming desktop listeners or static port advertising

---

## 1. Executive Summary & Security Model

The RefineID Remote Card Proxy protocol (RAPP) bridges physical identity cards (e.g. Finnish Citizen Certificate on FINEID cards) held at a mobile phone's NFC radio to requester workstations (macOS, Windows, Linux/BSD).

### 1.1 Sovereign Phone Custodian vs. Requester Workstation

1. **Phone is the Sovereign Custodian**:
   - The smartphone (iPhone) possesses the physical NFC antenna, reads contactless PACE/CAN tokens, prompts user PINs on its secure touch display, and controls card custody.
   - Operating systems hierarchy of attack surface: iOS is the most hardened consumer platform. Laptops (macOS, Linux, Windows) have expansive attack surfaces, peripheral buses, background daemons, and potential local privilege vectors.
   - **Zero Unprompted Exposure**: The iPhone **never** announces itself or opens any network listener by default. It activates its listener and discovery announcements **if and only if** the user explicitly toggles `[x] Allow Remote Reader` in the RefineID mobile UI.
   - When "Allow Remote Reader" is disabled, all radio advertising (BLE, AWDL) and network listeners (mDNS/DNS-SD, TCP) are completely quiescent, conserving battery and strictly complying with RFC 8882 (zero persistent trackable identifiers).

2. **Workstation is Strictly an Outbound Client (Requester)**:
   - macOS workstations (whether running the RefineID App, CLI, or CryptoTokenKit extension) **never** bind listening ports (no port 47110, no open TCP sockets) and never require inbound firewall configuration.
   - All desktop connections are strictly **outbound client connections** dialed toward the announced phone custodian.

3. **Workstation UX Hygiene**:
   - On macOS desktops, RefineID is a **pure local card reader** by default (PC/SC contact smartcard readers via `TKSmartCardSlotManager`).
   - The desktop initiates remote discovery/browsing if and only if the user explicitly turns on `[x] Enable Remote Phone Reader` in the macOS preferences.

---

## 2. Normative 3-Tier Discovery & Transport Hierarchy

When remote proxy operation is enabled, RefineID implements a strict fallback hierarchy:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Tier 1: Apple Direct P2P (AWDL / MultipeerConnectivity)                 │
│         - Native Apple-to-Apple high-speed ad-hoc channel               │
│         - Zero configuration, Wi-Fi infrastructure independent          │
│         - Profile: fi.refineid.apple-p2p.v1                             │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ fallback (non-Apple or P2P unavailable)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Tier 2: Bluetooth Low Energy Proximity (BLE GATT)                       │
│         - Cross-platform proximity-gated link (iOS, macOS, Linux, Win)  │
│         - CoreBluetooth CBPeripheralManager / CBCentralManager (GATT)   │
│         - Advisory RSSI discovery gate (>= -55 dBm)                     │
│         - Profile: fi.refineid.rapp.ble.v1                              │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ fallback (BLE disabled or out-of-range)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Tier 3: Local IP Stream Discovery (mDNS / DNS-SD + Outbound TCP)        │
│         - IETF RFC 6762 (mDNS) & RFC 6763 (DNS-SD)                      │
│         - Service type: _refineid-stream._tcp.local.                     │
│         - Phone acts as mDNS responder & TCP listener (ephemeral port)  │
│         - Workstation acts strictly as mDNS browser & outbound client   │
│         - Profile: fi.refineid.stream.v1                                │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Tier 1: Apple Direct P2P (`fi.refineid.apple-p2p.v1`)
- **Protocol**: Apple Wireless Direct Link (AWDL) orchestrated via `MultipeerConnectivity` or Network.framework `NWListener` with `includePeerToPeer = true`.
- **Applicability**: Between iOS phone custodian and macOS requester.
- **Advantages**: Completely independent of local Wi-Fi router isolation, public hotspot filtering, or corporate subnet partitioning.
- **Cryptographic Security**: Channel payload is still end-to-end encrypted with RAPP Noise protocol (`Noise_XXpsk3` for pairing, `Noise_KK` for sessions). The Apple transport is treated as an untrusted link.

### 2.2 Tier 2: Bluetooth Low Energy Proximity (`fi.refineid.rapp.ble.v1`)
- **Wire Profile**: Canonical GATT-based `fi.refineid.rapp.ble.v1` (RAPP v26.10.1 §2–§5).
  - Primary Service UUID: `7E39FD01-A6B5-4D78-9E11-37E28E9545F1`
  - Channel Characteristic: `7E39FD02-A6B5-4D78-9E11-37E28E9545F1` (Client write, Server indicate)
  - Bootstrap Characteristic: `7E39FD03-A6B5-4D78-9E11-37E28E9545F1` (Client read)
  - Framing: Mandates ATT MTU Exchange ($\ge 512$ bytes) and RAPP BLE SAR framing (6-byte header: Total Frame Length, Chunk Sequence, Flags, Reserved).
- **Advisory Proximity Gating**: Requester monitors RSSI and enforces an advisory discovery gate ($\ge -55\text{ dBm}$ filtered median over at least 3 packets, configurable to $-85\text{ dBm}$ in isolated developer testing).
  - *Threat Model Note*: Per RAPP v26.10.1 §4.4, RSSI is strictly an advisory filter and defense-in-depth heuristic; it does NOT prove physical proximity or defeat transparent RF relays or wormholes. Protection against unauthorized execution is provided at Layer 7 by explicit per-operation user consent on the phone display and PIN verification.
- **L2CAP CoC Clarification**: Apple platforms support `CBL2CAPChannel`, but client platforms such as Windows user-space do not expose public BLE L2CAP CoC APIs. Therefore, GATT-based `fi.refineid.rapp.ble.v1` is the canonical cross-platform Tier 2 profile. Any future credit-based CoC profile would be a separate, distinct adaptation (`fi.refineid.rapp.ble-coc.v1`).
- **No OS Pairing/Bonding**: Relies entirely on RAPP application-layer Noise cryptography without OS pairing popups or Bluetooth accessory dialogs.

### 2.3 Tier 3: Local IP Stream Discovery (`fi.refineid.stream.v1`)
- **Discovery**: Standard IETF mDNS (RFC 6762) / DNS-SD (RFC 6763).
- **Service Name**: `_refineid-stream._tcp.local.`
- **Privacy (RFC 8882)**:
  - The service instance name MUST be a fresh, ephemeral random string generated on each registration: `refineid-[random_8_hex]._refineid-stream._tcp.local.`, preventing long-term device tracking across networks.
  - The SRV record target MUST use an anonymized, ephemeral host label: `refineid-[random_8_hex].local.`, avoiding leakage of iOS device or user names.
  - The persistent 16-byte `rendezvous_token` (RAPP v26.10.1 §4.3) is **NEVER** published in mDNS records or instance names; it is transmitted strictly over the established point-to-point TCP stream during `Phase::Routing`.
  - TXT records publish `mode=pairing` (with the 16-byte ephemeral `offer_id`) during pairing, and `mode=session` (with optional 15-minute rotating HMAC discovery hints) during operational reconnection.
- **Connection**:
  1. Phone starts ephemeral TCP server on local IP.
  2. Phone advertises service record via `NWListener` / Bonjour.
  3. Workstation browsing via `NWBrowser` / Bonjour resolves phone IP:port.
  4. Workstation establishes outbound TCP connection to phone.

---

## 3. Privacy, Battery & Lifecycle Discipline

1. **On-Demand Activation**:
   - The phone does not broadcast BLE beacons or advertise mDNS services continuously.
   - Broadcasts occur only when:
     - The user is in an active pairing flow ("Pair New Computer" screen open).
     - "Allow Remote Reader" is enabled and the phone is unlocked/active.
2. **Background Handling**:
   - iOS suspends listening sockets when backgrounded unless an active session is in flight. The workstation will surface an explicit prompt ("Unlock your phone and tap RefineID") if a session dial times out.
3. **Auditability**:
   - Zero PIN data, candidate lengths, or raw key material are ever logged across any transport or discovery frame.
