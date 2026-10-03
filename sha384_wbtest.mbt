// SHA-384 official-shape vectors (hashlib cross-checked; same verdict
// discipline as sha256_wbtest.mbt — FIPS 180-4 self-implementation is
// self-certified against external authority, not against replicas).

///|
test "SHA-384 hashlib vectors" {
  // empty input (padding only)
  assert_eq(
    sha384_hex(@utf8.encode("")),
    "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b",
  )
  // "abc" — the FIPS one-block classic
  assert_eq(
    sha384_hex(@utf8.encode("abc")),
    "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
  )
  // 64-byte input — exact 128-byte half block
  assert_eq(
    sha384_hex(@utf8.encode("a".repeat(64))),
    "2e404b9339da795776e510d96930b3be2904c500395b8cb7413334b82d4dec413b4b8113045a05bbbcff846f027423f6",
  )
  // million a — multi-block stress
  assert_eq(
    sha384_hex(@utf8.encode("a".repeat(1000000))),
    "9d0e1809716474cb086e834e310a4a1ced149e9c00f248527972cec5704c2a5b07b8b3dc38ecc4ebae97ddd87f3d8985",
  )
  // non-ASCII entry through the utf8 wrapper
  assert_eq(
    sha384_utf8_hex("月兔规范形"),
    "56864eafcbfe466f51f326d5224717a92228dd2389b338776bd4d12018eb7e8c5a5b15be1e861b076185d4e5ed2db554",
  )
}
