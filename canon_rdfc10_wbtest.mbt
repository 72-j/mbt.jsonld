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

// ===== 役C3 移防④（canon_rdfc10 8 行）：串比较长短臂 + IRI 禁字符转义 +
// 谓词位容错 + 解析错上抛；384/493/567 定谳死账不探（见 todo 批账）=====

///|
test "c14n mf4: compare prefix-length arms (192/194)" {
  assert_eq(c14n_compare("abc", "abcd"), -1)
  assert_eq(c14n_compare("abcd", "abc"), 1)
  assert_eq(c14n_compare("ab", "ab"), 0)
}

///|
test "c14n mf4: iri forbidden char escape + parse error + literal predicate (285/411/679)" {
  // IRI 内 '^'（0x5E，禁字符表）→ UCHAR 大写转义
  match
    rdfc10_canonicalize_with_hash("<http://s/> <http://p^x/> \"v\" .", Sha256) {
    Ok((canonical, _)) => {
      // 反斜杠字面量过 heredoc/python 层易被吃（移防①② 坑族续）——
      // 断转义词形 "u005E" 在场 + 全串无裸 '^'，组合钉死 UCHAR 转义
      assert_true(canonical.contains("u005E"))
      assert_true(!canonical.contains("^"))
    }
    Err(_) => fail("expected canonicalization to succeed")
  }
  // 文法外容错形：谓词位字面量——411 `_` 臂在 hash_related_blank_node，
  // 须「首度哈希同形的碰撞组 + 组内 quad 携 bnode 分量」才进 n-degree 径
  //（_:a/_:b 同形互相碰撞，_:c 为共同关联 bnode；单 bnode 走简单径不达）
  match
    rdfc10_canonicalize_with_hash(
      "_:a \"lit\" _:c .\n_:b \"lit\" _:c .",
      Sha256,
    ) {
    Ok((canonical, _)) => assert_true(canonical.length() > 0)
    Err(_) => fail("expected literal-predicate quad to canonicalize")
  }
  // 非 N-Quads 输入 → Syntax 上抛（679）
  match rdfc10_canonicalize_with_hash("not nquads at all", Sha256) {
    Err(Syntax(_)) => ()
    _ => fail("expected Syntax error for garbage input")
  }
}
