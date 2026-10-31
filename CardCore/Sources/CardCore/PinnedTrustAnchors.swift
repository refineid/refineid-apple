// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The root certificates this application pins as trust anchors.
///
/// Each constant is one opaque, externally published DER certificate,
/// base64 encoded. The DVV roots are published at
/// `proxy.fineid.fi/ca/dvvroot3rc.crt` and `proxy.fineid.fi/ca/dvvroot3ec.crt`
/// (FINEID S2 v5.2 section 8.5, fingerprints in section 8.2); the
/// time-stamping root at
/// `crt.sectigo.com/SectigoQualifiedTimeStampingRootR45.crt`. The same
/// certificates are pinned by refineid-core.
internal enum PinnedTrustAnchors {
  /// DVV Gov. Root CA - G3 RSA.
  private static let dvvRootG3Rsa = """
    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
    """

  /// DVV Gov. Root CA - G3 ECC.
  private static let dvvRootG3Ecc = """
    MIIC3zCCAmWgAwIBAgIPAXlAp7XafZAcqUvyWq6uMAoGCCqGSM49BAMDMIGgMQswCQYDVQQGEwJG
    STEnMCUGA1UECgweRGlnaS0gamEgdmFlc3RvdGlldG92aXJhc3RvIENBMSkwJwYDVQQLDCBDZXJ0
    aWZpY2F0aW9uIEF1dGhvcml0eSBTZXJ2aWNlczEZMBcGA1UECwwQVmFybWVubmVwYWx2ZWx1dDEi
    MCAGA1UEAwwZRFZWIEdvdi4gUm9vdCBDQSAtIEczIEVDQzAeFw0yMTA1MDYwNzUxMzBaFw00MjA1
    MDUwNzUxMzBaMIGgMQswCQYDVQQGEwJGSTEnMCUGA1UECgweRGlnaS0gamEgdmFlc3RvdGlldG92
    aXJhc3RvIENBMSkwJwYDVQQLDCBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eSBTZXJ2aWNlczEZMBcG
    A1UECwwQVmFybWVubmVwYWx2ZWx1dDEiMCAGA1UEAwwZRFZWIEdvdi4gUm9vdCBDQSAtIEczIEVD
    QzB2MBAGByqGSM49AgEGBSuBBAAiA2IABLMtyj+KrpIkCpLKBebiaw19zy+Jq6daVfcGpmBeoy6v
    SG3dDsQzKsqrVJl6iIrPsy8TKNbd67Oo1lnK58UaDtyNiqywa21Rhu+USvrovkvtVnHwHepLtfVj
    WRK4r4mxMKNjMGEwHwYDVR0jBBgwFoAUuXaAw4P4zyLahevOFE5VrF5aCpAwHQYDVR0OBBYEFLl2
    gMOD+M8i2oXrzhROVaxeWgqQMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MAoGCCqG
    SM49BAMDA2gAMGUCMQC8Je7hVl91ZuhAIdRyRaVfO3f6zscgVg55aKWxvvDi9SWBDI+iaMJdyWpF
    P3Y5rSQCMESDaOZhMhOxhfJt1Ty1/oewEzbMV/ceO9lqU+Qa6kD7LbtdrQvuAQBDR0h5dfi+cw==
    """

  /// Sectigo Qualified Time Stamping Root R45.
  private static let sectigoQualifiedTimeStampingRootR45 = """
    MIIFiDCCA3CgAwIBAgIQeyTgGTPHlt/EBM4BFh9TczANBgkqhkiG9w0BAQwFADBeMQswCQYDVQQG
    EwJFUzEcMBoGA1UEChMTU2VjdGlnbyAoRXVyb3BlKSBTTDExMC8GA1UEAxMoU2VjdGlnbyBRdWFs
    aWZpZWQgVGltZSBTdGFtcGluZyBSb290IFI0NTAeFw0yMDEwMDUwMDAwMDBaFw00NTEwMDQyMzU5
    NTlaMF4xCzAJBgNVBAYTAkVTMRwwGgYDVQQKExNTZWN0aWdvIChFdXJvcGUpIFNMMTEwLwYDVQQD
    EyhTZWN0aWdvIFF1YWxpZmllZCBUaW1lIFN0YW1waW5nIFJvb3QgUjQ1MIICIjANBgkqhkiG9w0B
    AQEFAAOCAg8AMIICCgKCAgEAmxd6gVF16BNKraRrsc8dxZddzMAXlGxX8jMin2aivnwcsTL/bTZq
    gvXqxz98m8XaeSYJn3WOnebxiw7qdfDSFGR/Gm+i+/ExnnW2zEdYZNBPU9jl8Tq6e1y6fjOrNMfM
    8tDlgHG7AnLEcP9cIrk1eC6O2CmMzu/YMMwhzIFVdGx0/heH/cq9+GtV++L0oEE57277c2IjU9hA
    rl3o4L3YsUmBwPXF+uILNRMsCMacB1kh0zMn8+wH7WKh8tL/78IhqTglWoIHPOEuGS74/r+5ixCj
    hsaBJmftiKjIkEC+mbdxOMwK6bB7PcGtsMY1IZxBr0bbJhX0OL675VCc3sH0CDMEaxWK82xg626u
    lHkO1i6u1js1dpHRBzSPwm8IbbI5HMHpxe9zLmTRTjMasOaa4jAXQIYdmTcTRCGGanTiS3JRWDz4
    8mLhfAhLi2ktH7FF8ZnRazJJJrJaEZgq32Fn3uBYV6FzwYrBdwBgQfhMJmlC9uRH6O9IZarm4j2n
    tgobjKNCfuzu1D7nbYT5NSr79P2CKNkgdGErDOf5d+hnatg/5Ga/3Bj0Ft6wRNmcM1Soof+/Baum
    1iCAw1Yq2Nt8wDEn2gs3SZOSpgBTQyXvaNIkdnSo/aEkn52a3vdjJtqJkVcweWn+2ZXAfQsCA9VA
    eIbDC5beYlrdTAaVg0pHVwECAwEAAaNCMEAwHQYDVR0OBBYEFFmBqMOFZOfjRKRpUiaUU/Y7De7e
    MA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBDAUAA4ICAQAQ5fIz
    OSb7rPwmDEVfsfqAeNeGDOJYnJBZ2/LwAskopaGtwaT26JbIKEVZNrmX/AhGuMRa9FhflWPyzqd+
    XTKaaNTHMO3SrqUGco89x8bF7gIfNtQOkahq9VFhb1Hde6Cg3AqA/BcjT9Nzpxf0tlDoU/v8x2qL
    HFcri+bOpHOwZoVqybhHv64qrcKy1uU52Wwu4x7efGivn6lAdKdgTh9UD4Pwbmno16DtDWpIAAr/
    UgujWAymZPPvU337tkGjcGdkMmw8fFsU+gyoArSMT68vNZVRyDdA1AYKpAHAjPm/UtMXmKisnqqZ
    GFwIetffgtRuEO8ic06Kaz5avA1eaSdg2o8bdVWV8nbaytKpUccWxismeIIZD9yYRq/6Wr+sn/Vf
    KhfnQoEQnlQvzddjePWT8XSKLDARz5FJ5zUkLsEB/6bCweHfI3vlLKRBO2yOOCq/Fp92ww97BERo
    DaPJpuONrAmef+irVDOwQ4K6jTUe+tiigKtktRYjnrKbsk0wA9e2zokx8ECjx+NPGIXRYCViJ2ZX
    fb/RMwmXpWW9HsqkkE4QYu4WkuLFnNyUxazfKzoh1tBM6nmQgDofehzXIYIKE57APNIH8khQFUii
    eadK8N1x6SDuR5K0jRf9Mu/ExJsHzqLvXGgomeMlPvjoNbzzx8+7rIlPbXGmg1td75VgUg==
    """

  /// The pinned certificate-issuing roots.
  internal static var certificateIssuing: [Data] {
    [Self.dvvRootG3Rsa, Self.dvvRootG3Ecc].compactMap(Self.decoded)
  }

  /// The pinned time-stamping roots.
  internal static var timeStamping: [Data] {
    [Self.sectigoQualifiedTimeStampingRootR45].compactMap(Self.decoded)
  }

  /// The DER bytes of one wrapped base64 constant.
  private static func decoded(_ encoded: String) -> Data? {
    Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
  }
}
