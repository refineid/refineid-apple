// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineID

  /// RFC 9285 examples and malformed-input boundaries.
  @Suite
  internal struct Base45Tests {
    @Test(arguments: [
      ("AB", "BB8"),
      ("Hello!!", "%69 VD92EX0"),
      ("base-45", "UJCLQE7W581"),
      ("ietf!", "QED8WEX0"),
    ])
    internal func rfcExamples(plain: String, encoded: String) {
      #expect(Base45.encode(Data(plain.utf8)) == encoded)
      #expect(Base45.decode(encoded) == Data(plain.utf8))
    }

    @Test
    internal func malformedTextIsRefused() {
      #expect(Base45.decode("A") == nil)
      #expect(Base45.decode("abc") == nil)
      #expect(Base45.decode(":::") == nil)
    }

    @Test
    internal func everyByteRoundTrips() {
      let bytes = Data((UInt8.min...UInt8.max))

      #expect(Base45.decode(Base45.encode(bytes)) == bytes)
      #expect(Base45.decode(Base45.encode(Data())) == Data())
    }
  }

#endif
