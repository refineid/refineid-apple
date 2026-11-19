# Network Contract and Transport Security

Outbound network requirements, App Transport Security (ATS) rules, and
connection surface across macOS and iOS.

## Zero cloud backend

RefineID connects directly to smart cards and public signing infrastructure.
There is no RefineID server, no telemetry endpoint, no analytics collection,
and no proprietary cloud backend.

## Outbound traffic

The application initiates outbound connections for three purposes only:

1. **Qualified Time-Stamp Authorities (RFC 3161)**
   - Used to acquire time-stamp tokens from qualified trust service providers for
     archival signatures (PAdES-B-LTA and XAdES-B-LTA).
   - Default authority: `http://timestamp.sectigo.com/qualified`.
   - The timestamp authority URL is configurable in Settings when
     `FEATURE_TIMESTAMP_CONFIG` is enabled; the macOS MVP compiles that
     pane out and always asks the shipped qualified service.
   - Per-document spacing: `TimestampClient` spaces initial (and retried)
     timestamp requests for separate documents and containers by at least 15
     monotonic seconds (`TimestampThrottle.minimumDocumentSpacing`) to honor
     the authority's fair-use policy, while allowing follow-up timestamps on
     the same document (such as an archive timestamp after a signature
     timestamp) without intra-document delay. Single user-initiated Settings
     probes are unthrottled.
2. **Revocation and certificate chain checking (OCSP, CRL, caIssuers)**
   - RFC 6960 Online Certificate Status Protocol (OCSP), RFC 5280
     Certificate Revocation List (CRL) checks, and Authority Information
     Access (AIA) `caIssuers` certificate fetches.
   - Endpoints are extracted dynamically from the Authority Information Access
     and CRL Distribution Points extensions within the certificates being
     validated — both when embedding long-term validation material (`DSS` /
     `RevocationValues`) into a new `B-LTA` signature and when verifying a
     document on platforms with `FEATURE_DOCUMENT_VERIFICATION` enabled.
3. **EU Trusted Lists (ETSI TS 119 612)**
   - Periodic retrieval of the European Commission List of the Lists (LOTL)
     and National Trusted Lists by `TrustedLists` / `TrustedListStore`.
   - Required by archival document signing as well as document verification:
     no CA root is shipped, so every RFC 3161 timestamp token `TimestampClient`
     receives during signing is verified against the `TSA/QTST` anchors from
     the cached or freshly fetched EU trusted lists.

### Transport constraints: SigningNetwork

Every outbound Internet request for document signing, verification,
timestamping, revocation, and trust lists routes through `SigningNetwork`.

- **Supported schemes only.** Only `http` and `https` schemes are accepted.
  Other schemes (such as `ldap://` or `ftp://` found in legacy CRLDP or AIA
  extensions) are refused (`Failure.unsafeAddress`).
- **Public IP addresses only.** `SigningNetwork` resolves destination
  addresses and verifies that connections reach publicly routable unicast IP
  addresses only.
- **SSRF prevention and address handling.** Connections to private, loopback,
  link-local, carrier-grade NAT, or multicast/reserved address spaces are
  rejected. For HTTP certificate material requests, hostnames are resolved and
  rewritten directly to the vetted public numeric IP address before URLSession
  sees them, pinning the dispatch to the validated IP to prevent DNS rebinding
  (TOCTOU) while preserving the original HTTP `Host` header. HTTPS requests
  retain their hostname for SNI and TLS certificate validation after preflight
  verification confirms all resolved addresses are public.
- **Redirect validation.** At most two public redirects are followed (e.g. for
  canonical host hops in national trusted lists). Redirects are intercepted and
  re-vetted before following; any redirect changing to a non-public IP or
  leaving HTTP(S) fails with `Failure.unsafeRedirect`.
- **Response size limits.** Responses are strictly capped: 64 KB for timestamp
  tokens, OCSP responses, and AIA `caIssuers` certificate fetches, and 1 MB
  for certificate revocation lists (CRLs) and EU trust lists.

### App Transport Security (ATS)

Both `Config/RefineID-Store-Info.plist` (macOS) and
`Config/RefineID-iOS-Info.plist` (iOS) carry the following ATS configuration:

```xml
<key>NSAppTransportSecurity</key>
<dict>
	<key>NSAllowsArbitraryLoads</key>
	<true/>
	<key>NSExceptionDomains</key>
	<dict>
		<key>timestamp.sectigo.com</key>
		<dict>
			<key>NSExceptionAllowsInsecureHTTPLoads</key>
			<true/>
		</dict>
	</dict>
</dict>
```

- `NSAllowsArbitraryLoads = true` is required because archival signatures
  require fetching revocation endpoints (OCSP and CRL) published inside
  validated certificates across EU member states. Standards and national trust
  service providers frequently use unadorned HTTP endpoints, making static
  domain allowlists impossible.
- Because `NSAllowsArbitraryLoads = true` permits arbitrary loads at runtime,
  the explicit `NSExceptionDomains` entry for `timestamp.sectigo.com` has no
  additional runtime effect. It names the one fixed cleartext dependency for
  static analysis audits and is verified by
  `NetworkContractTests.applicationPlistsMatchTheContract`.
- Apple requires a justification for `NSAllowsArbitraryLoads` during App
  Review, and App Review reads the version's notes, not the property list:
  comments do not survive plist compilation. The justification is therefore
  the platform's `review.notes` in `Metadata/appstore.json`, which the
  release manager's `review-contact` pushes; the macOS notes carry it. The
  plist comments are the in-repository copy of the same rationale. The
  notes stay within App Store Connect's 4000-character field and
  `AppStoreReviewNotesTests` pins the text.
- Outbound transport security is actively enforced at runtime by
  `SigningNetwork`'s public IP gate, scheme restrictions, HTTP IP pinning,
  redirect re-vetting, and cryptographic verification of CMS structures,
  digest imprints, and certificates against the EU trusted lists.

## Inbound listeners and local network surface

### macOS

- **Zero listeners.** The macOS MVP ships with local smart card reader support
  only. It carries no Bonjour advertisements (`NSBonjourServices` is omitted),
  no local-network listening socket, and no local web daemon (the loopback
  Signature Creation Service / SCS is compiled out).
- **No Bluetooth.** CoreBluetooth is not declared or used on macOS; no
  Bluetooth permissions are declared or requested.
- **Entitlements.** `Config/RefineID-Store.entitlements` carries
  `com.apple.security.network.client = true` for outbound timestamping and
  revocation checks, and carries no `com.apple.security.network.server`
  entitlement and no `com.apple.security.device.bluetooth` entitlement.

### iOS

- **Remote Access Peripheral (RAPP).** When Remote Access (served over RAPP)
  is enabled on the phone, the device serves paired computers over local
  network and Bluetooth.
- **Bonjour.** Declares `_refineid-stream._tcp` in `NSBonjourServices` and
  describes usage in `NSLocalNetworkUsageDescription`. Serves stream
  connections while the app is active.
- **Bluetooth.** Declares `NSBluetoothAlwaysUsageDescription` and
  `bluetooth-peripheral` in `UIBackgroundModes` to serve paired computers from
  the background.
- **PIN isolation.** PIN 1 is supplied locally to the card on the phone;
  verification happens on-card. PIN 2 prompts appear strictly on the phone's
  physical screen. PIN codes never travel over Bluetooth or the local network
  ([pin-and-credentials.md](pin-and-credentials.md)).
