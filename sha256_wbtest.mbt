// RFC 6234 official SHA-256 test vectors (plus reference-crossed extras
// derived from the FIPS-validated system implementation) pinning the
// self-implementation end to end: empty (padding only), "abc" (single
// block), 56-byte (exact pad boundary, forces the extra block), and
// million-a (long multi-block).

///|
test "SHA-256 utf8 entry wrapper" {
  assert_eq(
    sha256_utf8_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "SHA-256 RFC 6234 official vectors" {
  assert_eq(
    sha256_hex(@utf8.encode("")),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    sha256_hex(@utf8.encode("abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    sha256_hex(
      @utf8.encode("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  assert_eq(
    sha256_hex(@utf8.encode("a".repeat(1000000))),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
test "SHA-256 block-boundary and UTF-8 entry vectors" {
  assert_eq(
    sha256_hex(@utf8.encode("0123456789".repeat(8))),
    "af1909413b96cbb29927b3a67f3a8879c801a37be383e5f9b31df5fa8d10fa2b",
  )
  assert_eq(
    sha256_hex(@utf8.encode("a".repeat(64))),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
  assert_eq(
    sha256_hex(@utf8.encode("\u{6708}\u{5154}\u{89c4}\u{8303}\u{5f62}")),
    "2ddb16df6fb71d65402ce0df16a7ec1d0e34e869d5136e66697fc8fa9f4be2d7",
  )
}
