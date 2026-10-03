///|
/// 测试域便捷包装（**原 `rdfc10_canonicalize` 的调用点专用**）：该入口真调用点仅本测试文件，
/// 役62「转正入口收紧」时删除（生产面 = `rdfc10_canonicalize_with_hash`，套件 harness 用）。
fn canon_string(input_nquads : String) -> Result[String, JsonLdError] {
  match rdfc10_canonicalize_with_hash(input_nquads, C14nHashAlgorithm::Sha256) {
    Ok((canonical_form, _mapping)) => Ok(canonical_form)
    Err(message) => Err(message)
  }
}

// RDFC-1.0 whitebox anchors: byte-inlined suite pairs from
// .rdf-tests/rdf-canon/rdfc10 (whitebox tests cannot read files) plus
// unit shapes for the ordering machinery. The full 86-entry suite
// harness is the next battle (canon_rdfc10_test.mbt, blackbox + @fs).

///|
/// Code point order, not String::compare's length-first order: "_:b10"
/// sorts before "_:b2<h1>" on the differing third character.
test "c14n_compare code point order" {
  assert_eq(c14n_compare("", ""), 0)
  assert_eq(c14n_compare("abc", "abc"), 0)
  assert_true(c14n_compare("b", "aab") > 0)
  assert_true(c14n_compare("_:b10<xx>", "_:b2<xx>") < 0)
  assert_true(c14n_compare("_:b2<xx>", "_:b10<xx>") > 0)
}

///|
/// Lexicographic next-permutation: 3! = 6 arrangements in ascending
/// order, duplicates collapse (two identical labels yield one round trip).
test "c14n_next_permutation enumeration" {
  let items = ["b", "a", "c"]
  items.sort_by(fn(first, second) { c14n_compare(first, second) })
  let mut count = 1
  while c14n_next_permutation(items) {
    count = count + 1
  }
  assert_eq(count, 6)
  assert_eq(items[0], "c")
  let duplicated = ["e", "e"]
  let mut duplicate_count = 1
  while c14n_next_permutation(duplicated) {
    duplicate_count = duplicate_count + 1
  }
  assert_eq(duplicate_count, 1)
}

///|
/// Suite test001c: empty input, empty canonical form.
test "rdfc10 empty document" {
  assert_eq(canon_string(""), Ok(""))
}

///|
/// Suite test002c: no blank nodes — byte passthrough.
test "rdfc10 no bnodes passthrough" {
  let document = "<http://example.org/test#example1> <http://example.org/vocab#p> <http://example.org/test#example2> .\n"
  assert_eq(canon_string(document), Ok(document))
}

///|
/// Suite test003c: one blank node takes the first canonical label.
test "rdfc10 single bnode" {
  let document = "_:e0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Foo> .\n"
  let expected = "_:c14n0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Foo> .\n"
  assert_eq(canon_string(document), Ok(expected))
}

///|
/// Suite test004c: two quads on one bnode, output sorted code point
/// order ("embed" line before the rdf-syntax-ns#type line).
test "rdfc10 bnode plus embed sorted output" {
  let document = "_:e0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Foo> .\n" +
    "_:e0 <http://example.org/vocab#embed> <http://example.org/test#example> .\n"
  let expected = "_:c14n0 <http://example.org/vocab#embed> <http://example.org/test#example> .\n" +
    "_:c14n0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/vocab#Foo> .\n"
  assert_eq(canon_string(document), Ok(expected))
}

///|
/// Suite test013c: typed literal plus IRI cycle (no bnodes at all).
test "rdfc10 type-coerced cycle iri only" {
  let first = "<http://example.org/test#example1> <http://example.org/vocab#date> \"2011-01-25T00:00:00Z\"^^<http://www.w3.org/2001/XMLSchema#dateTime> .\n"
  let second = "<http://example.org/test#example1> <http://example.org/vocab#embed> <http://example.org/test#example2> .\n"
  let third = "<http://example.org/test#example2> <http://example.org/vocab#parent> <http://example.org/test#example1> .\n"
  assert_eq(canon_string(first + second + third), Ok(first + second + third))
}

///|
/// Suite test021c: circle of 2 — the n-degree path assigns 0 and 1 by
/// exploration, not by input order.
test "rdfc10 circle of 2" {
  let document = "_:e0 <http://example.org/vocab#next> _:e1 .\n" +
    "_:e1 <http://example.org/vocab#next> _:e0 .\n"
  let expected = "_:c14n0 <http://example.org/vocab#next> _:c14n1 .\n" +
    "_:c14n1 <http://example.org/vocab#next> _:c14n0 .\n"
  assert_eq(canon_string(document), Ok(expected))
}

///|
/// Suite test022c: double circle of 2 — both blank nodes share first
/// degree hashes, forcing the full hash-n-degree path with permutations.
test "rdfc10 double circle of 2" {
  let document = "_:e0 <http://example.org/vocab#next> _:e1 .\n" +
    "_:e0 <http://example.org/vocab#prev> _:e1 .\n" +
    "_:e1 <http://example.org/vocab#next> _:e0 .\n" +
    "_:e1 <http://example.org/vocab#prev> _:e0 .\n"
  let expected = "_:c14n0 <http://example.org/vocab#next> _:c14n1 .\n" +
    "_:c14n0 <http://example.org/vocab#prev> _:c14n1 .\n" +
    "_:c14n1 <http://example.org/vocab#next> _:c14n0 .\n" +
    "_:c14n1 <http://example.org/vocab#prev> _:c14n0 .\n"
  assert_eq(canon_string(document), Ok(expected))
}

///|
/// Suite test074c (NegativeEvalTest): the 10-node poison clique (complete
/// digraph with self-loops, suite predicate) must end in an error via the
/// work budget, not hang or crash.
test "rdfc10 poison clique signals error" {
  let builder = StringBuilder()
  for first in 0..<10 {
    for second in 0..<10 {
      let line = "_:e" +
        first.to_string() +
        " <http:/example.com/p> _:e" +
        second.to_string() +
        " .\n"
      builder.write_string(line)
    }
  }
  match canon_string(builder.to_string()) {
    Ok(_) => fail("poison clique must not canonicalize")
    Err(JsonLdError::Unsupported(_)) => ()
    Err(_) => fail("wrong error family (expected Unsupported)")
  }
}
