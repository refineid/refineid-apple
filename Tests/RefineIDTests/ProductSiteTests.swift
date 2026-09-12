// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineID

  /// The About box names the public site from one definition.
  @Suite
  internal struct ProductSiteTests {
    @Test
    internal func addressIsThePublicSite() {
      #expect(ProductSite.label == "www.refineid.fi")
      #expect(ProductSite.url.absoluteString == "https://www.refineid.fi/")
      #expect(ProductSite.copyright == "Copyright 2026 Petri Koistinen")
    }

    @Test
    internal func bundleCopyrightMatchesTheAboutLine() {
      let bundled =
        Bundle.main.object(
          forInfoDictionaryKey: "NSHumanReadableCopyright"
        ) as? String
      #expect(bundled == ProductSite.copyright)
    }
  }

#endif
