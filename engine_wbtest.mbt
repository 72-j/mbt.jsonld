// ===== 役C3 移防⑦（engine 62 行）：expand_context 面 / 顶层展开驱动 /
// 套件助手直调 / flatten 形态族 / compact 入口面。死账/挂账见 todo 批账。=====

///|
fn eng7_options() -> JsonLdOptions {
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
test "e7: expandContext faces (59/72/74)" {
  // 非对象外部 context（59 内层 None）→ 无 @context 成员同径（74）→ 初始兜底
  let o1 = { ..eng7_options(), expand_context: Some(String("junk")), }
  assert_true(expand_document("{\"a\":1}", o1) is Ok(_))
  // 外部 context 处理错（72）——@base 非串
  let o2 = {
    ..eng7_options(),
    expand_context: Some(
      JsonValue::Object([
        ("@context", JsonValue::Object([("@base", JsonValue::Number(5))])),
      ]),
    ),
  }
  match expand_document("{\"a\":1}", o2) {
    Err(_) => ()
    Ok(_) => fail("72: expected expandContext processing error")
  }
}

///|
test "e7: top-level value-null dropped (119)" {
  // 顶层值对象 null 产物 → Ok(None) 驱动臂丢弃
  assert_true(expand_document("{\"@value\":null}", eng7_options()) is Ok(_))
}

///|
test "e7: suite helper direct calls (370/435/440/484)" {
  // 对象键序规范形（370 区——json_canonical）
  match
    json_canonical(
      JsonValue::Object([
        ("b", JsonValue::Number(1)),
        ("a", JsonValue::Number(2)),
      ]),
    ) {
    JsonValue::Object(pairs) => assert_eq(pairs[0].0, "a")
    _ => fail("expected canonical object")
  }
  // 全序比较：bool 对臂（435）+ 数组前缀臂（440）
  assert_eq(
    json_total_compare(JsonValue::Bool(true), JsonValue::Bool(false)),
    1,
  )
  assert_eq(
    json_total_compare(JsonValue::Bool(false), JsonValue::Bool(true)),
    -1,
  )
  assert_eq(
    json_total_compare(
      JsonValue::Array([JsonValue::Number(1)]),
      JsonValue::Array([JsonValue::Number(1), JsonValue::Number(2)]),
    ),
    -1,
  )
  // 同构快路径（484——规范词形相等即真）
  assert_true(isomorphic_for_suite(JsonValue::Number(1), JsonValue::Number(1)))
  assert_true(!isomorphic_for_suite(JsonValue::Number(1), JsonValue::Number(2)))
}

///|
test "e7: isomorphic bnode graph faces (525/563/606/608)" {
  // 同构文档：@graph 数组序差 + bnode 标签差（双射重贴）
  let ours = match
    parse_json(
      "{\"@graph\":[{\"@id\":\"_:x\",\"http://p/\":[{\"@value\":1}]},{\"@id\":\"_:y\",\"http://q/\":[{\"@value\":2}]}]}",
    ) {
    Ok(v) => v
    Err(_) => fail("parse failed")
  }
  let expected = match
    parse_json(
      "{\"@graph\":[{\"@id\":\"_:y\",\"http://q/\":[{\"@value\":2}]},{\"@id\":\"_:x\",\"http://p/\":[{\"@value\":1}]}]}",
    ) {
    Ok(v) => v
    Err(_) => fail("parse failed")
  }
  assert_true(isomorphic_for_suite(ours, expected))
  assert_true(!isomorphic_for_suite(ours, JsonValue::Number(1)))
}

///|
test "e7: flatten same-id merge and reverse injection (1046/1147/1170-1191)" {
  // 同 id 双节点属性并账（1046 既有槽追加臂）
  match
    flatten_document(
      "[{\"@id\":\"http://x/\",\"http://a/\":\"1\"},{\"@id\":\"http://x/\",\"http://b/\":\"2\"}]",
      eng7_options(),
    ) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("\"http://a/\""))
      assert_true(text.contains("\"http://b/\""))
    }
    Err(_) => fail("expected same-id flatten merge")
  }
  // 反向注入（1147 目标定位 + 1170-1191 并入/去重臂——#t0037 族）：
  // 双子引用同一父 → 第二次注入走同谓词并入/去重臂
  match
    flatten_document(
      "{\"@context\":{\"child\":{\"@reverse\":\"http://a/parent\"},\"child2\":{\"@reverse\":\"http://a/parent\"}},\"@id\":\"http://a/child1\",\"child\":{\"@id\":\"http://a/parent\"},\"child2\":{\"@id\":\"http://a/parent\"}}",
      eng7_options(),
    ) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("http://a/child1"))
      assert_true(text.contains("http://a/parent"))
    }
    Err(_) => fail("expected reverse injection flatten")
  }
}

///|
test "e7: flatten array/list/graph faces (851/874/885/1105/1119/1121)" {
  // 属性数组逐项走查（851）
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":[{\"@value\":\"1\"},{\"@value\":\"2\"}]}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("\"1\""))
    Err(_) => fail("expected array flatten")
  }
  // @list 值位（874 List 臂）
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":{\"@list\":[{\"@value\":\"v\"}]}}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("@list"))
    Err(_) => fail("expected list flatten")
  }
  // 图载体成员（1105/1119/1121——@graph 节点入图作用域账）
  match
    flatten_document(
      "{\"@graph\":[{\"@id\":\"http://g1/\",\"http://a/\":\"v\"}]}",
      eng7_options(),
    ) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("http://g1/"))
    }
    Err(_) => fail("expected graph flatten")
  }
}

///|
test "e7: flatten with context faces (1243/1247/1259/1262/1273/1306)" {
  // context 文档非对象（1262 原样兜底）→ 压缩合成面
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      context="\"junk\"",
      eng7_options(),
    ) {
    // junk 串 context = 远程引用尝试（1262 形——错误词形经实测校准）
    Err(InvalidContext(m)) =>
      assert_true(m.contains("loading remote context failed"))
    _ => fail("1262: expected remote-context error for string context")
  }
  // 空文档展平（1306 空对象臂）
  match flatten_document("{}", eng7_options()) {
    Ok(_) => ()
    Err(_) => fail("1306: expected empty flatten")
  }
}

///|
test "e7: compact document context faces (1259/1262/1391/1415/1432)" {
  // context 文档非对象（1262 同族——compact 入口解包面）
  match
    compact_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      "\"junk\"",
      eng7_options(),
    ) {
    // 同族：串 context = 远程引用尝试（1262 形）
    Err(InvalidContext(m)) =>
      assert_true(m.contains("loading remote context failed"))
    _ => fail("compact: expected remote-context error for string context")
  }
  // context 文档无 @context 成员 = 裸形直用（1259/1391——合法 term map）
  match
    compact_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      "{\"v\":\"http://a/v\"}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("\"v\""))
    Err(_) => fail("compact: expected bare term map context to work")
  }
}

///|
test "e7: compact tail faces (1415-1458)" {
  // compactArrays=false 单节点 → @graph 包裹（1415/1418——#t0091）
  let nofold = { ..eng7_options(), compact_arrays: false, }
  match
    compact_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}", "{\"v\":\"http://a/v\"}", nofold,
    ) {
    Ok(value) => assert_true(render_json(value).contains("@graph"))
    Err(_) => fail("1415: expected single-node graph wrap")
  }
  // 多节点顶层 → @graph 数组包裹（1432/1434/1443）
  match
    compact_document(
      "[{\"@id\":\"http://x/\",\"http://a/\":\"1\"},{\"@id\":\"http://y/\",\"http://a/\":\"2\"}]",
      "{\"a\":\"http://a/\"}",
      eng7_options(),
    ) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("\"@graph\""))
      assert_true(text.contains("http://x/"))
    }
    Err(_) => fail("1432: expected multi-node graph wrap")
  }
  // null context → context 空不发射（1458）
  match
    compact_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      "null",
      eng7_options(),
    ) {
    Ok(value) => assert_true(!render_json(value).contains("@context"))
    Err(_) => fail("1458: expected null context to emit no @context")
  }
}
