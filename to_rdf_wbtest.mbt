// ===== 役C3 移防⑤二轮（to_rdf 15 行）：数值典范直调 / langtag 直调 /
// @json 哨兵无 raw / 非法 datatype 存活面 / generalized bnode 反向谓词。
// trdf5 系为黑盒 _test 够不着私 fn——本文件为白盒直调面。=====

///|
fn tr9_options() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
}

///|
test "tr9: canonical number direct calls (520/563)" {
  // "1.5e3"：指数字段循环在 while i<len 守卫处退出（494 None 臂不可达
  // ——get_char 恒不越界，⑤ 定谳）→ 整形臂零添（520）→ "1500"
  match nq_canonical_number("1.5e3", false) {
    (form, false) => assert_eq(form, "1500")
    _ => fail("494/520: expected 1.5e3 -> 1500 integer form")
  }
  // "1.0e-1"：整形门不过（sig.length 2 > -shift 2 为假）→ double 形尾零
  // 削减（563）→ "1.0E-1"
  match nq_canonical_number("1.0e-1", false) {
    (form, true) => assert_eq(form, "1.0E-1")
    _ => fail("563: expected 1.0e-1 -> 1.0E-1 double form")
  }
  // 492 证伪注记：JSON 数字文法指数后恒数字或串尾（Lexer 保证）——
  // 非数字中断臂不可达；542 证伪注记：sig 前导零 505-508 先剥，
  // int_digits = sig+尾零 恒无前导零（all_zero 已 512 守）——前剥臂不可达
  //（563 = "1.0e-1" 双形削尾零，实测闭合）
}

///|
test "tr9: langtag direct (582)" {
  // 段长 >8 后遇 '-'（582——seg_len > 8 分支）
  assert_true(!nq_valid_langtag("toolongtag-x"))
  // 空段遇 '-'（582——seg_len == 0 分支）
  assert_true(!nq_valid_langtag("a--b"))
  // 对照：合法标签
  assert_true(nq_valid_langtag("en-US"))
}

///|
test "tr9: @json sentinel without raw (397)" {
  // 值对象 @type @json 但值为普通串（raw None）→ 词面弃（397 None 臂）
  match
    to_rdf_document(
      "{\"http://p/\":{\"@value\":\"plain\",\"@type\":\"@json\"}}",
      tr9_options(),
    ) {
    Ok(quads) => assert_true(quads.length() == 0)
    Err(_) => fail("397: expected @json string-value literal dropped")
  }
}

///|
test "tr9: illegal datatype char survival (413)" {
  // 值位 @type 含文法外字符「|」——展开门 is_valid_absolute_iri 只拒空白
  //（expand 1433），「|」存活到 to_rdf；nq_iri_chars_legal（to_rdf 91）拒
  // ⇒ 413 None 臂弃词面（ quad = 0）。空格形在展开期即拒（"invalid typed
  // value"）——两道门非同 gate 的实证
  match
    to_rdf_document(
      "{\"http://p/\":{\"@value\":\"5\",\"@type\":\"http://a/x|y\"}}",
      tr9_options(),
    ) {
    Ok(quads) => assert_eq(quads.length(), 0)
    Err(_) => fail("413: expected pipe-char datatype tolerated to to_rdf gate")
  }
}

///|
test "tr9: generalized bnode reverse predicate (898/901)" {
  let input = "{\"@id\":\"http://a/x/\",\"@reverse\":{\"_:p\":{\"@id\":\"http://a/y/\"}}}"
  // ⑤ 定谳（coverage-baseline 移防⑤）：bnode 谓词展开侧不可装机——
  // expand 1695 反向键须绝对 IRI（"_:p" scheme "_" 非法）⇒ 反向项整项
  // 拒，generalized 旗无关。行为钉 = 两档皆无 _:p 四元组（回归牙）
  let gen = { ..tr9_options(), produce_generalized_rdf: true, }
  match to_rdf_document(input, gen) {
    Ok(quads) => {
      let hit = quads.iter().any(fn(q) { q.predicate == "_:p" })
      assert_true(!hit)
    }
    Err(_) => fail("898: expected Ok (reverse entry dropped at expansion)")
  }
  match to_rdf_document(input, tr9_options()) {
    Ok(quads) => {
      let hit = quads.iter().any(fn(q) { q.predicate == "_:p" })
      assert_true(!hit)
    }
    Err(_) => fail("901: expected Ok (reverse entry dropped at expansion)")
  }
}
