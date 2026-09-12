# PKCS11Bridge

A PKCS#11 v2.40 module (read-and-sign only) implemented on top of
CryptoTokenKit and Security.framework. It never touches the card:
identities come from the keychain's token items and signatures from
`SecKeyCreateSignature`, so the system token daemon and the RefineID
token extension do all card communication and PIN handling. The module
advertises the protected authentication path, so PIN entry uses the
system dialog; `REFINEID_PKCS11_PIN_ENTRY=textual` withdraws that flag
so the consumer prompts instead, for remote and headless sessions
where no dialog can be answered.

Why it exists: macOS PKCS#11 consumers -- Java `SunPKCS11`, Firefox/NSS
card login, OpenSSH -- cannot reach CryptoTokenKit tokens. Apple's own
`/usr/lib/ssh-keychain.dylib` covers only RSA identities and only ssh;
current FINEID cards enroll EC P-384 keys by default, for which this
module is the only CTK-based PKCS#11 path.

Scope: one binary, two installed names, two disjoint profiles -- and
no name that exposes everything. The default name
(`librefineid_pkcs11.dylib`) serves authentication consumers (ssh,
browser login) and exposes only identities without the
contentCommitment (nonRepudiation) key usage: the qualified signature
key is legally weighty and belongs to a dedicated signing
application, not to every process that loads a PKCS#11 module or to
an ssh-agent's PIN cache. The signing name
(`librefineid_pkcs11_sign.dylib`) serves document-signing
applications (SunPKCS11/DSS) and exposes only the contentCommitment
identities, so a signing key picker cannot offer the wrong key. The
profile is decided by the file name the module is loaded under, so
the choice is always explicit in the consumer's configuration.

Status: working read-and-sign module, EC identities first. The full
PKCS#11 v3.2 surface is present: all 104 entry points exist
(unimplemented ones return `CKR_FUNCTION_NOT_SUPPORTED`, and the
legacy parallel-management pair returns `CKR_FUNCTION_NOT_PARALLEL`,
both as the spec directs). `C_GetInterfaceList`/`C_GetInterface`
publish three "PKCS 11" interfaces -- 3.2, 3.0, and legacy 2.40 -- and
`C_GetFunctionList` serves pre-3.0 consumers (OpenSSH, NSS, older
`SunPKCS11`) with the 2.40 list, whose version field the spec fixes at
2.40. Wired to CryptoTokenKit: slots enumerate present tokens
(Secure Enclave tokens excluded), each identity surfaces as a
certificate, public-key, and private-key object sharing one `CKA_ID`,
and `C_Sign` performs CKM_ECDSA through `SecKeyCreateSignature` with
DER-to-r||s conversion. Verified against a real FINEID card and a real server: the card signs
an ssh login end to end (`C_Sign` through `SecKeyCreateSignature`,
X9.62 DER converted to raw r||s).
Remaining ladder: authenticated `ssh` login, `keytool` (`SunPKCS11`),
then a PAdES signature from EU DSS.

Build and test:

```sh
swift build
swift test
```

Install (from the repository root):

```sh
Scripts/install-pkcs11-macos.sh
```

This builds the release configuration and installs
`/usr/local/lib/librefineid_pkcs11.dylib` -- named like the Linux
module, and located inside `ssh-agent`'s default PKCS#11 provider
allowlist (`/usr/lib*`, `/usr/local/lib*`; a module under `$HOME` is
refused). Use it:

```sh
ssh-keygen -D /usr/local/lib/librefineid_pkcs11.dylib   # list keys
ssh-add -s /usr/local/lib/librefineid_pkcs11.dylib      # add to agent
ssh -o PKCS11Provider=/usr/local/lib/librefineid_pkcs11.dylib user@host
```

At the `ssh-add` PIN prompt, enter the card PIN; OpenSSH refuses an
empty PIN for login-required tokens before ever calling the module.
When no PIN is supplied at all (as with `ssh-keygen -D` or the ssh
`PKCS11Provider` flow), the token's protected authentication path
applies and the system PIN dialog appears at signing time.

Specifications (https://docs.oasis-open.org/pkcs11/):

- Spec v3.2 (OASIS Standard, os include files): the implemented ABI.
  `Cryptoki.h` is verified against the official `pkcs11t.h`,
  `pkcs11f.h`, and `pkcs11.h` -- constants, structure layouts, all
  three function-list member orders, and all 104 prototype signatures.
  The legacy 2.40 surface is additionally verified against the v2.40
  errata01/os includes.
- Profiles v3.2: conformance targets. The object model follows the
  Public Certificates Token behavior (certificates readable without
  login, key pairs discoverable through matching `CKA_ID`); Baseline
  Provider conformance additionally needs a `CKO_PROFILE` object,
  tracked in TASKS.md.
- Current Mechanisms v3.0 (pkcs11-curr): normative mechanism
  definitions for the advertised set (CKM_ECDSA family first, RSA
  PKCS#1/PSS after). Note the signature format: CKM_ECDSA returns raw
  r||s, so the bridge converts the X9.62 DER that
  SecKeyCreateSignature produces.
- Historical Mechanisms and Functions v3.0: the do-not-implement
  register; nothing listed there ships in this module.
- Usage Guide v3.2: non-normative companion.
