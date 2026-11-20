# App Store copy

Status: the store copy exactly as `Metadata/appstore.json` carries it, which
`Scripts/apple-app-store-connect-release-manager.swift metadata` pushes. If
the two differ, the JSON is what the store shows, and the difference is a
bug in this file.

The quoted copy keeps the characters the store receives, so the Finnish and
Swedish text carries its accents and the bullets stay bullets.

Character limits:
 * name 30
 * subtitle 30
 * promotional text 170
 * description 4000.

## Name

RefineID (all languages)

## Subtitle (<=30 characters)
- English: `Authenticate and sign`
- Suomi: `Tunnistaudu ja allekirjoita`
- Svenska: `Identifiera och underteckna`

## Promotional text (<=170 characters)
- English: `Authenticate and sign with your identity card.`
- Suomi: `Tunnistaudu ja allekirjoita henkilökortilla.`
- Svenska: `Identifiera dig och underteckna med identitetskortet.`

Each platform carries its own field; the macOS and iOS texts are the same
today, and the JSON keys both.

## Beta app description (TestFlight, app-level, both platforms)

### English

```text
RefineID brings the Finnish identity card to your Mac and iPhone.

Attach a USB smart-card reader, insert your identity card, and sign in to e-services directly in Safari with the certificate on your card.

RefineID is open source.
```

### Suomi

```text
RefineID tuo suomalaisen henkilökortin Maciin ja iPhoneen.

Liitä USB-kortinlukija, aseta henkilökortti lukijaan ja kirjaudu sähköisiin palveluihin suoraan Safarissa kortillasi.

RefineID on avointa lähdekoodia.
```

### Svenska

```text
RefineID tar det finländska identitetskortet till Mac och iPhone.

Anslut en USB-kortläsare, sätt i ditt identitetskort och logga in på e-tjänster direkt i Safari med certifikatet på ditt kort.

RefineID är öppen källkod.
```

## Release notes (What's New)

### English

```text
• Card activation and PIN code management
• Improved document handling
```

### Suomi

```text
• Kortin aktivointi ja tunnuslukujen hallinta
• Parannettu asiakirjojen käsittely
```

### Svenska

```text
• Aktivering av kort och hantering av koder
• Förbättrad dokumenthantering
```

One string per localization, shared by both platforms, written only when a
live version exists.

## iOS description

Platform versions carry their own description in App Store Connect. This one
names the iPhone and its wireless reader.

### English

```text
Identity card reader and signing tool.

You can also use your phone wirelessly as a card reader.

• Sign in to online services: Authenticate to e-services.
• Sign and verify documents: Create a qualified electronic signature and verify signed documents.
• Card and certificate management: Card activation and PIN code management.
• Privacy: No ads or tracking, open source: github.com/refineid
```

### Suomi

```text
Henkilökortinlukija ja allekirjoitustyökalu.

Voit käyttää myös puhelinta langattomasti kortinlukijana.

• Kirjaudu verkkopalveluihin: Tunnistaudu sähköisiin asiointipalveluihin.
• Allekirjoita ja tarkasta asiakirjoja: Tee asiakirjoihin hyväksytty sähköinen allekirjoitus ja tarkasta allekirjoitukset.
• Kortin ja varmenteiden hallinta: Kortin aktivointi ja tunnuslukujen hallinta.
• Yksityisyys: Ei mainoksia tai seurantaa, avointa lähdekoodia: github.com/refineid
```

### Svenska

```text
Identitetskortläsare och underskriftsverktyg.

Du kan även använda telefonen trådlöst som kortläsare.

• Logga in på e-tjänster: Identifiera dig i e-tjänster.
• Underteckna och granska dokument: Skapa en kvalificerad elektronisk underskrift och granska dokument.
• Hantering av kort och certifikat: Aktivering av kort och hantering av koder.
• Integritet: Ingen reklam eller spårning, öppen källkod: github.com/refineid
```

## macOS description

The Mac release works with a card and a reader: it names no wireless phone
reader, because remote use through a phone is not part of it. It also makes
no claim about which readers are "compatible", which says nothing a buyer
can act on: a card either fits the reader or it does not.

### English

```text
Identity card reader and signing tool.

Insert your identity card into a USB smart-card reader and sign in to e-services directly in Safari with the certificate on your card.

• Sign in to online services: Authenticate to e-services.
• Sign documents: Create a qualified electronic signature.
• Card and certificate management: Card activation and PIN code management.
• Privacy: No ads or tracking, open source: github.com/refineid
```

### Suomi

```text
Henkilökortinlukija ja allekirjoitustyökalu.

Aseta henkilökortti USB-kortinlukijaan ja kirjaudu sähköisiin palveluihin suoraan Safarissa kortin varmenteella.

• Kirjaudu verkkopalveluihin: Tunnistaudu sähköisiin asiointipalveluihin.
• Allekirjoita asiakirjoja: Tee asiakirjoihin hyväksytty sähköinen allekirjoitus.
• Kortin ja varmenteiden hallinta: Kortin aktivointi ja tunnuslukujen hallinta.
• Yksityisyys: Ei mainoksia tai seurantaa, avointa lähdekoodia: github.com/refineid
```

### Svenska

```text
Identitetskortläsare och underskriftsverktyg.

Sätt identitetskortet i en USB-kortläsare och logga in på e-tjänster direkt i Safari med kortets certifikat.

• Logga in på e-tjänster: Identifiera dig i e-tjänster.
• Underteckna dokument: Skapa en kvalificerad elektronisk underskrift.
• Hantering av kort och certifikat: Aktivering av kort och hantering av koder.
• Integritet: Ingen reklam eller spårning, öppen källkod: github.com/refineid
```

## Keywords
- English: `identity card`
- Suomi: `henkilökortti`
- Svenska: `identitetskort`

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
