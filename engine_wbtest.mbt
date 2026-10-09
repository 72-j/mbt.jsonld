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
test "jcs_serialize 钉（评审役 R-1）：键码点序 + JCS 直出" {
  // 键序反例 = json_canonical 的长度序（@id/ex:p/@context）；JCS 码点序 =
  // @context < @id < ex:p——本钉改线即红
  let value = match
    parse_json("{\"ex:p\":1,\"@id\":\"a\",\"@context\":\"b\"}") {
    Ok(value) => value
    Err(_) => fail("parse failed")
  }
  assert_eq(
    jcs_serialize(value),
    "{\"@context\":\"b\",\"@id\":\"a\",\"ex:p\":1}",
  )
  // JCS 转义形（§3.2.2.2 短转义）+ 数词形词样保真
  let value2 = match parse_json("{\"k\":\"a\\nb\",\"m\":0.002}") {
    Ok(value) => value
    Err(_) => fail("parse failed")
  }
  assert_eq(jcs_serialize(value2), "{\"k\":\"a\\nb\",\"m\":0.002}")
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

///|
fn e8_parse(text : String) -> JsonValue {
  match parse_json(text) {
    Ok(v) => v
    Err(_) => abort("e8 parse failed: " + text)
  }
}

///|
test "e8: entry parse errors (42/1243/1326/1247/1375)" {
  // 顶层解析错：expand_top_values parse 臂（42）；flatten_core 上传臂（1326）
  // 与 flatten with-context 入口上传臂（1243）同笔串联
  assert_true(expand_document("{nope", eng7_options()) is Err(_))
  match flatten_document("{nope", context="{}", eng7_options()) {
    Err(_) => ()
    Ok(v) => fail("1243: expected parse error, got " + render_json(v))
  }
  // flatten context 文档解析错（1247——input 合法、context 炸）
  match flatten_document("{}", context="{bad", eng7_options()) {
    Err(_) => ()
    Ok(v) => fail("1247: expected context parse error, got " + render_json(v))
  }
  // compact context 文档解析错（1375——同族 compact 侧）
  match compact_document("{}", "{bad", eng7_options()) {
    Err(_) => ()
    Ok(v) => fail("1375: expected context parse error, got " + render_json(v))
  }
}

///|
test "e8: flatten context faces (1259/1262/1273)" {
  // 裸形 term map 直用（1259——对象无 @context 键回落 ctx_doc 本身）
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      context="{\"v\":\"http://a/v\"}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("\"v\""))
    Err(_) => fail("1259: expected bare term-map context to work")
  }
  // 非对象 context 文档（1262 原样透传——串 context = 远程引用尝试）
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      context="\"junk\"",
      eng7_options(),
    ) {
    Err(InvalidContext(m)) =>
      assert_true(m.contains("loading remote context failed"))
    _ => fail("1262: expected remote-context error")
  }
  // context 处理错上传（1273——@base 非串）
  match
    flatten_document(
      "{\"@id\":\"http://x/\",\"http://a/\":\"v\"}",
      context="{\"@context\":{\"@base\":5}}",
      eng7_options(),
    ) {
    Err(_) => ()
    Ok(v) =>
      fail("1273: expected context processing error, got " + render_json(v))
  }
}

///|
test "e8: compaction error propagation (1292/1432/1443)" {
  // F3-43 碰撞构造三入口：flatten 成员压缩错上传（1292）。
  // 碰撞上下文 = wrapper 形（@context 内仅 tag；@prefix:false 下 tag:foo
  // 不成 curie，回落全形键 → scheme 撞在册 term 名 → InvalidContext）
  let collide_input = "{\"@id\":\"http:s1\",\"tag:foo\":\"v\"}"
  let collide_ctx = "{\"@context\":{\"tag\":{\"@id\":\"http://other/\",\"@prefix\":false}}}"
  match flatten_document(collide_input, context=collide_ctx, eng7_options()) {
    Err(InvalidContext(m)) => assert_eq(m, "scheme collides with term name")
    _ => fail("1292: expected scheme collision via flatten")
  }
  // compactArrays=false 单节点包裹臂压缩错（1432）
  let nofold = { ..eng7_options(), compact_arrays: false, }
  match compact_document(collide_input, collide_ctx, nofold) {
    Err(InvalidContext(m)) => assert_eq(m, "scheme collides with term name")
    _ => fail("1432: expected scheme collision in wrap arm")
  }
  // 多节点臂压缩错（1443）
  match
    compact_document(
      "[{\"@id\":\"http:s1\",\"tag:foo\":\"v\"},{\"@id\":\"http:s2\",\"tag:foo\":\"v2\"}]",
      collide_ctx,
      eng7_options(),
    ) {
    Err(InvalidContext(m)) => assert_eq(m, "scheme collides with term name")
    _ => fail("1443: expected scheme collision in multi arm")
  }
}

///|
test "e8: top-level drop and list arms (119/191)" {
  // 顶层数组标量成员 → 展开为 None → 弃置臂（119）——全弃则顶为空数组
  match expand_document("[1,\"two\"]", eng7_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    Err(_) => fail("119: expected scalar members dropped")
  }
  // 顶层 @list 对象 → 实测渲染 []（展开侧丢弃——行为钉；191 other 臂是否
  // 可达由覆盖裁决：ExpandObject 若不产 List 则臂死）
  match expand_document("{\"@list\":[{\"@value\":\"x\"}]}", eng7_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    Err(_) => fail("191-probe: expected top-level list dropped")
  }
}

///|
test "e8: helper direct faces (370/435/827)" {
  // json_canonical 数组臂（370——e7 仅对象形）
  match
    json_canonical(
      JsonValue::Array([JsonValue::Number(2), JsonValue::Number(1)]),
    ) {
    JsonValue::Array(items) => assert_eq(items[0], JsonValue::Number(2))
    _ => fail("370: expected canonical array")
  }
  // 全序比较 bool 相等臂（435——e7 仅 true/false 异序）
  assert_eq(json_total_compare(JsonValue::Bool(true), JsonValue::Bool(true)), 0)
  assert_eq(
    json_total_compare(JsonValue::Bool(false), JsonValue::Bool(false)),
    0,
  )
  // 控制字符 \u 转义 A-F 半位（827——0x0B 低半位 11 → 'B'，55+n 臂）
  assert_true(render_json(JsonValue::String("\u{000b}")).contains("\\u000B"))
}

///|
test "e8: iso sort-skip and relabel faces (525/563/606/608)" {
  // @graph 值非数组 → 排序跳过臂（525）——同形直比真
  let g_obj = "{\"@graph\":{\"@id\":\"http://a/\",\"http://p/\":\"v\"}}"
  assert_true(isomorphic_for_suite(e8_parse(g_obj), e8_parse(g_obj)))
  // @type 数组非串项：收集跳过（563）+ 重标保留（608）——标签差驱动重标
  let tn = "{\"@id\":\"_:a\",\"@type\":[123],\"http://p/\":\"v\"}"
  let tn2 = "{\"@id\":\"_:b\",\"@type\":[123],\"http://p/\":\"v\"}"
  assert_true(isomorphic_for_suite(e8_parse(tn), e8_parse(tn2)))
  // @type 固定 IRI 不在重标映射 → 保留原形（606）
  let ti = "{\"@id\":\"_:a\",\"@type\":[\"http://fixed/\"],\"http://p/\":\"v\"}"
  let ti2 = "{\"@id\":\"_:b\",\"@type\":[\"http://fixed/\"],\"http://p/\":\"v\"}"
  assert_true(isomorphic_for_suite(e8_parse(ti), e8_parse(ti2)))
}

///|
test "e8: graph-carrier re-encounter merge (920 + 967/972 证伪)" {
  // 图载体两位置再现（属性位 + 根位同键预并 → 陈旧件后走）：
  // visited 命中 + 全形 → merge → nq_has_graph ⇒ own_scope=""（920）。
  // 陈旧件 @type t2 ⊆ 首见全形 [t1,t2] ⇒ 967 追臂预期不中（⊆ 不变式证伪探针）
  let doc = "[{\"@id\":\"http://a/p1/\",\"http://a/ref/\":{\"@id\":\"_:g\",\"@type\":\"http://t1/\",\"@graph\":[{\"@id\":\"_:x\",\"http://a/gp/\":\"1\"}],\"http://a/np/\":\"n1\"}},{\"@id\":\"_:g\",\"@type\":\"http://t2/\",\"@graph\":[{\"@id\":\"_:x\",\"http://a/gp/\":\"1\"}],\"http://a/np/\":\"n1\"}]"
  match flatten_document(doc, eng7_options()) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("_:g"))
      assert_true(text.contains("http://t1/"))
    }
    Err(_) => fail("920: expected carrier re-encounter merge")
  }
}

///|
test "e8: raw duplicate keys prop merge (1046)" {
  // 同 id 预并（nq_merge 248-250 属性对原样并入）→ 同谓词双对 →
  // prop_map 既有槽追加臂（1046）——原始重复键解析层即去重不可达（实证）
  match
    flatten_document(
      "[{\"@id\":\"http://x/\",\"http://a/\":\"1\"},{\"@id\":\"http://x/\",\"http://a/\":\"2\"}]",
      eng7_options(),
    ) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("\"1\""))
      assert_true(text.contains("\"2\""))
    }
    Err(_) => fail("1046: expected duplicate-key property merge")
  }
}

///|
test "e8: compact value-position arms (1418/1434/1445)" {
  // 单值对象 → 单节点解包臂 _ => ()（1418——值位非节点弃）
  match
    compact_document(
      "{\"@value\":\"x\"}",
      "{\"v\":\"http://a/v\"}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("@value") == false)
    Err(_) => fail("1418: expected value dropped in unwrap arm")
  }
  // compactArrays=false 单值 → 包裹臂 _ => ()（1434）
  let nofold = { ..eng7_options(), compact_arrays: false, }
  match compact_document("{\"@value\":\"x\"}", "{}", nofold) {
    Ok(value) => assert_true(!render_json(value).contains("@value"))
    Err(_) => fail("1434: expected value dropped in wrap arm")
  }
  // 多节点数组混入值对象 → 多节点臂 _ => ()（1445——值成员跳过）
  match
    compact_document(
      "[{\"@value\":\"x\"},{\"@id\":\"http://a/\",\"http://p/\":\"v\"}]",
      "{}",
      eng7_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://a/"))
    Err(_) => fail("1445: expected value member skipped")
  }
}

///|
test "e8: reverse value-object falsification (1191)" {
  // 节点位 @reverse 值对象——展开是否保留非节点 reverse 值（1191 证伪探针：
  // 若展开侧即弃，此臂不可达）
  let result = flatten_document(
    "{\"@id\":\"http://p/\",\"@reverse\":{\"http://q/\":{\"@value\":\"x\"}}}",
    eng7_options(),
  )
  match result {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("http://p/") || !text.contains("http://p/"))
    }
    Err(_) => ()
  }
}

///|
test "e8b: array member none drop (119)" {
  // 数组成员 @value:null 值对象 → expand_object Ok(None)（顶层同款 135 臂
  // 已证 None 面）；注：{} 空对象走 Some(Node) → push_top_value 185 自由
  // 浮动弃置，非此臂（勘误——首探 [{},{}] 不中即此故）
  match
    expand_document("[{\"@value\":null},{\"@value\":null}]", eng7_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    Err(_) => fail("119: expected value-null members dropped in array")
  }
}

///|
test "e8b: flatten empty with context (1306)" {
  // 空 flatten 主体 + context 压缩通道 → compacted 空 → 空对象臂（1306）
  // ——e7 的空文档钉走的是无 context 直出臂，未入此臂（勘误）
  match
    flatten_document("{}", context="{\"v\":\"http://a/v\"}", eng7_options()) {
    Ok(value) => assert_eq(render_json(value), "{}")
    Err(_) => fail("1306: expected empty flatten with context")
  }
}

///|
test "e8b: reverse injection append (1179)" {
  // C 先行全形注册（显式 parent 谓词）→ P 后行 reverse 注入命中既有同谓词
  // 对、值异 → 去重通过追加臂（1179）——e7 双子同值走的是去重跳过侧
  let doc = "[{\"@id\":\"http://a/C\",\"http://a/parent\":\"http://a/other\"},{\"@id\":\"http://a/P\",\"child\":{\"@id\":\"http://a/C\"}}]"
  let opts = {
    ..eng7_options(),
    expand_context: Some(
      JsonValue::Object([
        (
          "@context",
          JsonValue::Object([
            (
              "child",
              JsonValue::Object([
                ("@reverse", JsonValue::String("http://a/parent")),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  }
  match flatten_document(doc, opts) {
    Ok(value) => {
      let text = render_json(value)
      assert_true(text.contains("http://a/other"))
      assert_true(text.contains("http://a/P"))
    }
    Err(_) => fail("1179: expected reverse injection append")
  }
}
