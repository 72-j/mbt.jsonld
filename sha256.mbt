// SHA-256 (FIPS 180-4) self-implementation for the RDFC-1.0 battle
// (spec.md section 8.132 route A; user ruling 2026-10-03: option b,
// self-implementation self-certified against RFC 6234 official vectors).
// SHA-256 is a core dependency of the six-step algorithm, not a tail
// piece: the hex string of first-degree / n-degree hashes IS the bnode
// ordering key. Whole-buffer padding shape, 512-bit blocks, 64 rounds.

///|
/// 64 round constants: first 32 bits of the fractional parts of the
/// cube roots of the first 64 primes (FIPS 180-4 section 4.2.3).
let sha256_round_constants : Array[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
/// Initial state: first 32 bits of the fractional parts of the square
/// roots of the first 8 primes (FIPS 180-4 section 4.2.2).
let sha256_initial_state : Array[UInt] = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
  0x5be0cd19,
]

///|
/// Rotate-right (FIPS 180-4 section 4.1.2 rotr); UInt logical shift
/// keeps the high bits zero-filled.
fn sha256_rotr(word : UInt, count : Int) -> UInt {
  (word >> count) | (word << (32 - count))
}

///|
/// Small sigma zero (FIPS 180-4 section 4.1.2): ROTR7 ^ ROTR18 ^ SHR3.
fn sha256_sigma0(word : UInt) -> UInt {
  sha256_rotr(word, 7) ^ sha256_rotr(word, 18) ^ (word >> 3)
}

///|
/// Small sigma one (FIPS 180-4 section 4.1.2): ROTR17 ^ ROTR19 ^ SHR10.
fn sha256_sigma1(word : UInt) -> UInt {
  sha256_rotr(word, 17) ^ sha256_rotr(word, 19) ^ (word >> 10)
}

///|
/// Big sigma zero (FIPS 180-4 section 4.1.2): ROTR2 ^ ROTR13 ^ ROTR22.
fn sha256_big_sigma0(word : UInt) -> UInt {
  sha256_rotr(word, 2) ^ sha256_rotr(word, 13) ^ sha256_rotr(word, 22)
}

///|
/// Big sigma one (FIPS 180-4 section 4.1.2): ROTR6 ^ ROTR11 ^ ROTR25.
fn sha256_big_sigma1(word : UInt) -> UInt {
  sha256_rotr(word, 6) ^ sha256_rotr(word, 11) ^ sha256_rotr(word, 25)
}

///|
/// Choose (FIPS 180-4 section 4.1.2 Ch): (e AND f) XOR (NOT e AND g);
/// NOT shaped as XOR with all-ones to keep the expression flat.
const SHA256_ALL_ONES : UInt = 0xFFFFFFFF

///|
fn sha256_choose(word : UInt, then_word : UInt, else_word : UInt) -> UInt {
  (word & then_word) ^ (else_word & (word ^ SHA256_ALL_ONES))
}

///|
/// Majority (FIPS 180-4 section 4.1.2 Maj): (a AND b) XOR (a AND c) XOR
/// (b AND c).
fn sha256_majority(first : UInt, second : UInt, third : UInt) -> UInt {
  (first & second) ^ (first & third) ^ (second & third)
}

///|
/// Digest computation: whole-buffer padding (FIPS 180-4 section 5.1.1:
/// 0x80, zeros, 64-bit big-endian bit length) then 512-bit block
/// compression per section 6.2. Returns the 8 final state words.
fn sha256_words(data : Bytes) -> Array[UInt] {
  let message_length = data.length()
  let bit_length = message_length.to_uint64() * 8UL
  let padded : Array[Byte] = []
  for index in 0..<message_length {
    padded.push(data[index])
  }
  padded.push((128 : Int).to_byte())
  while padded.length() % 64 != 56 {
    padded.push((0 : Int).to_byte())
  }
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    padded.push((bit_length >> shift).to_uint().reinterpret_as_int().to_byte())
  }
  let state : Array[UInt] = Array::make(8, 0)
  for index in 0..<8 {
    state[index] = sha256_initial_state[index]
  }
  let mut block_base = 0
  while block_base < padded.length() {
    let schedule : Array[UInt] = Array::make(64, 0)
    for t in 0..<16 {
      let base = block_base + t * 4
      schedule[t] = padded[base].to_uint() << 24
      schedule[t] = schedule[t] | (padded[base + 1].to_uint() << 16)
      schedule[t] = schedule[t] | (padded[base + 2].to_uint() << 8)
      schedule[t] = schedule[t] | padded[base + 3].to_uint()
    }
    for t in 16..<64 {
      schedule[t] = sha256_sigma1(schedule[t - 2]) +
        schedule[t - 7] +
        sha256_sigma0(schedule[t - 15]) +
        schedule[t - 16]
    }
    let mut working_a = state[0]
    let mut working_b = state[1]
    let mut working_c = state[2]
    let mut working_d = state[3]
    let mut working_e = state[4]
    let mut working_f = state[5]
    let mut working_g = state[6]
    let mut working_h = state[7]
    for round_index in 0..<64 {
      let sum_one = working_h +
        sha256_big_sigma1(working_e) +
        sha256_choose(working_e, working_f, working_g) +
        sha256_round_constants[round_index] +
        schedule[round_index]
      let sum_two = sha256_big_sigma0(working_a) +
        sha256_majority(working_a, working_b, working_c)
      working_h = working_g
      working_g = working_f
      working_f = working_e
      working_e = working_d + sum_one
      working_d = working_c
      working_c = working_b
      working_b = working_a
      working_a = sum_one + sum_two
    }
    state[0] = state[0] + working_a
    state[1] = state[1] + working_b
    state[2] = state[2] + working_c
    state[3] = state[3] + working_d
    state[4] = state[4] + working_e
    state[5] = state[5] + working_f
    state[6] = state[6] + working_g
    state[7] = state[7] + working_h
    block_base = block_base + 64
  }
  state
}

///|
/// Digest as 64-char lowercase hex (the RDFC-1.0 ordering-key shape,
/// rdfc-1.0 spec section 4.6.2: hash expressed as lowercase hex string).
fn sha256_hex(data : Bytes) -> String {
  let builder = StringBuilder()
  for word in sha256_words(data) {
    for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
      let nibble = ((word >> shift) & 15).reinterpret_as_int()
      let digit_char = if nibble < 10 {
        Int::unsafe_to_char(48 + nibble)
      } else {
        Int::unsafe_to_char(87 + nibble)
      }
      builder.write_char(digit_char)
    }
  }
  builder.to_string()
}

///|
/// SHA-256 of a string via UTF-8 bytes (the RDFC-1.0 entry shape: the
/// algorithm hashes the canonical serialization strings, section 4.6.2).
fn sha256_utf8_hex(input : String) -> String {
  sha256_hex(@utf8.encode(input))
}
