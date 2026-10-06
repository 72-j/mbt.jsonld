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
