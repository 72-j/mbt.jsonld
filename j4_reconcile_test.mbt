///|
/// J4 对账三件套（spec §5.1——骨架 vs 手写，非模型 vs 引擎）：
///   件 1 接口一致 = interface_gate_test 既有门（表 handler ↔ mock 双向）。
///   件 2 步骤覆盖 = 本文件：steps 7 行 + keyword_dispatch 14 行 + iri_rules
///        7 行，逐行**行为探针**证明手写链兑现声明（缺行/多行/错向皆红）。
///   件 3 值级对拍 = 同一探针的 expected 即精确展开形（值级，非仅行为）。
/// **J4 对账产出（骨架 vs 手写分叉账）**：keyword_dispatch 的 9 行 handler_hook
/// （set_language/set_direction/expand_list/expand_set/expand_graph/
/// expand_reverse/expand_nest/expand_included/set_index）指向 **pending 桩**——
/// 真落点 = expand_object 内联臂（J2 各批实装处）。表行 = 声明的语义归属；
/// 本文件 fixture 逐行证明内联臂兑现声明的 action/args。桩本身由
/// expand_standard_wbtest 的 Unsupported 常驻活账管辖。

///|
/// 值级对拍探针：doc（含 @context）→ 展开形 canonical → 与 expected 串比
fn j4_expand_eq(doc : String, expected : String) -> Bool {
  let options : @jsonld.JsonLdOptions = {
    base: None,
    expand_context: None,
    processing_mode: @jsonld.ProcessingMode::JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
  }
  let result = @jsonld.expand_document(doc, options)
  let actual = match result {
    Ok(value) => @jsonld.canonical_for_suite(value)
    Err(e) => {
      println("J4 expand-err: \{doc}")
      let _ = e
      return false
    }
  }
  let expected_value = match @jsonld.parse_json(expected) {
    Ok(v) => @jsonld.canonical_for_suite(v)
    Err(_) => {
      println("J4 expected-unparseable: \{expected}")
      return false
    }
  }
  let ok = diag_json_str(actual) == diag_json_str(expected_value)
  if !ok {
    println(
      "J4 MISMATCH doc=\{doc}\n  actual  =\{diag_json_str(actual)}\n  expected=\{expected}",
    )
  }
  ok
}

///|
/// 值级对拍全表（件 2 + 件 3 合一：每行 = 声明路由的行为证明 + 精确展开值）
async test "J4: keyword_dispatch 14 routes + steps + iri_rules value-level" {
  // (路由键, doc, expected-expanded)
  let fixtures : Array[(String, String, String)] = [
    // ---------- keyword_dispatch 13 键 + _term 缺省臂 ----------
    (
      "@id", "{\"@context\":{\"id\":\"@id\",\"@base\":\"http://ex/\",\"m\":\"http://ex/m\"},\"id\":\"z\",\"m\":\"v\"}",
      "[{\"@id\":\"http://ex/z\",\"http://ex/m\":[{\"@value\":\"v\"}]}]",
    ),
    (
      "@type", "{\"@context\":{\"type\":\"@type\"},\"type\":\"T\"}", "[{\"@type\":[\"T\"]}]",
    ),
    (
      "@value", "{\"@context\":{\"a\":\"http://ex/a\",\"v\":\"@value\"},\"a\":{\"v\":\"x\"}}",
      "[{\"http://ex/a\":[{\"@value\":\"x\"}]}]",
    ),
    (
      "@language", "{\"@context\":{\"a\":\"http://ex/a\",\"v\":\"@value\",\"l\":\"@language\"},\"a\":{\"v\":\"x\",\"l\":\"en\"}}",
      "[{\"http://ex/a\":[{\"@value\":\"x\",\"@language\":\"en\"}]}]",
    ),
    (
      "@direction", "{\"@context\":{\"a\":\"http://ex/a\",\"v\":\"@value\",\"d\":\"@direction\"},\"a\":{\"v\":\"x\",\"d\":\"rtl\"}}",
      "[{\"http://ex/a\":[{\"@value\":\"x\",\"@direction\":\"rtl\"}]}]",
    ),
    (
      "@list", "{\"@context\":{\"L\":{\"@id\":\"http://ex/L\",\"@container\":\"@list\"}},\"L\":[\"v\"]}",
      "[{\"http://ex/L\":[{\"@list\":[{\"@value\":\"v\"}]}]}]",
    ),
    (
      "@set", "{\"@context\":{\"S\":{\"@id\":\"http://ex/S\",\"@container\":\"@set\"}},\"S\":[\"v\"]}",
      "[{\"http://ex/S\":[{\"@value\":\"v\"}]}]",
    ),
    (
      "@graph", "{\"@graph\":[{\"@id\":\"http://ex/g\",\"http://ex/p\":[{\"@value\":\"v\"}]}]}",
      "[{\"@id\":\"http://ex/g\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
    // @reverse 语义 = t0042 oracle 保形（@reverse 映射保留——reverse 批账），
    // 非 REC 反转形（J4 对账发现：路由 result="property" 的词形即此）
    (
      "@reverse", "{\"@context\":{\"rev\":{\"@reverse\":\"http://ex/rev\",\"@type\":\"@id\"}},\"@id\":\"http://ex/p\",\"rev\":\"http://ex/node\"}",
      "[{\"@id\":\"http://ex/p\",\"@reverse\":{\"http://ex/rev\":[{\"@id\":\"http://ex/node\"}]}}]",
    ),
    (
      "@nest", "{\"@context\":{\"nest\":\"@nest\",\"a\":\"http://ex/a\"},\"nest\":{\"a\":\"v\"}}",
      "[{\"http://ex/a\":[{\"@value\":\"v\"}]}]",
    ),
    // @included 语义 = in01 oracle 保形（键渲染 + 仅 included 的根节点保留）
    (
      "@included", "{\"@context\":{\"inc\":\"@included\"},\"inc\":{\"@id\":\"http://ex/x\"}}",
      "[{\"@included\":[{\"@id\":\"http://ex/x\"}]}]",
    ),
    (
      "@index", "{\"@context\":{\"C\":{\"@id\":\"http://ex/C\",\"@container\":\"@index\"}},\"C\":{\"A\":\"v\"}}",
      "[{\"http://ex/C\":[{\"@value\":\"v\",\"@index\":\"A\"}]}]",
    ),
    (
      "@context", "{\"@context\":{\"a\":\"http://ex/a\"},\"a\":\"v\"}", "[{\"http://ex/a\":[{\"@value\":\"v\"}]}]",
    ),
    // _term 缺省臂：非关键字键 = term 展开（compact 键形——相对键无词表时弃，
    // t0115 族 oracle）
    (
      "_term", "{\"@context\":{\"ex\":\"http://ex/\"},\"ex:thing\":\"v\"}", "[{\"http://ex/thing\":[{\"@value\":\"v\"}]}]",
    ),
  ]
  // 骨架路由行 ↔ 手写行为双钉：路由行存在 + fixture 值级兑现
  for fixture in fixtures {
    let (keyword, doc, expected) = fixture
    let route = @jsonld.jsonld_keyword_route(keyword)
    if route is None {
      fail("J4: 路由行缺失 \{keyword}")
    }
    if !j4_expand_eq(doc, expected) {
      fail("J4 值级对拍红：\{keyword}")
    }
  }
  // 骨架路由全表行数钉（14 = 13 键 + _term）
  assert_eq(@jsonld.jsonld_keyword_routes().length(), 14)
}

///|
/// steps 7 行覆盖：entry 形态三分（dispatch 行）+ 直通行（无 hook）+ 终点
async test "J4: steps coverage (entry dispatch + passthrough rows)" {
  // entry.dispatch 三形态（scalar / array / object）
  assert_true(j4_expand_eq("\"x\"", "[]")) // scalar → 值对象顶层即弃
  assert_true(
    j4_expand_eq(
      "[{\"@id\":\"http://ex/a\",\"http://ex/p\":[{\"@value\":\"v\"}]}]", "[{\"@id\":\"http://ex/a\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  ) // array 逐元素
  assert_true(
    j4_expand_eq(
      "{\"@id\":\"http://ex/a\",\"http://ex/p\":[{\"@value\":\"v\"}]}", "[{\"@id\":\"http://ex/a\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  ) // object 单节点
  // 步骤 id 全集钉（7 行账面）
  let ids = [
    @jsonld.JsonLdStep::ExpansionEntry.id(),
    @jsonld.JsonLdStep::ExpansionExpandValue.id(),
    @jsonld.JsonLdStep::ExpansionExpandArray.id(),
    @jsonld.JsonLdStep::ExpansionExpandObject.id(),
    @jsonld.JsonLdStep::ExpansionPostprocess.id(),
    @jsonld.JsonLdStep::TorfEntry.id(),
    @jsonld.JsonLdStep::TorfEmit.id(),
  ]
  assert_eq(ids.length(), 7)
  assert_true(ids.contains("expansion.entry"))
  assert_true(ids.contains("torf.emit"))
}

///|
/// iri_rules 7 行覆盖：逐行行为探针（expand_iri 求值序 = 表序）
async test "J4: iri_rules coverage (7 rules in declared order)" {
  // 1 keyword：starts_with_at → 原样（未知关键字键忽略）
  assert_true(j4_expand_eq("{\"@foo\":\"v\"}", "[]"))
  // 2 term：term_defined → 查表
  assert_true(
    j4_expand_eq(
      "{\"@context\":{\"a\":\"http://ex/a\"},\"a\":\"v\"}", "[{\"http://ex/a\":[{\"@value\":\"v\"}]}]",
    ),
  )
  // 3 bnode：is_bnode → 原样（骨架缺省实现行）
  assert_true(
    j4_expand_eq(
      "{\"@id\":\"_:b\",\"http://ex/p\":[{\"@value\":\"v\"}]}", "[{\"@id\":\"_:b\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  )
  // 4 compact：has_prefix → 展开
  assert_true(
    j4_expand_eq(
      "{\"@context\":{\"ex\":\"http://ex/\"},\"@id\":\"ex:x\",\"http://ex/p\":[{\"@value\":\"v\"}]}",
      "[{\"@id\":\"http://ex/x\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  )
  // 5 absolute：has_valid_scheme → 原样（骨架缺省实现行）
  assert_true(
    j4_expand_eq(
      "{\"@id\":\"http://ex/x\",\"http://ex/p\":[{\"@value\":\"v\"}]}", "[{\"@id\":\"http://ex/x\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  )
  // 6 vocab：vocab_base_set → 拼接
  assert_true(
    j4_expand_eq(
      "{\"@context\":{\"@vocab\":\"http://ex/v/\"},\"k\":\"v\"}", "[{\"http://ex/v/k\":[{\"@value\":\"v\"}]}]",
    ),
  )
  // 7 relative：base_set → base 合并
  assert_true(
    j4_expand_eq(
      "{\"@context\":{\"@base\":\"http://ex/b/\"},\"@id\":\"z\",\"http://ex/p\":[{\"@value\":\"v\"}]}",
      "[{\"@id\":\"http://ex/b/z\",\"http://ex/p\":[{\"@value\":\"v\"}]}]",
    ),
  )
}

///|
/// 骨架 vs 手写分叉账钉（J4 对账产出）：9 行 keyword hook 声明指向 pending 桩
/// （真落点 = expand_object 内联臂）——分叉在册，桩由 Unsupported 常驻活账管辖
async test "J4: skeleton-vs-handwritten divergence ledger" {
  let pending_hooks : Array[(String, String)] = [
    ("@language", "Expander::set_language"),
    ("@direction", "Expander::set_direction"),
    ("@list", "Expander::expand_list"),
    ("@set", "Expander::expand_set"),
    ("@graph", "Expander::expand_graph"),
    ("@reverse", "Expander::expand_reverse"),
    ("@nest", "Expander::expand_nest"),
    ("@included", "Expander::expand_included"),
    ("@index", "Expander::set_index"),
  ]
  for pair in pending_hooks {
    match @jsonld.jsonld_keyword_route(pair.0) {
      Some(route) =>
        assert_true(
          route.handler == Some(pair.1),
          msg="J4 分叉账：\{pair.0} 声明落点漂移",
        )
      None => fail("J4 分叉账：路由行缺失 \{pair.0}")
    }
  }
}

///|
/// torf 阶段值级件（torf.entry hook = node_to_quads；torf.emit = 出账直通行）
async test "J4: torf steps value-level (entry hook + emit passthrough)" {
  let options : @jsonld.JsonLdOptions = {
    base: None,
    expand_context: None,
    processing_mode: @jsonld.ProcessingMode::JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
  }
  let doc = "{\"@id\":\"http://ex/s\",\"http://ex/p\":[{\"@value\":\"v\"}]}"
  let quads = match @jsonld.to_rdf_document(doc, options) {
    Ok(qs) => qs
    Err(_) => fail("J4 torf: 管线报错")
  }
  assert_eq(quads.length(), 1)
  assert_eq(quads[0].subject, "<http://ex/s>")
  assert_eq(quads[0].predicate, "<http://ex/p>")
  assert_eq(quads[0].object, "\"v\"")
  assert_true(quads[0].graph is None)
}
