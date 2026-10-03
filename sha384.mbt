// SHA-384 (FIPS 180-4 sections 6.3/6.4) self-implementation, the RDFC-1.0
// hashAlgorithm=SHA384 variant (suite test075; REC section 3.1 option).
// Same 512-bit compression as SHA-512: 64-bit words, 80 rounds, message
// padded to 128-byte blocks with a 128-bit length field; the digest is
// the first six state words as 96 lowercase hex chars. The round
// constants are program-derived (first 80 primes, cube roots, fractional
// 64 bits) and the initial state the square roots of primes 23-53 —
// cross-checked against hashlib and pinned by the wbtest vectors.

///|
/// 80 round constants (FIPS 180-4 section 4.2.3, first 64 bits).
let sha384_round_constants : Array[UInt64] = [
  0x428a2f98d728ae22UL, 0x7137449123ef65cdUL, 0xb5c0fbcfec4d3b2fUL, 0xe9b5dba58189dbbcUL,
  0x3956c25bf348b538UL, 0x59f111f1b605d019UL, 0x923f82a4af194f9bUL, 0xab1c5ed5da6d8118UL,
  0xd807aa98a3030242UL, 0x12835b0145706fbeUL, 0x243185be4ee4b28cUL, 0x550c7dc3d5ffb4e2UL,
  0x72be5d74f27b896fUL, 0x80deb1fe3b1696b1UL, 0x9bdc06a725c71235UL, 0xc19bf174cf692694UL,
  0xe49b69c19ef14ad2UL, 0xefbe4786384f25e3UL, 0x0fc19dc68b8cd5b5UL, 0x240ca1cc77ac9c65UL,
  0x2de92c6f592b0275UL, 0x4a7484aa6ea6e483UL, 0x5cb0a9dcbd41fbd4UL, 0x76f988da831153b5UL,
  0x983e5152ee66dfabUL, 0xa831c66d2db43210UL, 0xb00327c898fb213fUL, 0xbf597fc7beef0ee4UL,
  0xc6e00bf33da88fc2UL, 0xd5a79147930aa725UL, 0x06ca6351e003826fUL, 0x142929670a0e6e70UL,
  0x27b70a8546d22ffcUL, 0x2e1b21385c26c926UL, 0x4d2c6dfc5ac42aedUL, 0x53380d139d95b3dfUL,
  0x650a73548baf63deUL, 0x766a0abb3c77b2a8UL, 0x81c2c92e47edaee6UL, 0x92722c851482353bUL,
  0xa2bfe8a14cf10364UL, 0xa81a664bbc423001UL, 0xc24b8b70d0f89791UL, 0xc76c51a30654be30UL,
  0xd192e819d6ef5218UL, 0xd69906245565a910UL, 0xf40e35855771202aUL, 0x106aa07032bbd1b8UL,
  0x19a4c116b8d2d0c8UL, 0x1e376c085141ab53UL, 0x2748774cdf8eeb99UL, 0x34b0bcb5e19b48a8UL,
  0x391c0cb3c5c95a63UL, 0x4ed8aa4ae3418acbUL, 0x5b9cca4f7763e373UL, 0x682e6ff3d6b2b8a3UL,
  0x748f82ee5defb2fcUL, 0x78a5636f43172f60UL, 0x84c87814a1f0ab72UL, 0x8cc702081a6439ecUL,
  0x90befffa23631e28UL, 0xa4506cebde82bde9UL, 0xbef9a3f7b2c67915UL, 0xc67178f2e372532bUL,
  0xca273eceea26619cUL, 0xd186b8c721c0c207UL, 0xeada7dd6cde0eb1eUL, 0xf57d4f7fee6ed178UL,
  0x06f067aa72176fbaUL, 0x0a637dc5a2c898a6UL, 0x113f9804bef90daeUL, 0x1b710b35131c471bUL,
  0x28db77f523047d84UL, 0x32caab7b40c72493UL, 0x3c9ebe0a15c9bebcUL, 0x431d67c49c100d4cUL,
  0x4cc5d4becb3e42b6UL, 0x597f299cfc657e2aUL, 0x5fcb6fab3ad6faecUL, 0x6c44198c4a475817UL,
]

///|
/// Initial state: fractional 64 bits of the square roots of primes
/// 23-53 (FIPS 180-4 section 5.3.3 — the 9th-16th primes, NOT the first
/// eight; those give SHA-512's state).
let sha384_initial_state : Array[UInt64] = [
  0xcbbb9d5dc1059ed8UL, 0x629a292a367cd507UL, 0x9159015a3070dd17UL, 0x152fecd8f70e5939UL,
  0x67332667ffc00b31UL, 0x8eb44a8768581511UL, 0xdb0c2e0d64f98fa7UL, 0x47b5481dbefa4fa4UL,
]

///|
const SHA384_ALL_ONES : UInt64 = 0xFFFFFFFFFFFFFFFFUL

///|
fn sha384_rotr(word : UInt64, count : Int) -> UInt64 {
  (word >> count) | (word << (64 - count))
}

///|
/// Small sigma zero (section 4.1.2): ROTR1 ^ ROTR8 ^ SHR7.
fn sha384_sigma0(word : UInt64) -> UInt64 {
  sha384_rotr(word, 1) ^ sha384_rotr(word, 8) ^ (word >> 7)
}

///|
/// Small sigma one (section 4.1.2): ROTR19 ^ ROTR61 ^ SHR6.
fn sha384_sigma1(word : UInt64) -> UInt64 {
  sha384_rotr(word, 19) ^ sha384_rotr(word, 61) ^ (word >> 6)
}

///|
/// Big sigma zero (section 4.1.2): ROTR28 ^ ROTR34 ^ ROTR39.
fn sha384_big_sigma0(word : UInt64) -> UInt64 {
  sha384_rotr(word, 28) ^ sha384_rotr(word, 34) ^ sha384_rotr(word, 39)
}

///|
/// Big sigma one (section 4.1.2): ROTR14 ^ ROTR18 ^ ROTR41.
fn sha384_big_sigma1(word : UInt64) -> UInt64 {
  sha384_rotr(word, 14) ^ sha384_rotr(word, 18) ^ sha384_rotr(word, 41)
}

///|
/// Choose (section 4.1.2 Ch), XOR-with-ones shape for the flat expression.
fn sha384_choose(
  word : UInt64,
  then_word : UInt64,
  else_word : UInt64,
) -> UInt64 {
  (word & then_word) ^ (else_word & (word ^ SHA384_ALL_ONES))
}

///|
/// Majority (section 4.1.2 Maj).
fn sha384_majority(first : UInt64, second : UInt64, third : UInt64) -> UInt64 {
  (first & second) ^ (first & third) ^ (second & third)
}

///|
/// Digest computation: whole-buffer padding to 128-byte blocks (0x80,
/// zeros, 16-byte big-endian bit length — the upper eight length bytes
/// stay zero for inputs far below 2 exabytes), then the 80-round
/// compression per section 6.4. Returns the eight final state words;
/// the SHA-384 digest is the first six.
fn sha384_words(data : Bytes) -> Array[UInt64] {
  let message_length = data.length()
  let bit_length = message_length.to_uint64() * 8UL
  let padded : Array[Byte] = []
  for index in 0..<message_length {
    padded.push(data[index])
  }
  padded.push((128 : Int).to_byte())
  while padded.length() % 128 != 112 {
    padded.push((0 : Int).to_byte())
  }
  for _length_byte in 0..<8 {
    padded.push((0 : Int).to_byte())
  }
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    padded.push((bit_length >> shift).to_uint().reinterpret_as_int().to_byte())
  }
  let state : Array[UInt64] = Array::make(8, 0UL)
  for index in 0..<8 {
    state[index] = sha384_initial_state[index]
  }
  let mut block_base = 0
  while block_base < padded.length() {
    let schedule : Array[UInt64] = Array::make(80, 0UL)
    for t in 0..<16 {
      let base = block_base + t * 8
      schedule[t] = padded[base].to_uint().to_uint64() << 56
      schedule[t] = schedule[t] | (padded[base + 1].to_uint().to_uint64() << 48)
      schedule[t] = schedule[t] | (padded[base + 2].to_uint().to_uint64() << 40)
      schedule[t] = schedule[t] | (padded[base + 3].to_uint().to_uint64() << 32)
      schedule[t] = schedule[t] | (padded[base + 4].to_uint().to_uint64() << 24)
      schedule[t] = schedule[t] | (padded[base + 5].to_uint().to_uint64() << 16)
      schedule[t] = schedule[t] | (padded[base + 6].to_uint().to_uint64() << 8)
      schedule[t] = schedule[t] | padded[base + 7].to_uint().to_uint64()
    }
    for t in 16..<80 {
      schedule[t] = sha384_sigma1(schedule[t - 2]) +
        schedule[t - 7] +
        sha384_sigma0(schedule[t - 15]) +
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
    for round_index in 0..<80 {
      let sum_one = working_h +
        sha384_big_sigma1(working_e) +
        sha384_choose(working_e, working_f, working_g) +
        sha384_round_constants[round_index] +
        schedule[round_index]
      let sum_two = sha384_big_sigma0(working_a) +
        sha384_majority(working_a, working_b, working_c)
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
    block_base = block_base + 128
  }
  state
}

///|
/// Digest as 96-char lowercase hex (the RDFC-1.0 ordering-key shape for
/// the SHA384 variant; six state words truncated per section 6.5).
pub fn sha384_hex(data : Bytes) -> String {
  let builder = StringBuilder()
  let state = sha384_words(data)
  for index in 0..<6 {
    // 16 nibbles per 64-bit word
    for shift in [60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0] {
      let nibble = ((state[index] >> shift).to_uint() & 15).reinterpret_as_int()
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
/// SHA-384 of a string via UTF-8 bytes (the RDFC-1.0 SHA384 entry shape).
pub fn sha384_utf8_hex(input : String) -> String {
  sha384_hex(@utf8.encode(input))
}
