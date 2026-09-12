# App Store copy

Status: reconciled with `Metadata/appstore.json`, 2026-08-16. The JSON is
what `Scripts/apple-app-store-connect-release-manager.swift metadata`
pushes; this file explains and mirrors it. If the two differ, the JSON
is what the store shows, and the difference is a bug in this file.

Character limits:
 * name 30
 * subtitle 30
 * promotional text 170
 * description 4000.

## Name

RefineID (all languages)

## Subtitle (<=30 characters)

- en: `Use your identity card online`
- fi: `Käytä henkilökorttia verkossa`
- sv: `Använd identitetskortet online`

## Promotional text (<=170 characters)

- en: `Log in to services with your identity card and sign documents.`
- fi: `Kirjaudu palveluihin henkilökortilla ja allekirjoita asiakirjoja.`
- sv: `Logga in på tjänster med ditt identitetskort och underteckna dokument.`

The macOS and iOS promotional texts are the same: both platforms sign
documents since 26.8.16.

## iOS description

### English

RefineID brings the Finnish identity card to iPhone.

Read your card with a USB-C smart-card reader, or wirelessly on iPhone,
then sign in to e-services directly in Safari with the certificate on
your card. Pick a PDF in RefineID to sign it with a qualified signature.

RefineID is open source: github.com/refineid/refineid-apple

### Suomi

RefineID tuo suomalaisen henkilökortin iPhoneen.

Lue korttisi USB-C-kortinlukijalla, tai iPhonessa langattomasti, ja
kirjaudu sähköisiin palveluihin suoraan Safarissa kortin varmenteella.
Valitse PDF RefineID:ssä ja allekirjoita se hyväksytyllä sähköisellä
allekirjoituksella.

RefineID on avointa lähdekoodia: github.com/refineid/refineid-apple

### Svenska

RefineID tar det finländska identitetskortet till iPhone.

Läs kortet med en USB-C-kortläsare, eller trådlöst på iPhone, och logga
in på e-tjänster direkt i Safari med kortets certifikat. Välj en PDF i
RefineID för att underteckna den med en kvalificerad elektronisk
underskrift.

RefineID är öppen källkod: github.com/refineid/refineid-apple

## macOS description

Platform versions carry their own description in App Store Connect; the
iOS text above names the iPhone and its readers, so the Mac release
needs this one. Same rules: 4000 characters, en/fi/sv.

### English

A reader for the Finnish identity card.

Insert your identity card into a USB smart-card reader and sign in to
e-services directly in Safari with the certificate on your card. Drop a
PDF on RefineID to sign it with a qualified signature.

RefineID is open source: github.com/refineid/refineid-apple

### Suomi

Suomalaisen henkilökortin lukija.

Aseta henkilökortti USB-kortinlukijaan ja kirjaudu sähköisiin
palveluihin suoraan Safarissa kortin varmenteella. Pudota PDF
RefineID:hen ja allekirjoita se hyväksytyllä sähköisellä
allekirjoituksella.

RefineID on avointa lähdekoodia: github.com/refineid/refineid-apple

### Svenska

En läsare för det finländska identitetskortet.

Sätt identitetskortet i en USB-kortläsare och logga in på e-tjänster
direkt i Safari med kortets certifikat. Släpp en PDF på RefineID för
att underteckna den med en kvalificerad elektronisk underskrift.

RefineID är öppen källkod: github.com/refineid/refineid-apple

## Keywords

- en: `identity card`
- fi: `henkilökortti`
- sv: `identitetskort`

## App Store Connect fields

The web-form values, so the record is filled from one reviewed place.
All are public; none is a secret.

- **Support URL:** `https://www.refineid.fi/`
- **Marketing URL:** `https://www.refineid.fi/`
- **Privacy Policy URL**, per localization:
  - en: `https://www.refineid.fi/privacy-policy/`
  - fi: `https://www.refineid.fi/tietosuojaseloste/`
  - sv: `https://www.refineid.fi/integritetspolicy/`
- **Copyright:** `2026 Petri Koistinen`

### App Review / Beta App Review contact

- **Name:** Petri Koistinen
- **Email:** `petri.koistinen@refineid.fi`
- **Phone:** `+358449564098`

Not `iki.fi`: the review contact is the business address, the same one
the privacy pages and `security.txt` publish.
