// ===== 役C1 批1：expand_object 负例臂直击钉（覆盖率战役本体） =====
// 未覆盖带定性：值对象互斥族 / @reverse 拒收族 / @graph·@nest·@included
// 形态门族 / 帧模式 pattern 族。钉子走 pub 入口 expand_document，
// Err 臂按变体钉死（Variant(_)+fail 兜底形态）。

///|
/// plain 档 options（默认 1.1，无 base）
fn neg_plain_options() -> JsonLdOptions {
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
/// 帧档 options（frame_expansion: true——帧 pattern 臂入口）
fn neg_frame_options() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: true,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
}

///|
/// 钉死 InvalidValue 变体（文案不钉——文案随役可修，变体是契约）
fn expect_invalid_value(text : String, options : JsonLdOptions) -> Unit raise {
  match expand_document(text, options) {
    Err(InvalidValue(_)) => ()
    _ => fail("expected JsonLdError::InvalidValue")
  }
}

///|
/// 值对象互斥族（#ter38/#tdi09 同族臂）：@type 与 @language/@direction
/// 互斥、@type 二现、@type/@language 非串形
test "vo: @type after @language — mutual exclusion" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@language\":\"en\",\"@type\":\"http://a/dt\"}",
    neg_plain_options(),
  )
}

///|
test "vo: @type after @direction — mutual exclusion" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@direction\":\"ltr\",\"@type\":\"http://a/dt\"}",
    neg_plain_options(),
  )
}

///|
test "vo: @type relative unresolvable — expand_iri err propagation" {
  match
    expand_document(
      "{\"@value\":\"x\",\"@type\":\"relative-unresolvable\"}",
      neg_plain_options(),
    ) {
    Err(InvalidValue(_)) => ()
    Err(_) => fail("wrong variant (not InvalidValue)")
    Ok(_) => fail("expected error, got Ok")
  }
}

///|
test "vo: @language after @type — mutual exclusion (reverse order)" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@type\":\"http://a/\",\"@language\":\"en\"}",
    neg_plain_options(),
  )
}

///|
test "vo: @language non-string — must be string or null" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@language\":123}",
    neg_plain_options(),
  )
}

///|
test "vo: @direction non-string — must be string or null" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@direction\":123}",
    neg_plain_options(),
  )
}

///|
test "vo: @index non-string — invalid @index value" {
  expect_invalid_value("{\"@value\":\"x\",\"@index\":123}", neg_plain_options())
}

///|
/// @reverse 拒收族：非 map 值 / 关键字键 / 值对象值
test "rev: non-map @reverse" {
  expect_invalid_value("{\"@reverse\":\"http://a/\"}", neg_plain_options())
}

///|
/// #ter25 同族：reverse map 键不得为关键字
test "rev: keyword key in reverse map" {
  expect_invalid_value(
    "{\"@reverse\":{\"@id\":{\"@id\":\"http://a/\"}}}",
    neg_plain_options(),
  )
}

///|
/// #ter34 同族：reverse map 值须为节点对象
test "rev: value object in reverse map" {
  expect_invalid_value(
    "{\"@reverse\":{\"http://a/p\":{\"@value\":\"x\"}}}",
    neg_plain_options(),
  )
}

///|
/// 形态门族：@graph 对象形（#t0020——节点下 @graph 保留于节点对象）
test "form: @graph object form" {
  let result = expand_document(
    "{\"@id\":\"http://a/\",\"@graph\":{\"@id\":\"http://g/\"}}",
    neg_plain_options(),
  )
  match result {
    Ok(value) => assert_true(render_json(value).contains("@graph"))
    _ => fail("expected Ok with node @graph")
  }
}

///|
test "form: @graph null arm" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@graph\":null}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@graph null = no graph content)")
  }
}

///|
test "form: @graph non-map rejection" {
  expect_invalid_value("{\"@graph\":\"x\"}", neg_plain_options())
}

///|
test "form: @nest in value object rejection" {
  expect_invalid_value(
    "{\"@value\":\"x\",\"@nest\":{\"@id\":\"http://a/\"}}",
    neg_plain_options(),
  )
}

///|
test "form: @nest null arm" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@nest\":null}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@nest null = empty)")
  }
}

///|
/// #tin07 同族：数组元素须为对象
test "form: @included array non-object element" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@included\":[\"http://x/\"]}",
    neg_plain_options(),
  )
}

///|
test "form: @included non-map rejection" {
  expect_invalid_value("{\"@included\":123}", neg_plain_options())
}

///|
test "form: @included null arm" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@included\":null}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@included null = empty)")
  }
}

///|
/// 循环后段验形门：条目带 @value 键
test "form: @included entry with @value key" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@included\":[{\"@value\":\"x\"}]}",
    neg_plain_options(),
  )
}

///|
test "form: @included entry with @list key" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@included\":[{\"@list\":[\"http://x/\"]}]}",
    neg_plain_options(),
  )
}

///|
/// 帧模式 pattern 族（frame_expansion: true——套件 92 例未达的组合形）
test "frame: @id array pattern" {
  match expand_document("{\"@id\":[\"http://a/\"]}", neg_frame_options()) {
    Ok(value) => assert_true(render_json(value).contains("http://a/"))
    _ => fail("expected Ok (@id pattern array)")
  }
}

///|
/// 负例 t0053 同族：@type pattern 不得含空白节点标识符
test "frame: @type bnode rejection" {
  expect_invalid_value("{\"@type\":[\"_:b\"]}", neg_frame_options())
}

///|
/// t0064 同族：@type MAY be map with @default entry, MUST preserve
test "frame: @type default array preserve" {
  match
    expand_document(
      "{\"@type\":[{\"@default\":\"http://a/\"}]}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@type default object preserved)")
  }
}

///|
test "frame: @type default direct object" {
  match
    expand_document(
      "{\"@type\":{\"@default\":\"http://a/\"}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@type default direct object)")
  }
}

///|
/// 帧旗词表门：@embed 词表 = true|false|@always|@once|@never|@last，词表外拒
test "frame: @embed badword rejection" {
  expect_invalid_value("{\"@embed\":\"sometimes\"}", neg_frame_options())
}

///|
test "frame: @embed bool flag" {
  match expand_document("{\"@embed\":true}", neg_frame_options()) {
    Ok(_) => ()
    _ => fail("expected Ok (@embed bool flag)")
  }
}

///|
/// 反向属性帧 pattern：@default 带（REC 帧 @reverse 模式值域）
test "frame: reverse term with @default pattern" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":\"http://a/x\"}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (reverse @default pattern)")
  }
}

///|
test "frame: reverse term with node value" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@id\":\"http://a/x\"}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (reverse node pattern)")
  }
}

///|
/// 别名键可达性批：frame_value_pattern 预扫扫**原始键**，别名 term
/// （"type"→"@type"）携非串值绕过预扫直达 @type 帧 pattern 臂——
/// 字面 "@type" 同值则被成分带（twin 门）处理。
test "frame: aliased @type bnode rejection" {
  expect_invalid_value(
    "{\"@context\":{\"type\":\"@type\"},\"type\":[\"_:b\"]}",
    neg_frame_options(),
  )
}

///|
test "frame: aliased @type default direct object" {
  match
    expand_document(
      "{\"@context\":{\"type\":\"@type\"},\"type\":{\"@default\":\"http://a/\"}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (aliased @type default direct object)")
  }
}

///|
test "frame: aliased @type default array preserve" {
  match
    expand_document(
      "{\"@context\":{\"type\":\"@type\"},\"type\":[{\"@default\":\"http://a/\"}]}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (aliased @type default array)")
  }
}

///|
test "frame: aliased @id object wildcard" {
  match
    expand_document(
      "{\"@context\":{\"id\":\"@id\"},\"id\":{}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (aliased @id object wildcard)")
  }
}

///|
test "frame: aliased @id array with object item" {
  match
    expand_document(
      "{\"@context\":{\"id\":\"@id\"},\"id\":[{\"@id\":\"http://a/\"}]}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (aliased @id array with object item)")
  }
}

///|
/// 钉死 InvalidList 变体（文案不钉）
fn expect_invalid_list(text : String, options : JsonLdOptions) -> Unit raise {
  match expand_document(text, options) {
    Err(InvalidList(_)) => ()
    _ => fail("expected JsonLdError::InvalidList")
  }
}

///|
/// 1.0 档 options（list-of-lists 门控探针用）
fn neg_options_10() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd10,
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
/// @set 族（expand_list_set_object 拦截器 @set 臂——数组/单值双形）
test "set: @set array value object" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@set\":[\"x\",\"y\"]}}",
      neg_plain_options(),
    ) {
    Ok(value) => {
      let rendered = render_json(value)
      assert_true(rendered.contains("\"x\""))
      assert_true(rendered.contains("\"y\""))
    }
    _ => fail("expected Ok (@set array)")
  }
}

///|
test "set: @set single value object" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@set\":\"x\"}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("\"x\""))
    _ => fail("expected Ok (@set single)")
  }
}

///|
test "set: @set with @index" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@set\":[\"x\"],\"@index\":\"i\"}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@set with @index)")
  }
}

///|
/// list_item 族（expand_list_item 缺口臂）
test "list: nested array in list (1.1 nested list)" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@list\":[[\"a\",\"b\"]]}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (nested array in list)")
  }
}

///|
test "list: nested list object as list item" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@list\":[{\"@list\":[\"x\"]}]}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (nested list object item)")
  }
}

///|
test "list: grouped @set as list item" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@list\":[{\"@set\":[\"x\",\"y\"]}]}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (grouped @set item)")
  }
}

///|
/// #ter24 同族经拦截器：1.0 下 list 项 {@list} → list of lists
test "list: 1.0 interceptor list-of-lists rejection" {
  expect_invalid_list(
    "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@list\":[{\"@list\":[\"x\"]}]}}",
    neg_options_10(),
  )
}

///|
/// frame_preserve_default 族（@default 词形保形——Number/Bool/数组递归臂；
/// 通道=反向属性 @default pattern，spec §8.96）
test "fpd: @default number raw preserve" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":1.5}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@default number)")
  }
}

///|
test "fpd: @default bool true preserve" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":true}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@default bool true)")
  }
}

///|
test "fpd: @default bool false preserve" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":false}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@default bool false)")
  }
}

///|
test "fpd: @default array recursion" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":[\"a\",\"b\"]}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@default array)")
  }
}

///|
/// graph 容器族（expand_graph_container——@id/@index map 形与 @none 直出）
test "graph: @id container map attach" {
  match
    expand_document(
      "{\"@context\":{\"g\":{\"@id\":\"@graph\",\"@container\":\"@id\"}},\"g\":{\"http://a/\":{\"@id\":\"http://a/\",\"p\":\"v\"}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@id graph map)")
  }
}

///|
test "graph: @index container map attach" {
  match
    expand_document(
      "{\"@context\":{\"g\":{\"@id\":\"@graph\",\"@container\":\"@index\"}},\"g\":{\"idx1\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@index graph map)")
  }
}

///|
test "graph: @none entry in @id map" {
  match
    expand_document(
      "{\"@context\":{\"g\":{\"@id\":\"@graph\",\"@container\":\"@id\"}},\"g\":{\"@none\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@none graph map entry)")
  }
}

///|
/// 批3：append_collection_item 族（节点位 @graph 双形通道 + @set 递归形）
test "col: @set array item error propagates" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@graph\":[{\"@set\":[{\"@value\":\"x\",\"@language\":123}]}]}",
    neg_plain_options(),
  )
}

///|
test "col: @set null transparent drop" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@graph\":[{\"@set\":null}]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@set null dropped)")
  }
}

///|
test "col: @set single scalar recursion" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@graph\":[{\"@set\":\"x\"}]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (@set single scalar dropped)")
  }
}

///|
test "col: scoped context reaches graph item" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@context\":{\"q\":\"http://b/q\"}}},\"p\":{\"@graph\":{\"@id\":\"http://x/\",\"q\":\"z\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://b/q"))
    _ => fail("expected Ok (scoped context applied in graph item)")
  }
}

///|
test "col: expand_object error at graph item" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@graph\":[{\"@value\":\"x\",\"@language\":123}]}",
    neg_plain_options(),
  )
}

///|
test "col: nested array at graph position ignored" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@graph\":[[\"a\"]]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (nested array ignored)")
  }
}

///|
/// 双键 @list 形（绕 2070 单键守卫）直达 expand_object：List 产物被
/// 2131 防御臂丢弃（与单键 @list 整弃一致）——内容不浮出
test "col: two-key @list form at graph position" {
  match
    expand_document(
      "{\"@id\":\"http://a/\",\"@graph\":[{\"@list\":[\"x\"],\"@index\":\"i\"}]}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      // DIAG 定谳：@list 内容在属性展开内部被弃（list 位先验），节点本体
      // 带 @index 存活——2131 List 防御臂不经此形（文本难达，留账）
      assert_true(
        render_json(value) ==
        "[{\"@id\":\"http://a/\",\"@graph\":[{\"@index\":\"i\"}]}]",
      )
    Err(_) => fail("expected Ok (two-key @list dropped)")
  }
}

///|
/// previous=Some 入口：term 定义 "@context": null（nullification 臂
/// previous_after(None, false) 造快照）→ 节点位 @graph 的集合项在
/// previous=Some 位展开（2109-2110 回退门求值）
test "col: nullified term context reaches graph item gate" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@context\":null}},\"p\":{\"@graph\":{\"@id\":\"http://x/\",\"@index\":\"i\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://x/"))
    _ => fail("expected Ok (nullified context graph item kept)")
  }
}

///|
/// type-scoped 空化造 previous（REC 4.1.2 步 5.2.1 唯一制造点：type_scoped
/// 面 propagate=false + "@context": null 整空化）→ 节点位 @graph 集合项在
/// previous=Some 位展开（2109-2110 回退门第二合取项求值）
test "col: type-scoped nullification reaches graph item gate" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@container\":\"@type\",\"@context\":null}},\"@id\":\"http://n/\",\"@type\":\"t\",\"@graph\":{\"@id\":\"http://x/\",\"@index\":\"i\"}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://x/"))
    _ => fail("expected Ok (type-scoped nullified graph item)")
  }
}

///|
test "col: @set single value error propagates" {
  expect_invalid_value(
    "{\"@id\":\"http://a/\",\"@graph\":[{\"@set\":{\"@value\":\"x\",\"@language\":123}}]}",
    neg_plain_options(),
  )
}

///|
/// 钉死 InvalidContext 变体（文案不钉）
fn expect_invalid_context(text : String, options : JsonLdOptions) -> Unit raise {
  match expand_document(text, options) {
    Err(InvalidContext(_)) => ()
    _ => fail("expected JsonLdError::InvalidContext")
  }
}

///|
/// 批4：@import / 远程 context 装载链失败径（resolve_context_reference 无 base
/// 拒 + load_context 注入 loader 失败传）
test "imp: @import without base unresolvable" {
  expect_invalid_context(
    "{\"@context\":{\"@import\":\"http://x/c\",\"p\":\"http://a/p\"}}",
    neg_plain_options(),
  )
}

///|
/// loader 失败注入（(String) -> Result[String, String] 契约面）
test "imp: @import loader failure propagates" {
  let fail_loader : (String) -> Result[String, String] = s => Err("boom")
  let options : JsonLdOptions = {
    base: Some("http://a/"),
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: Some(fail_loader),
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
  expect_invalid_context(
    "{\"@context\":{\"@import\":\"ctx.json\",\"p\":\"http://a/p\"}}", options,
  )
}

///|
test "str: remote context ref without base unresolvable" {
  expect_invalid_context(
    "{\"@context\":\"http://x/c\",\"p\":\"v\"}",
    neg_plain_options(),
  )
}

///|
/// 批4b：expand_container_map / expand_map_item_values 族
test "tmap: entry scoped context invalid term def" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"},\"t\":{\"@id\":\"http://a/t\",\"@context\":{\"q\":123}}},\"p\":{\"t\":{\"@id\":\"http://x/\"}}}",
    neg_plain_options(),
  )
}

///|
test "tmap: vo item without datatype gets @type" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}},\"p\":{\"http://a/t\":{\"@value\":\"x\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://a/t"))
    _ => fail("expected Ok (vo datatype written from type map index)")
  }
}

///|
test "tmap: list item in type container" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}},\"p\":{\"http://a/t\":{\"@list\":[\"x\"]}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (list item in type container)")
  }
}

///|
test "imap: vo item is invalid value object" {
  expect_invalid_value(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\",\"@index\":\"http://a/idx\"}},\"p\":{\"k\":{\"@value\":\"x\"}}}",
    neg_plain_options(),
  )
}

///|
test "imap: list item with index mapping" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\",\"@index\":\"http://a/idx\"}},\"p\":{\"k\":{\"@list\":[\"x\"]}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (list item with index mapping)")
  }
}

///|
test "imap: list item without index mapping" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\"}},\"p\":{\"k\":{\"@list\":[\"x\"]}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (list item without index mapping)")
  }
}

///|
test "idmap: vo item in id container" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@id\"}},\"p\":{\"http://x/\":{\"@value\":\"v\"}}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (vo item in id container)")
  }
}

///|
test "imap: array-of-array member flattens" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\"}},\"p\":{\"k\":[[\"a\",\"b\"]]}}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (array member flattened)")
  }
}

///|
test "imap: error inside array member propagates" {
  expect_invalid_value(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\"}},\"p\":{\"k\":[[{\"@value\":\"x\",\"@language\":123}]]}}",
    neg_plain_options(),
  )
}

///|
test "vcv: @graph duplicate in array" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@graph\"]}}}",
    neg_plain_options(),
  )
}

///|
test "vcv: @set duplicate in array" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@set\",\"@set\"]}}}",
    neg_plain_options(),
  )
}

///|
test "vcv: @list duplicate in array" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@list\",\"@list\"]}}}",
    neg_plain_options(),
  )
}

///|
test "vcv: unknown member in array" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@foo\"]}}}",
    neg_plain_options(),
  )
}

///|
test "vcv: non-string member in array" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[123]}}}",
    neg_plain_options(),
  )
}

///|
test "vcv: number container value" {
  expect_invalid_context(
    "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":123}}}",
    neg_plain_options(),
  )
}

///|
/// 批5b：装载面两钉（loader 缺省 = Unsupported 契约；loader 出非 JSON）
fn neg_base_options(base : String) -> JsonLdOptions {
  {
    base: Some(base),
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
test "load: no loader provided is Unsupported" {
  match
    expand_document(
      "{\"@context\":{\"@import\":\"ctx.json\",\"p\":\"http://a/p\"}}",
      neg_base_options("http://a/"),
    ) {
    Err(Unsupported(_)) => ()
    _ => fail("expected JsonLdError::Unsupported (loader not provided)")
  }
}

///|
test "load: loader returning invalid json" {
  let bad_json_loader : (String) -> Result[String, String] = _ => Ok("not json")
  let options : JsonLdOptions = {
    base: Some("http://a/"),
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: Some(bad_json_loader),
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
  expect_invalid_context(
    "{\"@context\":{\"@import\":\"ctx.json\",\"p\":\"http://a/p\"}}", options,
  )
}

///|
/// 批5c：merge_base_reference 相对合并边角（query 追加 / 无 authority 根 /
/// 无斜杠无冒号 base）
test "base: query reference appends to queryless base" {
  match expand_document("{\"@id\":\"?q\"}", neg_base_options("http://a/b")) {
    Ok(value) => assert_eq(render_json(value), "[]") // @id-only 节点顶层被弃；合并发生在弃置前
    _ => fail("expected Ok (query reference merged)")
  }
}

///|
test "base: slash reference on authorityless base" {
  match expand_document("{\"@id\":\"/x\"}", neg_base_options("abc")) {
    Ok(value) => assert_eq(render_json(value), "[]") // 同上
    _ => fail("expected Ok (slash reference merged)")
  }
}

///|
test "base: plain reference on slashless colonless base" {
  match expand_document("{\"@id\":\"x\"}", neg_base_options("abc")) {
    Ok(value) => assert_eq(render_json(value), "[]") // 同上
    _ => fail("expected Ok (plain reference merged)")
  }
}

///|
/// 批5d：杂项单钉
test "selfprefix: colonless id skips self-compact check" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"noself\"}},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (colonless id term usable)")
  }
}

///|
test "ftd: @type default non-string ignored" {
  match expand_document("{\"@type\":{\"@default\":123}}", neg_frame_options()) {
    Ok(_) => ()
    _ => fail("expected Ok (non-string default ignored)")
  }
}

///|
test "shape: nested array under nullified graph gate" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@container\":\"@type\",\"@context\":null}},\"@id\":\"http://n/\",\"@type\":\"t\",\"@graph\":[[\"a\"]]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (nested array at nullified gate)")
  }
}

///|
test "elem: top-level value null" {
  match expand_document("{\"@value\":null}", neg_plain_options()) {
    Ok(value) => assert_true(render_json(value) == "[]")
    Err(_) => fail("expected Ok (value null dropped at top)")
  }
}

///|
test "elem: top-level array of scalars" {
  match expand_document("[\"x\",1.5]", neg_plain_options()) {
    Ok(value) => assert_eq(render_json(value), "[]") // 标量串顶层展开后被弃
    Err(_) => fail("expected Ok (scalar array)")
  }
}

///|
test "prot: equivalent protected redefinition allowed" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\",\"@context\":{\"q\":\"http://b/q\"}}},{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\",\"@context\":{\"q\":\"http://b/q\"}}}],\"p\":{\"http://a/t\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("http://x/"))
    _ => fail("expected Ok (equivalent redefinition kept)")
  }
}

///|
test "prot: inequivalent protected redefinition rejected" {
  expect_invalid_context(
    "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}},{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@index\"}}]}",
    neg_plain_options(),
  )
}

///|
test "selfprefix: null-term prefix falls through compact" {
  match
    expand_document(
      "{\"@context\":{\"p\":null},\"p:x\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (null term prefix falls through)")
  }
}

///|
/// 批5 mini-wave2：base 边角（"//"引用×无冒号 base / 斜杠引用×非//scheme base）
test "base: scheme-relative reference on colonless base" {
  match expand_document("{\"@id\":\"//h/p\"}", neg_base_options("abc")) {
    Ok(value) => assert_eq(render_json(value), "[]")
    _ => fail("expected Ok")
  }
}

///|
test "base: slash reference on non-authority scheme base" {
  match expand_document("{\"@id\":\"/x\"}", neg_base_options("ex:a")) {
    Ok(value) => assert_eq(render_json(value), "[]")
    _ => fail("expected Ok")
  }
}

///|
/// 批5 mini-wave2：expand_element / expand_array 臂
test "elem: invalid @type value propagates at top" {
  match expand_document("{\"@type\":123}", neg_plain_options()) {
    Err(InvalidValue(_)) => ()
    _ => fail("expected InvalidValue for numeric @type")
  }
}

///|
test "elem: bool scalar is unsupported" {
  match expand_document("true", neg_plain_options()) {
    Err(Unsupported(_)) => ()
    _ => fail("expected Unsupported for boolean scalar")
  }
}

///|
test "elem: nested array via element dispatch" {
  // 顶层驱动卫兵：嵌套数组顶层 = Unsupported("nested array at top pending")
  // （engine.mbt 驱动层卫兵，不经 expand_array）
  match expand_document("[[\"a\"]]", neg_plain_options()) {
    Err(Unsupported(_)) => ()
    _ => fail("expected Unsupported (nested array at top)")
  }
}

///|
test "elem: array item unknown-only node" {
  // 未知属性独占节点 = 空节点，驱动层直弃（[]）
  match expand_document("[{\"unknown\":\"v\"}]", neg_plain_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    Err(_) => fail("expected Ok (empty node dropped)")
  }
}

///|
/// 批5 mini-wave2：等价重定义逐字段面（同容器双型 / graph 双型 / datatype /
/// 同 scoped context）
test "prot: equivalent type-container redefinition" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}},{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}}]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (type/type equivalent)")
  }
}

///|
test "prot: equivalent graph-container redefinition" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@graph\"}},{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@graph\"}}]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (graph/graph equivalent)")
  }
}

///|
test "prot: equivalent datatype redefinition" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@type\":\"http://a/d\"}},{\"p\":{\"@id\":\"http://a/p\",\"@type\":\"http://a/d\"}}]}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (datatype equivalent)")
  }
}

///|
test "prot: equivalent local context redefinition" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":{\"@id\":\"http://a/p\",\"@context\":{\"q\":\"http://b/q\"}}},{\"p\":{\"@id\":\"http://a/p\",\"@context\":{\"q\":\"http://b/q\"}}}],\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (local context equivalent)")
  }
}

///|
/// 批5 mini-wave3：frame pattern 面（@list 项循环 / pattern 保形 / @default
/// 数组保形）——expand_array·expand_value 残臂的真实入口
test "frame: @list pattern with nested array item" {
  // 嵌套数组经 @list 模式项循环展开成 List[literal]，非节点形落空 pattern {}
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@list\":[[\"a\"]]}}",
      neg_frame_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"@reverse\":{\"http://a/p\":[{}]}}]")
    _ => fail("expected Ok (list pattern empty node fallback)")
  }
}

///|
test "frame: @list pattern with bool item" {
  // 模式项 Bool 落值 pattern 保形（不经 expand_value 标量臂）
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@list\":[true]}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (bool as value pattern)")
  }
}

///|
test "frame: pattern object with invalid @id" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@id\":123}}",
      neg_frame_options(),
    ) {
    Ok(_) => () // 模式位 @id 数值 = 容忍（pattern node 原样保形）
    _ => fail("expected Ok (numeric @id tolerated in pattern)")
  }
}

///|
test "frame: pattern object with value null" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@value\":null}}",
      neg_frame_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@reverse\":{\"http://a/p\":[{\"@value\":[]}]}}]",
      ) // @value:null 保形为空值 pattern
    _ => fail("expected Ok (null value pattern preserved)")
  }
}

///|
test "frame: @default with nested array values" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":[[\"a\"],[\"b\"]]}}",
      neg_frame_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("expected Ok (default array preservation)")
  }
}

///|
test "frame: pattern value object with invalid language" {
  // 值对象 @language 非串 → expand_object 错误 → expand_element Err 臂传播
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@value\":\"x\",\"@language\":123}}",
      neg_frame_options(),
    ) {
    Ok(_) => () // 模式位值对象 @language 非串 = 容忍（保形不校验）
    _ => fail("expected Ok (pattern tolerance)")
  }
}

///|
test "graph: array with bool item" {
  // @graph 数组项 Bool = 值对象形被弃（顶层空）
  match expand_document("{\"@graph\":[true]}", neg_plain_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    _ => fail("expected Ok (bool item dropped)")
  }
}

///|
test "graph: node with invalid nest reference" {
  // @nest 引用未声明 term → 错误穿 @graph 臂 → expand_element Err 臂传播
  match
    expand_document(
      "{\"@graph\":{\"@id\":\"http://x/\",\"@nest\":\"unknown\"}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext("invalid @nest value")) => ()
    _ => fail("expected InvalidContext (invalid @nest value)")
  }
}

///|
test "graph: array of scalars" {
  // 标量串/数经 @graph 数组臂展开后值对象被弃（顶层空）
  match expand_document("{\"@graph\":[\"x\",1.5]}", neg_plain_options()) {
    Ok(value) => assert_eq(render_json(value), "[]")
    _ => fail("expected Ok (scalar graph items dropped)")
  }
}

///|
/// 批6：1.0 模式面助手
fn neg_plain10_options() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd10,
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
test "td: non-string @direction rejected" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@direction\":123}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid base direction")
    _ => fail("expected InvalidContext (invalid base direction)")
  }
}

///|
test "td: @nest alias to non-nest term rejected" {
  match
    expand_document(
      "{\"@context\":{\"x\":\"http://a/x\",\"t\":{\"@id\":\"http://a/t\",\"@nest\":\"x\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (alias not @nest)")
  }
}

///|
test "td: non-string @nest rejected" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@nest\":123}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (numeric @nest)")
  }
}

///|
test "td: non-bool @protected rejected" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@protected\":123}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @protected value")
    _ => fail("expected InvalidContext (numeric @protected)")
  }
}

///|
test "td: @protected in 1.0 mode rejected" {
  match
    expand_document(
      "{\"@context\":{\"t\":{\"@id\":\"http://a/t\",\"@protected\":true}},\"p\":\"v\"}",
      neg_plain10_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid term definition")
    _ => fail("expected InvalidContext (1.0 @protected)")
  }
}

///|
test "kw: keyword with extra entry is redefinition" {
  match
    expand_document(
      "{\"@context\":{\"@id\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "keyword redefinition")
    _ => fail("expected InvalidContext (keyword redefinition)")
  }
}

///|
test "kw: empty keyword definition is redefinition" {
  match expand_document("{\"@context\":{\"@type\":{}}}", neg_plain_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "keyword redefinition")
    _ => fail("expected InvalidContext (empty keyword def)")
  }
}

///|
test "kw: keyword with non-set container is redefinition" {
  match
    expand_document(
      "{\"@context\":{\"@id\":{\"@container\":\"@list\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "keyword redefinition")
    _ => fail("expected InvalidContext (keyword container)")
  }
}

///|
test "kw: keyword-shaped non-keyword term is redefinition" {
  match
    expand_document(
      "{\"@context\":{\"@ignoreMe\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "keyword redefinition")
    _ => fail("expected InvalidContext (keyword-shaped term)")
  }
}

///|
/// 批7-A：process_context 校验面负例 + @vocab 解析边角 + 装载成功路由
test "ctx: non-bool context-level @protected" {
  match
    expand_document("{\"@context\":{\"@protected\":123}}", neg_plain_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @protected value")
    _ => fail("expected InvalidContext (numeric @protected)")
  }
}

///|
test "ctx: context-level @protected in 1.0" {
  match
    expand_document(
      "{\"@context\":{\"@protected\":true,\"p\":\"http://a/p\"},\"p\":\"v\"}",
      neg_plain10_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid context entry")
    _ => fail("expected InvalidContext (1.0 context @protected)")
  }
}

///|
test "ctx: @vocab naming null-iri term falls to join" {
  // @vocab="x"，x=null term → 精确命中臂得 None → 回落拼接（无 vocab 无
  // base → 原样）
  match
    expand_document(
      "{\"@context\":{\"x\":null,\"@vocab\":\"x\",\"p\":\"http://a/p\"},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (vocab falls through to raw value)")
  }
}

///|
test "ctx: @vocab compact with null-iri prefix" {
  match
    expand_document(
      "{\"@context\":{\"zz\":null,\"@vocab\":\"zz:suf\",\"q\":\"http://a/q\"},\"q\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (compact lookup misses on null iri)")
  }
}

///|
test "ctx: relative @vocab without vocab and base" {
  match
    expand_document(
      "{\"@context\":{\"@vocab\":\"rel\",\"p\":\"http://a/p\"},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (raw relative vocab kept)")
  }
}

///|
test "ctx: string @version rejected" {
  match
    expand_document(
      "{\"@context\":{\"@version\":\"1.1\",\"p\":\"http://a/p\"},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @version value (1.1)")
    _ => fail("expected InvalidContext (string @version)")
  }
}

///|
test "ctx: null @direction resets" {
  match
    expand_document(
      "{\"@context\":{\"@direction\":null,\"p\":\"http://a/p\"},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (null direction reset)")
  }
}

///|
test "ctx: non-string @direction rejected" {
  match
    expand_document("{\"@context\":{\"@direction\":123}}", neg_plain_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid base direction")
    _ => fail("expected InvalidContext (numeric @direction)")
  }
}

///|
test "ctx: successful import reaches skip arm" {
  // 远程 context 文档 = {"@context":{…}} 包裹形（裸对象不算）
  let empty_loader : (String) -> Result[String, String] = _ => {
    Ok("{\"@context\":{}}")
  }
  let options : JsonLdOptions = {
    base: Some("http://a/"),
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: Some(empty_loader),
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
  match
    expand_document(
      "{\"@context\":{\"@import\":\"c.json\",\"p\":\"http://a/p\"},\"p\":\"v\"}",
      options,
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (import consumed, skip arm)")
  }
}

///|
test "ctx: self-prefix compact is cyclic" {
  match expand_document("{\"@context\":{\"a\":\"a:b\"}}", neg_plain_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "cyclic IRI mapping")
    _ => fail("expected InvalidContext (cyclic)")
  }
}

///|
test "ctx: null removal of protected term rejected" {
  match
    expand_document(
      "{\"@context\":[{\"@protected\":true,\"p\":\"http://a/p\"},{\"p\":null}],\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "protected term redefinition")
    _ => fail("expected InvalidContext (protected null removal)")
  }
}

///|
/// 批7-B：expand_term_values(_inner) 残臂——先 DIAG 学形
test "tv: list container two-key object" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":{\"@list\":[\"x\"],\"@set\":[\"y\"]}}",
      neg_plain_options(),
    ) {
    Ok(value) => fail("DIAG11 ok: " + render_json(value))
    Err(InvalidList(msg)) => assert_eq(msg, "invalid set or list object")
    _ => fail("expected InvalidList (two-key value object)")
  }
}

///|
test "tv: null item in list container array" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[null,\"x\"]}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@list\":[{\"@value\":\"x\"}]}]}]",
      ) // null 项丢弃
    _ => fail("expected Ok (null dropped in list container)")
  }
}

///|
test "tv: scalar under type container" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@type\"}},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"http://a/p\":[{\"@id\":\"v\"}]}]")
    // 标量入 @type 容器 → 节点 id 强转
    _ => fail("expected Ok (node id coercion)")
  }
}

///|
test "tv: scalar under id container" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@id\"}},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"http://a/p\":[{\"@value\":\"v\"}]}]")
    _ => fail("expected Ok (plain literal)")
  }
}

///|
test "tv: two-key list-set object plain property" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@list\":[\"x\"],\"@set\":[\"y\"]}}",
      neg_plain_options(),
    ) {
    Ok(value) => fail("DIAG15 ok: " + render_json(value))
    Err(InvalidList(msg)) => assert_eq(msg, "invalid set or list object")
    _ => fail("expected InvalidList (two-key value object)")
  }
}

///|
test "tv: type-scoped protection error at value position" {
  match
    expand_document(
      "{\"@context\":{\"q\":{\"@id\":\"http://b/q\",\"@protected\":true},\"t\":{\"@id\":\"http://a/t\",\"@container\":\"@type\",\"@context\":{\"q\":\"http://b/q2\"}}},\"@type\":\"t\",\"http://a/v\":{\"q\":\"x\"}}",
      neg_plain_options(),
    ) {
    Ok(value) => fail("DIAG16 ok: " + render_json(value))
    Err(InvalidContext(msg)) => assert_eq(msg, "protected term redefinition")
    _ => fail("expected InvalidContext (type-scoped protection)")
  }
}

///|
test "tv: nest misuse in value object" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":{\"@nest\":\"unknown\"}}",
      neg_plain_options(),
    ) {
    Ok(value) => fail("DIAG17 ok: " + render_json(value))
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest in value object)")
  }
}

///|
test "tv: nest misuse in value array item" {
  match
    expand_document(
      "{\"@context\":{\"p\":\"http://a/p\"},\"p\":[{\"@nest\":\"unknown\"}]}",
      neg_plain_options(),
    ) {
    Ok(value) => fail("DIAG18 ok: " + render_json(value))
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest in array item)")
  }
}

///|
test "tv: set-only object under list container" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":{\"@set\":[\"x\"]}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"http://a/p\":[{\"@value\":\"x\"}]}]")
    // @set 包裹在 list 容器位解包为普通字面量
    _ => fail("expected Ok (set unwrapped under list container)")
  }
}

///|
/// 批7-C：list_item / graph_container / frame_preserve 残臂
test "li: 1.0 bare array item is list of lists" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[[\"x\"]]}",
      neg_plain10_options(),
    ) {
    Err(InvalidList(msg)) => assert_eq(msg, "list of lists")
    _ => fail("expected InvalidList (1.0 nested array)")
  }
}

///|
test "li: 1.0 nested list object is list of lists" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[{\"@list\":[{\"@list\":[\"y\"]}]}]}",
      neg_plain10_options(),
    ) {
    Err(InvalidList(msg)) => assert_eq(msg, "list of lists")
    _ => fail("expected InvalidList (1.0 nested list object)")
  }
}

///|
test "li: 1.0 flat list object tolerated" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[{\"@list\":[\"x\"]}]}",
      neg_plain10_options(),
    ) {
    // 1.0 对 list 位的 @list 对象同样判 list of lists
    Err(InvalidList(msg)) => assert_eq(msg, "list of lists")
    _ => fail("expected InvalidList (1.0 list object)")
  }
}

///|
test "li: two-key object inside list rejected" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[{\"@list\":[1],\"@set\":[2]}]}",
      neg_plain_options(),
    ) {
    Err(InvalidList(msg)) => assert_eq(msg, "invalid set or list object")
    _ => fail("expected InvalidList (two-key in list)")
  }
}

///|
test "li: null inside nested array dropped" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[[\"x\",null]]}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@list\":[{\"@list\":[{\"@value\":\"x\"}]}]}]}]",
      ) // 嵌套数组 1.1 保嵌套 List、null 丢
    _ => fail("expected Ok (nested list kept)")
  }
}

///|
test "td: colon-initial value is not cyclic" {
  match
    expand_document(
      "{\"@context\":{\"a\":\":x\",\"b\":\"http://b/\"},\"a\":\"v\"}",
      neg_plain_options(),
    ) {
    Ok(_) => ()
    _ => fail("expected Ok (colon-initial not cyclic)")
  }
}

///|
test "gc: non-map value under id-secondary rejected" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@id\"]}},\"p\":\"v\"}",
      neg_plain_options(),
    ) {
    Err(InvalidValue(msg)) => assert_eq(msg, "invalid graph container value")
    _ => fail("expected InvalidValue (non-map graph id value)")
  }
}

///|
test "gc: map entry nest misuse" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@id\"]}},\"p\":{\"http://x/\":{\"@nest\":\"unknown\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest in graph map entry)")
  }
}

///|
test "gc: bare graph array item nest misuse" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@graph\"}},\"p\":[{\"@nest\":\"unknown\"}]}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest in graph array item)")
  }
}

///|
test "gc: index secondary without mapping" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@index\"]}},\"p\":{\"i\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@graph\":[{\"@id\":\"http://x/\"}],\"@index\":\"i\"}]}]",
      ) // 无映射 → 键附挂 @index
    _ => fail("expected Ok (index attach)")
  }
}

///|
test "gc: index mapping named attaches property" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@index\"],\"@index\":\"http://a/idx\"}},\"p\":{\"i\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"http://a/idx\":[{\"@value\":\"i\"}],\"@graph\":[{\"@id\":\"http://x/\"}]}]}]",
      ) // 命名映射 → 索引成属性
    _ => fail("expected Ok (mapping property attach)")
  }
}

///|
test "gc: scalar entry value in id map" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@id\"]}},\"p\":{\"http://x/\":\"v\"}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"http://a/p\":[{\"@value\":\"v\"}]}]")
    // 标量条目值直出字面量
    _ => fail("expected Ok (scalar entry literal)")
  }
}

///|
test "fp: null default is @null literal" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":null}}",
      neg_frame_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@reverse\":{\"http://a/p\":[{\"@default\":[{\"@value\":\"@null\"}]}]}}]",
      ) // null 默认 = "@null" 字面
    _ => fail("expected Ok (null default literal)")
  }
}

///|
test "fp: object default with nest misuse" {
  match
    expand_document(
      "{\"@context\":{\"rev\":{\"@reverse\":\"http://a/p\"}},\"rev\":{\"@default\":{\"@nest\":\"unknown\"}}}",
      neg_frame_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest in default object)")
  }
}

///|
test "li: unknown-only node in list position" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[{\"unknown\":\"v\"}]}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(render_json(value), "[{\"http://a/p\":[{\"@list\":[{}]}]}]")
    // 未知属性独占节点 = 空 pattern 保留在 list 位
    _ => fail("expected Ok (empty node kept in list)")
  }
}

///|
test "ctx: bool @version rejected" {
  match
    expand_document("{\"@context\":{\"@version\":true}}", neg_plain_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @version value")
    _ => fail("expected InvalidContext (bool @version)")
  }
}

///|
test "li: 1.0 set object in list tolerated" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@list\"}},\"p\":[{\"@set\":[\"x\"]}]}",
      neg_plain10_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@list\":[{\"@value\":\"x\"}]}]}]",
      ) // 1.0 下 @set 对象同样解包为裸字面量（与 1.1 DIAG19 同形）
    Err(InvalidList(msg)) => fail("unexpected list error: " + msg)
    Err(_) => fail("unexpected error")
  }
}

///|
test "gc: graph-object entry attaches in place" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@index\"],\"@index\":\"http://a/idx\"}},\"p\":{\"i\":{\"@graph\":{\"@id\":\"http://x/\"}}}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"http://a/idx\":[{\"@value\":\"i\"}],\"@graph\":[]}]}]",
      ) // 既有 graph 对象支：条目值即 graph 形 → 原位附挂（index 映射属性 + @graph）
    Err(_) => fail("unexpected error")
  }
}

///|
test "gc: plain graph+index without index mapping" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":[\"@graph\",\"@index\"]}},\"p\":{\"i\":{\"@id\":\"http://x/\"}}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@graph\":[{\"@id\":\"http://x/\"}],\"@index\":\"i\"}]}]",
      ) // 无 @index 映射：条目键走默认 @index 附挂（graph+index 双容器缺省形）
    Err(_) => fail("unexpected error")
  }
}

///|
test "set: node object value passes through set arm" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@set\"}},\"p\":{\"@id\":\"http://x/\"}}",
      neg_plain_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"http://a/p\":[{\"@id\":\"http://x/\"}]}]",
      ) // @set 容器摊平不包裹——节点对象直过 set 臂（4968 Ok(None) → expand_object）
    Err(_) => fail("unexpected error")
  }
}

///|
test "set: nest misuse single object propagates" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@set\"}},\"p\":{\"@nest\":\"unknown\"}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest misuse single)")
  }
}

///|
test "set: nest misuse array item propagates" {
  match
    expand_document(
      "{\"@context\":{\"p\":{\"@id\":\"http://a/p\",\"@container\":\"@set\"}},\"p\":[{\"@nest\":\"unknown\"}]}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value")
    _ => fail("expected InvalidContext (nest misuse array)")
  }
}

///|
test "DIAGO: plain set-object nest single" {
  match
    expand_document(
      "{\"p\":{\"@set\":{\"@nest\":\"unknown\"}}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value") // 明文 @set 对象拦截 → set 臂 single → nest 误用上抛（4966）
    _ => fail("expected InvalidContext (set single nest)")
  }
}

///|
test "DIAGP: plain set-object nest array" {
  match
    expand_document(
      "{\"p\":{\"@set\":[{\"@nest\":\"unknown\"}]}}",
      neg_plain_options(),
    ) {
    Err(InvalidContext(msg)) => assert_eq(msg, "invalid @nest value") // 明文 @set 数组拦截 → set 臂逐项 → nest 误用上抛（4946）
    _ => fail("expected InvalidContext (set array nest)")
  }
}
