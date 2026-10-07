// ===== 役C2 批1：compact_standard 未覆盖臂探针（小族先收） =====
// 二路手段：① **白盒直调**（compact_bare_fit / compact_object_fit /
// compact_value_jv / compact_list_bare_fit / literal_datatype_of /
// compact_property_values）——把臂状态手工构造成型，臂级可达性可判；
// ② **pub 入口** compact_document——管线可达性（含 base 相对上跳族）。
// 纪律：探针先跑、看未行闭合再定性——**死账须实证，推理不记账**（用户令）。

///|
/// plain 档 options（1.1，无 base——与 expand neg_plain_options 同形）
fn c2_options() -> JsonLdOptions {
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
/// 1.0 档 options（嵌套 list 报错臂入口）
fn c2_options_10() -> JsonLdOptions {
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
/// 字面量构造（缺省全 None——逐例覆写需要的位）
fn c2_lit(
  value : String,
  datatype : String?,
  language : String?,
  direction : String?,
  raw : JsonValue?,
) -> ExpandedLiteral {
  { value, datatype, language, direction, raw, index: None, included: None, }
}

///|
/// 节点构造（id-only 或带属性）
fn c2_node(
  id : String?,
  properties : Array[(String, Array[ExpandedValue])],
) -> ExpandedNode {
  {
    id,
    types: [],
    properties,
    reverse_props: [],
    graph: None,
    included: None,
    index: None,
  }
}

///|
/// term 定义构造（只列本批要动的五个位，其余缺省）
fn c2_td(
  iri : String?,
  datatype : String?,
  container : ContainerType?,
  language_mapping : LanguageMember?,
  direction_mapping : LanguageMember?,
) -> TermDefinition {
  {
    iri,
    datatype,
    container,
    reverse: None,
    graph_secondary: None,
    local_context: None,
    context_base_url: None,
    index_mapping: None,
    is_protected: false,
    is_prefix: None,
    language_mapping,
    direction_mapping,
    nest: None,
    simple_form: false,
    graph_set: false,
    container_set: false,
  }
}

///|
/// 活动 context 构造（无 term 表——直调族的 term 由入参单传）
fn c2_active(
  default_language : String?,
  default_direction : String?,
) -> ActiveContext {
  {
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language,
    default_direction,
  }
}

///|
/// 裸串断言助手（避免 `is JsonValue::String(...)` 字面量模式的解析歧义）
fn c2_expect_bare_string(out : JsonValue) -> Unit raise {
  match out {
    JsonValue::String(s) => assert_eq(s, "x")
    _ => fail("expected bare string, got non-string")
  }
}

///|
/// 值适配族（bare_fit 方向缺省对齐：行 451）——td 无方向映射 + 值带方向 +
/// context 缺省方向在场 ⇒ 走 `None => …d == default_direction` 臂
test "C2-01 bare_fit 方向缺省对齐（行 451）" {
  let active = c2_active(None, Some("rtl"))
  let td = c2_td(Some("http://ex/p"), None, None, None, None)
  let v = ExpandedValue::Value(c2_lit("x", None, None, Some("rtl"), None))
  assert_true(compact_bare_fit(v, td, active))
}

///|
/// 对象适配族（object_fit 方向映射 Null 臂：行 533）——td `@direction: null`
/// + 值无方向 ⇒ dir_aligned 取 Null 臂
test "C2-02 object_fit 方向映射 Null 臂（行 533）" {
  let active = c2_active(Some("en"), None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    None,
    None,
    Some(LanguageMember::Null),
  )
  let v = ExpandedValue::Value(
    c2_lit("x", Some("http://ex/t"), None, None, None),
  )
  assert_true(compact_object_fit(v, td, active))
}

///|
/// 对象适配族（object_fit 方向缺省对齐：行 536）——td 无方向映射 + 值带方向
/// + context 缺省方向在场
test "C2-03 object_fit 方向缺省对齐（行 536）" {
  let active = c2_active(None, Some("rtl"))
  let td = c2_td(Some("http://ex/p"), None, None, None, None)
  let v = ExpandedValue::Value(
    c2_lit("x", Some("http://ex/t"), None, Some("rtl"), None),
  )
  assert_true(compact_object_fit(v, td, active))
}

///|
/// 值压缩族（语言吸收 × 方向 Set：行 600）——语言合且方向合 ⇒ 裸串吸收
test "C2-04 value_jv 语言吸收×方向 Set（行 600）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    None,
    Some(LanguageMember::Set("en")),
    Some(LanguageMember::Set("rtl")),
  )
  let out = compact_value_jv(
    c2_lit("x", None, Some("en"), Some("rtl"), None),
    Some(td),
    active,
    active,
    c2_options(),
  )
  c2_expect_bare_string(out)
}

///|
/// 值压缩族（语言映射 Set 但值无语言：行 611）——语言吸收 None 臂，续走缺省
test "C2-05 value_jv 语言映射 Set 值无语言（行 611）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    None,
    Some(LanguageMember::Set("en")),
    None,
  )
  let out = compact_value_jv(
    c2_lit("x", None, None, None, None),
    Some(td),
    active,
    active,
    c2_options(),
  )
  c2_expect_bare_string(out)
}

///|
/// 值压缩族（语言映射 Null × 方向 Set：行 616）——语言压制臂内方向对齐
test "C2-06 value_jv 语言 Null×方向 Set 吸收（行 616）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    None,
    Some(LanguageMember::Null),
    Some(LanguageMember::Set("rtl")),
  )
  let out = compact_value_jv(
    c2_lit("x", None, None, Some("rtl"), None),
    Some(td),
    active,
    active,
    c2_options(),
  )
  c2_expect_bare_string(out)
}

///|
/// 值压缩族（方向映射 Null 吸收 raw：行 642）——无方向值在 `@direction: null`
/// term 下裸形（raw 标量——数值/布尔原样）
test "C2-07 value_jv 方向 Null 吸收 raw（行 642）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    None,
    None,
    Some(LanguageMember::Null),
  )
  let out = compact_value_jv(
    c2_lit("true", None, None, None, Some(JsonValue::Bool(true))),
    Some(td),
    active,
    active,
    c2_options(),
  )
  match out {
    JsonValue::Bool(b) => assert_true(b)
    _ => fail("expected raw bool passthrough")
  }
}

///|
/// list 适配族（首项非 Value：行 2636）——`@list` 容器 × 方向 Set，
/// 首项为节点 ⇒ 方向闸取 `_ => true`（逐项方向闸只对首值字面量生效）
test "C2-08 list_bare_fit 首项非 Value（行 2636）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    Some(ContainerType::List),
    None,
    Some(LanguageMember::Set("rtl")),
  )
  let items = [ExpandedValue::Node(c2_node(Some("http://ex/n"), []))]
  assert_true(compact_list_bare_fit(items, None, td, active))
}

///|
/// datatype 取形族（混合列：行 347）——已收 datatype 后再遇无 datatype 值项
/// ⇒ mixed
test "C2-09 literal_datatype_of 混合列（行 347）" {
  let typed = ExpandedValue::Value(
    c2_lit("a", Some("http://ex/dt"), None, None, None),
  )
  let plain = ExpandedValue::Value(c2_lit("b", None, None, None, None))
  let list = ExpandedValue::List([typed, plain], index=None)
  assert_true(literal_datatype_of(list) is None)
}

///|
/// **死带拆除复跑钉·形一**（原 @list 吸收块，役C2批2 拆）：同入参现走
/// `compact_value_item` 的 List 容器臂（本函数逐值调用）⇒ 单 List 值仍出裸数组
/// ——**行为零变更**（拆前/拆后同果）
test "C2-S1 property_values @list 吸收（拆后走 value_item 臂）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    Some(ContainerType::List),
    None,
    None,
  )
  let vals = [
    ExpandedValue::List(
      [ExpandedValue::Value(c2_lit("x", None, None, None, None))],
      index=None,
    ),
  ]
  match compact_property_values(vals, Some(td), active, c2_options()) {
    Ok(JsonValue::Array(items)) => assert_eq(items.length(), 1)
    _ => fail("expected absorbed bare array")
  }
}

///|
/// **死带拆除复跑钉·形二**：1.0 档 + 嵌套 list ⇒ `compaction to list of lists`
/// ——拆前属被删块内错误臂，拆后由 `compact_value_item` 同判据（行 1062）抛，
/// 经本函数 Err 传播臂（行 1122）返回
test "C2-S2 property_values @list×1.0 嵌套 list（拆后走 value_item 1062）" {
  let active = c2_active(None, None)
  let td = c2_td(
    Some("http://ex/p"),
    None,
    Some(ContainerType::List),
    None,
    None,
  )
  let inner = ExpandedValue::List(
    [ExpandedValue::Value(c2_lit("x", None, None, None, None))],
    index=None,
  )
  let vals = [ExpandedValue::List([inner], index=None)]
  match compact_property_values(vals, Some(td), active, c2_options_10()) {
    Err(InvalidList(_)) => ()
    _ => fail("expected InvalidList (compaction to list of lists)")
  }
}

///|
/// **管线探针·base 相对多段上跳**（行 307）：base 目录 1 段、目标 2 段
/// ⇒ `../bb/` 的段间 "/" 拼接臂（307）
test "C2-P1 pub 管线 多段 ../ 上跳（行 307）" {
  let ctx = "{\"@context\":{\"@base\":\"http://a.example/aa/\",\"@vocab\":\"http://a.example/vocab/\"}}"
  let doc = "{\"@context\":{\"@base\":\"http://a.example/aa/\",\"@vocab\":\"http://a.example/vocab/\"},\"@id\":\"../bb/cc\",\"p\":\"x\"}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(pairs.any(fn(p) { p.1 == JsonValue::String("../bb/cc") }))
    _ => fail("expected object with relative id")
  }
}

///|
/// **管线探针·base 相对上跳越界断臂**（行 296）：base 目录 2 段、目标 1 段
/// ⇒ `it` 提前耗尽走 break（296）
test "C2-P2 pub 管线 上跳越界 break（行 296）" {
  let ctx = "{\"@context\":{\"@base\":\"http://a.example/aa/bb/\",\"@vocab\":\"http://a.example/vocab/\"}}"
  let doc = "{\"@context\":{\"@base\":\"http://a.example/aa/bb/\",\"@vocab\":\"http://a.example/vocab/\"},\"@id\":\"../../aa\",\"p\":\"x\"}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(pairs.any(fn(p) { p.1 == JsonValue::String("../") }))
    _ => fail("expected object with up-jump id")
  }
}

///|
/// **证伪尝试·裸 authority base 的上跳族**（行 232/235/253/257/261）：base 无路径
/// （"http://a.example"）时 `boundary`（"http://"）先命中前缀短路 ⇒ 上跳块整体
/// 不进——探针跑通即「前缀短路先手」，三行不得转死账（须另立可达性论证）
test "C2-F1 pub 管线 裸 authority base 前缀短路（行 232/253/257 证伪尝试）" {
  let ctx = "{\"@context\":{\"@base\":\"http://a.example\",\"@vocab\":\"http://a.example/vocab/\"}}"
  let doc = "{\"@context\":{\"@base\":\"http://a.example\",\"@vocab\":\"http://a.example/vocab/\"},\"@id\":\"/bb/cc\",\"p\":\"x\"}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) => {
      let mut id_word = ""
      let mut seen = false
      for p in pairs {
        if p.0 == "@id" {
          match p.1 {
            JsonValue::String(s) => id_word = s
            _ => fail("@id value not a string")
          }
          seen = true
        }
      }
      assert_true(seen)
      // 记录实测：前缀短路胜出（词形 = base 剥 "http://" 后的残余），上跳块未进
      assert_true(id_word == "a.example/bb/cc")
    }
    _ => fail("expected object")
  }
}

///|
/// **结构性疑点·定性探针**（行 1105/1106 族 = `compact_property_values` 的 @list
/// 容器吸收块）：唯一调用点 = `compact_property_pair`（1229），
/// 而 `compact_property_pair` 三处调用（892/2065/2107）只能供**反向位** td
/// （2107 处候选集已空 ⇒ td_opt=None）——反向 term 的容器白名单 = @set/@index/
/// None（expand_standard.mbt 4432-4439 `invalid reverse property`）⇒ 本节
/// `td.container is Some(List)` **恒假**。探针实证：`@reverse × @container @list`
/// 定义期即被拒（非运行期分流）。
test "C2-S3 @reverse×@list 定义期拒绝（行 1105 死带定性）" {
  let ctx = "{\"@context\":{\"r\":{\"@reverse\":\"http://ex/p\",\"@container\":\"@list\"}}}"
  let doc = "{\"@context\":{\"r\":{\"@reverse\":\"http://ex/p\",\"@container\":\"@list\"}},\"@id\":\"http://ex/s\",\"r\":[\"a\"]}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(_)) => ()
    _ => fail("expected InvalidContext (invalid reverse property)")
  }
}

///|
/// **证伪尝试·语言映射 × 数值标量**（行 606）：语言吸收要求值带语言，而数值/
/// 布尔裸值在展开期恒无语言 ⇒ `Some(raw) => raw`（606）无管线径
test "C2-F2 pub 管线 语言映射 term × 数值值（行 606 证伪尝试）" {
  let ctx = "{\"@context\":{\"p\":{\"@id\":\"http://ex/p\",\"@language\":\"en\"}}}"
  let doc = "{\"@context\":{\"p\":{\"@id\":\"http://ex/p\",\"@language\":\"en\"}},\"@id\":\"http://ex/s\",\"p\":1}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(_)) => ()
    _ => fail("expected compacted object")
  }
}

///|
/// **证伪尝试·方向映射 × 数值标量**（行 635）：方向吸收要求值带方向 ⇒ 数值值
/// 不入 `Some(Set(d)) => …raw`（635）臂
test "C2-F3 pub 管线 方向映射 term × 数值值（行 635 证伪尝试）" {
  let ctx = "{\"@context\":{\"@direction\":\"rtl\",\"p\":{\"@id\":\"http://ex/p\",\"@direction\":\"rtl\"}}}"
  let doc = "{\"@context\":{\"@direction\":\"rtl\",\"p\":{\"@id\":\"http://ex/p\",\"@direction\":\"rtl\"}},\"@id\":\"http://ex/s\",\"p\":1}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(_)) => ()
    _ => fail("expected compacted object")
  }
}

// ===== 役C2 批2：错传播链一击 + 上跳块 bp/ip/auth 臂 =====
// 撞名族纪律：ctx 只走参数、doc 不嵌 @context——嵌则展开期把 "tag:…"
// CURIE 化为 td_iri+rest，压缩位撞名检测自消（td_iri+rest == pred 豁免形）。

///|
/// **错传播链·@list 项节点属性位 scheme 撞名**（行 1066）：撞名 Err 在项节点
/// 正向属性 fallback 键位（1928 → 1159 Err）引爆——项节点无 id 有属性 ⇒
/// compact_value_item Node 臂 1046 回传 ⇒ 列环 Err 臂 1066。判据同 #te002。
test "C2-B2-01 列表项节点内撞名错传播（行 1066）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\"}}"
  let doc = "{\"http://a/p\":{\"@list\":[{\"tag:2010\":\"v\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **错传播链·@reverse 块 pred 撞名**（行 1201）：@reverse 块内属性
/// "tag:2010"（绝对 IRI 形 pred）无反转 term 匹配 ⇒ compact_property_pair
/// 反转位 key=compact_iri_word=原形 ⇒ 撞名检测（scheme "tag" 在册且重展开
/// 异）⇒ Err（1201）。te002 oracle 走正向 1928 位——本探针补反转位。
test "C2-B2-02 @reverse 块 pred 撞名（行 1201）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\"}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"tag:2010\":[{\"@id\":\"http://ex/o\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **错传播链·反转 term 载撞名子节点**（行 1122/1205）：反转 term r 的对象值
/// 节点内含撞名正向属性 ⇒ 子节点压缩 Err ⇒ compact_value_item Node 臂回传 ⇒
/// property_values 值环 Err 臂 1122 ⇒ compact_property_pair 1205。
test "C2-B2-03 反转 term 载撞名子（行 1122/1205）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\",\"r\":{\"@reverse\":\"http://a/r\"}}}"
  let doc = "{\"@id\":\"http://ex/s\",\"http://a/r\":[{\"tag:2010\":\"v\"}]}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **@vocab-miss 词形路 × 裸 authority base 保绝对**（行为钉）：@vocab 型
/// term 未命中走前缀词步（compact_iri_word 1018 allow_base=false）⇒ 174 门
/// （compactToRelative && allow_base——上跳块整体嵌于其内）跳过 ⇒ 尾点绝对
/// 返回。行 232/253 定谳门死（另账）：裸 authority base ⇒ boundary="http://"
/// ⇒ 205 前缀短路先手，allow_base=true 面亦不达 227。
/// base 纪律：active.base 只从 ctx `@base` 来（options.base 不入链）。
test "C2-B2-04 @vocab-miss 裸 authority base 保绝对（行为钉）" {
  let ctx = "{\"@context\":{\"@base\":\"http://a.example\",\"tv\":{\"@id\":\"http://a/q\",\"@type\":\"@vocab\"}}}"
  let doc = "{\"http://a/q\":[{\"@id\":\"http://b.example/x/y\"}]}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(
        pairs.any(fn(p) {
          p.0 == "tv" && p.1 == JsonValue::String("http://b.example/x/y")
        }),
      )
    _ => fail("expected compacted object")
  }
}

///|
/// **base 无 `//` × @id 值词形路**（行 235/261）：base 形 "http:x/y"
/// （scheme 冒号+路径斜杠在、无 `//`）⇒ boundary="http:x/y" 对
/// "http://b.example/x/y" 前缀失配 ⇒ 落入 227；base.find("//")=None ⇒
/// bp=base 原形（235）；authority_ok 元组首位 None ⇒ `_ => false`（261）。
/// 上跳块整体嵌于 174 门（compactToRelative && allow_base）⇒ 须 allow_base=true
/// 路（@id 值渲染 1036 调用形）。authority 异 ⇒ 保绝对词面。
test "C2-B2-05 base 无 // bp/auth 臂（行 235/261）" {
  let ctx = "{\"@context\":{\"@base\":\"http:x\",\"tv\":{\"@id\":\"http://a/q\",\"@type\":\"@vocab\"}}}"
  let doc = "{\"http://a/q\":[{\"@id\":\"http://b.example/x/y\"}]}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(
        pairs.any(fn(p) {
          p.0 == "tv" && p.1 == JsonValue::String("http://b.example/x/y")
        }),
      )
    _ => fail("expected compacted object")
  }
}

///|
/// **term:null 的 scheme 位**（行 1167）：`"tag": null` 保 term、iri 映射
/// null（expand_standard.mbt 3866-3876 唯一 iri:None 构造点）⇒ 键
/// "tag:x" 撞名检测时 `active.terms.get("tag")` Some 而 `td.iri` None
/// ⇒ 内层 None 臂（1167）⇒ Ok 放行（词面不塌）。
test "C2-B2-06 term:null scheme 位（行 1167）" {
  let ctx = "{\"@context\":{\"tag\":null}}"
  let doc = "{\"tag:x\":\"v\"}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(
        pairs.any(fn(p) { p.0 == "tag:x" && p.1 == JsonValue::String("v") }),
      )
    _ => fail("expected compacted object")
  }
}

///|
/// **反转位 × compact_arrays=false**（行 1109）：property_values 的
/// keep_array 门——`!options.compact_arrays` ⇒ 单值也保数组形。
test "C2-B2-07 反转位 compact_arrays=false（行 1109）" {
  let ctx = "{\"@context\":{\"r\":{\"@reverse\":\"http://a/r\"}}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"http://a/r\":[{\"@id\":\"http://ex/o\"}]}}"
  let opts = {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: false,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
  match compact_document(doc, ctx, opts) {
    Ok(JsonValue::Object(pairs)) => {
      // compact_arrays=false ⇒ 顶层单节点走 @graph 包裹——r 对在 @graph[0] 内
      let mut seen = false
      for p in pairs {
        if p.0 == "@graph" {
          match p.1 {
            JsonValue::Array(items) =>
              match items[0] {
                JsonValue::Object(node) =>
                  for np in node {
                    if np.0 == "r" {
                      assert_true(np.1 is JsonValue::Array(_))
                      seen = true
                    }
                  }
                _ => fail("expected node in graph")
              }
            _ => fail("expected graph array")
          }
        }
      }
      assert_true(seen)
    }
    _ => fail("expected compacted object")
  }
}

///|
/// **图容器 term × 非载体节点值**（行 1466）：graph_td 命中而子节点无
/// @graph ⇒ `match child.graph` None 臂（1466）⇒ 落回常规分选。
test "C2-B2-08 图容器非载体节点（行 1466）" {
  let ctx = "{\"@context\":{\"g\":{\"@id\":\"http://a/g\",\"@container\":\"@graph\"}}}"
  let doc = "{\"http://a/g\":[{\"@id\":\"http://ex/x\"}]}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(_)) => ()
    _ => fail("expected compacted object")
  }
}

///|
/// **图容器 term × 字面量值**（行 1468）：graph_td 命中而值非节点 ⇒
/// `_ => ()`（1468）⇒ 落回常规分选。
test "C2-B2-09 图容器字面量值（行 1468）" {
  let ctx = "{\"@context\":{\"g\":{\"@id\":\"http://a/g\",\"@container\":\"@graph\"}}}"
  let doc = "{\"http://a/g\":[\"x\"]}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(_)) => ()
    _ => fail("expected compacted object")
  }
}

///|
/// **图容器内容子节点撞名**（行 1375）：@graph 载体内容节点含撞名正向
/// 属性 ⇒ compact_node_jv(sub) Err ⇒ 内容环 Err 臂（1375）。
test "C2-B2-10 图内容子节点撞名（行 1375）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\",\"g\":{\"@id\":\"http://a/g\",\"@container\":\"@graph\"}}}"
  let doc = "{\"http://a/g\":[{\"@graph\":[{\"tag:2010\":\"v\"}]}]}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **图载体带 id × 裸次级撞名**（行 1458）：container @graph（次级 None）、
/// 载体节点带 @id ⇒ graph_bares 渲染 Err ⇒ 1458。
test "C2-B2-12 图载体裸次级撞名（行 1458）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\",\"g\":{\"@id\":\"http://a/g\",\"@container\":\"@graph\"}}}"
  let doc = "{\"http://a/g\":[{\"@id\":\"http://ex/c\",\"tag:2010\":\"v\",\"@graph\":[{\"@id\":\"http://ex/x\"}]}]}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **@set term 前置扫描**（行 1503）：同 IRI 双 term（@set + @language
/// 映射图）+ 无语言值 ⇒ non-map bare-fit 前置扫描归 @set term ⇒
/// group_array Set/List 臂（1503）⇒ 保数组形。
test "C2-B2-13 @set term 前置扫描（行 1503）" {
  let ctx = "{\"@context\":{\"ls\":{\"@id\":\"http://a/l\",\"@container\":\"@set\"},\"ll\":{\"@id\":\"http://a/l\",\"@container\":\"@language\"}}}"
  let doc = "{\"http://a/l\":[\"x\"]}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(JsonValue::Object(pairs)) =>
      assert_true(
        pairs.any(fn(p) { p.0 == "ls" && p.1 is JsonValue::Array(_) }),
      )
    _ => fail("expected compacted object")
  }
}

///|
/// **图映射反转 term 的 map-miss 单值对**（行 1205）：反转 term 带 @index
/// 映射容器（反转定义期白名单 @set/@index/None——@language 形定义期即拒）、
/// 值=无 @index 节点 ⇒ compact_map_entry None ⇒ 2039 单值
/// compact_property_pair（反转位）⇒ 1203 compact_property_values ⇒ 值内
/// 撞名属性 Err ⇒ 1122 ⇒ 1205。
test "C2-B2-14 图映射反转 map-miss 单值对（行 1205）" {
  let ctx = "{\"@context\":{\"tag\":\"http://ns/tag/\",\"r\":{\"@reverse\":\"http://a/r\",\"@container\":\"@index\"}}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"http://a/r\":[{\"tag:2010\":\"v\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **直调 compact_iri_word × allow_base=false 位保绝对**（行为钉）：174 门
/// require allow_base=true——false 位（失配兜底位）整块跳过（base 相对化 +
/// 上跳块同门），恒保绝对词面。行 232/253 需 base 带 `//` + 裸 authority +
/// allow_base=true，但彼形 boundary="http://" 被行 204 前缀短路截走（门死
/// 维持批1 判；同 scheme 层级 IRI 无绕行形）。
test "C2-B2-15 直调 allow_base=false 位保绝对（行为钉）" {
  let terms : Map[String, TermDefinition] = Map([])
  terms["tv"] = c2_td(Some("http://a/q"), Some("@vocab"), None, None, None)
  let active : ActiveContext = {
    base: Some("http://a.example"),
    vocab: None,
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let word = compact_iri_word(
    "http://b.example/x/y",
    false,
    false,
    false,
    active,
    c2_options(),
  )
  assert_eq(word, "http://b.example/x/y")
}

///|
/// **直调 compact_iri_word × base 无 `//`**（行 235/261 终证）：base 形
/// "http:x/y"（裸冒 scheme + path——纯 "http:x" 不行：boundary 退化 "http:"
/// 被行 204 前缀截走）⇒ 行 204 不截、226 门全开 ⇒ base.find("//")=None ⇒
/// bp=base 原形（235）+ authority 元组 `(None,Some)` 落 `_`（261）；
/// authority 判 false ⇒ 落 319 尾保绝对词面。
test "C2-B2-16 直调 base 无 //（行 235/261）" {
  let terms : Map[String, TermDefinition] = Map([])
  terms["tv"] = c2_td(Some("http://a/q"), Some("@vocab"), None, None, None)
  let active : ActiveContext = {
    base: Some("http:x/y"),
    vocab: None,
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let word = compact_iri_word(
    "http://b.example/x/y",
    false,
    false,
    true,
    active,
    c2_options(),
  )
  assert_eq(word, "http://b.example/x/y")
}

///|
/// **language×direction-null 组合臂 + 数值 raw 吸收**（行 601/617/606/635）：
/// term @language+@direction:null（601 判向）× 串值；@language:null+
/// @direction:null（617 判向）× 裸串值；@language × 数值 raw（606 raw Some
/// 臂）；@direction × 数值 raw（635 raw Some 臂）——数值能否带 language/
/// direction 过展开，实证为准。
test "C2-B2-17 language 方向组合吸收两臂" {
  let ctx = "{\"@context\":{\"lda\":{\"@id\":\"http://a/lda\",\"@language\":\"en\",\"@direction\":null},\"ldn\":{\"@id\":\"http://a/ldn\",\"@language\":null,\"@direction\":null}}}"
  let doc = "{\"http://a/lda\":{\"@value\":\"x\",\"@language\":\"en\"},\"http://a/ldn\":{\"@value\":\"x\"}}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(jv) => {
      let out = render_json(jv)
      assert_true(out.find("\"lda\":\"x\"") is Some(_))
      assert_true(out.find("\"ldn\":\"x\"") is Some(_))
    }
    Err(InvalidContext(msg)) => fail("ctx err: " + msg)
    Err(_) => fail("last-resort err")
  }
}

///|
/// **数值 raw × direction 吸收**（行 635 raw Some 臂）：数值 @value 带
/// @direction 过展开（引擎实证放行）⇒ direction 吸收回传 raw 数值裸形。
/// **606 负得入账**：数值+@language 展开期 `InvalidValue: invalid
/// language-tagged value` 拒——raw Some（数值/布尔/@json 专属）与 language
/// Some（串值专属）无交集 ⇒ raw Some 臂（606）构造性死候选（双证：探针
/// 负得 + raw 填充点 1543/1563/1581/2839 全 language None）。
test "C2-B2-18 数值 raw × direction 吸收（635）+ 606 负得" {
  let ctx = "{\"@context\":{\"ldr\":{\"@id\":\"http://a/ldr\",\"@direction\":\"rtl\"}}}"
  let doc = "{\"http://a/ldr\":{\"@value\":2,\"@direction\":\"rtl\"}}"
  match compact_document(doc, ctx, c2_options()) {
    Ok(jv) =>
      assert_eq(
        render_json(jv),
        "{\"@context\":{\"ldr\":{\"@id\":\"http://a/ldr\",\"@direction\":\"rtl\"}},\"ldr\":2}",
      )
    Err(InvalidContext(msg)) => fail("InvalidContext: " + msg)
    Err(InvalidValue(msg)) => fail("InvalidValue: " + msg)
    Err(_) => fail("other family (not ctx/value)")
  }
}

///|
/// **反转位分键路内嵌撞名**（行 899+2078 双闭）：无反转 term × 正向候选
/// fw ⇒ 2067 分键路；值节点非 id-only ⇒ bare_fit 败 ⇒ **best=None**
/// （分键路为单遍 bare_fit 环、无 object 二遍——884 门死判据）⇒ 892 逐值
/// property_pair ⇒ 节点对象递归内嵌 "tag:2010" 撞名 Err（1201→1205）⇒
/// 899 ⇒ 分键路 Err 臂 2078。
test "C2-B2-19 反转位对象形内嵌撞名（899+2078）" {
  let ctx = "{\"@context\":{\"fw\":\"http://a/r\",\"tag\":\"http://ns/tag/\"}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"http://a/r\":[{\"@id\":\"http://ex/o\",\"tag:2010\":\"v\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **反转 term 位分键路内嵌撞名**（行 2057）：反转 term r（无容器）× 多值
/// ⇒ 2052 分键路；撞名值对象形 fit ⇒ 884 传播 ⇒ 2057。与 B2-19 同机制，
/// 分支入口异（有/无反转 term）。
test "C2-B2-20 反转 term 分键路内嵌撞名（2057）" {
  let ctx = "{\"@context\":{\"r\":{\"@reverse\":\"http://a/r\"},\"tag\":\"http://ns/tag/\"}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"http://a/r\":[{\"@id\":\"http://ex/o\"},{\"@id\":\"http://ex/o2\",\"tag:2010\":\"v\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}

///|
/// **分键路 None 臂逐值 property_pair 内嵌撞名**（行 899）：候选 fw 在册但
/// 值两头不 fit（datatype 版 term——bare_fit 字面量面 @id 型拒绝、节点位
/// object_fit 非 @id/@vocab/@none 拒）⇒ best=None ⇒ 892 逐值
/// property_pair ⇒ 节点对象递归内嵌撞名（1201→1205）⇒ 899 传播。
/// （List@index 形负得：@reverse 位禁 @list——展开期
/// InvalidValue「invalid reverse property value」。）
test "C2-B2-21 分键路 None 臂 datatype 版 term 值内嵌撞名（899）" {
  let ctx = "{\"@context\":{\"fw\":{\"@id\":\"http://a/r\",\"@type\":\"http://dt/x\"},\"tag\":\"http://ns/tag/\"}}"
  let doc = "{\"@id\":\"http://ex/s\",\"@reverse\":{\"http://a/r\":[{\"@id\":\"http://ex/o\",\"tag:2010\":\"v\"}]}}"
  match compact_document(doc, ctx, c2_options()) {
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Ok(jv) => fail("got OK: " + render_json(jv))
    Err(_) => fail("got other err")
  }
}
