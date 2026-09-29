///|
/// #t0001 方法级对拍：expand_iri 绝对 IRI 原样返回（@id 键的身份展开）

///|
test "expand_iri absolute passthrough (#t0001 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  assert_true(
    IriExpander::expand_iri(
      e, active, "http://example.org/test#example", true, false,
    )
    is Ok("http://example.org/test#example"),
  )
}

///|
/// #t0001 方法级对拍：bnode 原样返回
test "expand_iri bnode passthrough (#t0001 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  assert_true(
    IriExpander::expand_iri(e, active, "_:b0", true, false) is Ok("_:b0"),
  )
}

///|
/// #t0001 端到端：仅 @id 的顶层节点 → free-floating → []
test "t0001 end-to-end: drop free-floating node (#t0001 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document("{\"@id\": \"http://example.org/test#example\"}", options)
    is Ok(Array([])),
  )
}

///|
/// 空对象端到端：无 @id 无属性 → free-floating → []
test "empty object end-to-end: free-floating (#t0001 同族判定)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(expand_document("{}", options) is Ok(Array([])))
}

///|
/// 契约烟雾：未落码钩子逐一调用，断言礼貌拒绝（Unsupported）——
/// "红而非错"纪律的可执行钉子；同时使 extend 清单与 with-fn 实现非死码。
/// **常驻活账**：Unsupported 断言数 = 未落码钩子数（当前 12；②批
/// expand_compact/lookup_term/resolve_base 转真行为，③批 concat_vocab 解挂）——
/// 每落一个方法，将其断言改为真行为断言；减到 0 = J2 expansion 完成。
/// 禁止一次性化（否则掩盖"静默实现成 Ok"）。
test "contract smoke: pending hooks refuse politely (red-not-wrong)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  // expand_term 已落码（①批）：属性位 null → 丢弃（空数组）——烟雾活账翻转示例
  assert_true(
    Expander::expand_term(e, active, "t", JsonValue::Null, None, options)
    is Ok([]),
  )
  // postprocess_value（#t0045 批升级）：恒等对非值；值对象空语言清除
  assert_true(Expander::postprocess_value(e, active, List([])) is Ok(List([])))
  // （模式位不收 struct 更新字面量 ⇒ 先取值再逐字段断言）
  match
    Expander::postprocess_value(
      e,
      active,
      ExpandedValue::Value(ExpandedLiteral::{
        value: "x",
        datatype: None,
        language: Some(""),
        direction: None,
        raw: None,
        index: None,
        included: None,
      }),
    ) {
    Ok(ExpandedValue::Value(lit)) => {
      assert_eq(lit.value, "x")
      assert_eq(lit.language, None)
      assert_eq(lit.direction, None)
    }
    _ => fail("postprocess: expected normalized literal")
  }
  assert_true(
    Expander::set_language(e, active, JsonValue::Null) is Err(Unsupported(_)),
  )
  assert_true(
    Expander::set_direction(e, active, JsonValue::Null) is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_list(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_set(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_graph(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_reverse(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_nest(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::expand_included(e, active, JsonValue::Null, None, options)
    is Err(Unsupported(_)),
  )
  assert_true(
    Expander::set_index(e, active, JsonValue::Null) is Err(Unsupported(_)),
  )
  assert_true(IriExpander::handle_keyword(e, "@id") is Ok("@id"))
  // expand_compact 已落码（②批）：未声明前缀 = 非错误拒绝（落链由 expand_iri）——烟雾活账翻转
  assert_true(
    IriExpander::expand_compact(e, active, "ex:t", true, false)
    is Err(InvalidValue("compact prefix not declared")),
  )
  // concat_vocab 已落码（③批）：@vocab 未声明 = Err 非静默拼接——烟雾活账翻转
  assert_true(
    IriExpander::concat_vocab(e, active, "t")
    is Err(InvalidValue("@vocab not declared")),
  )
  // resolve_base 已落码（②批）：无 base = 相对值原样保留（value 位语义）——烟雾活账翻转
  assert_true(IriExpander::resolve_base(e, active, "t") is Ok("t"))
  assert_true(IriExpander::lookup_term(e, active, "t") is Err(Unsupported(_)))
}

///|
/// #t0045 方法级对拍：@value 词形保留 + @language 键序无关合并 + 顶层值对象丢弃
test "value object family batch 1 (#t0045 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document("{\"@value\": \"free-floating value\"}", options)
    is Ok(Array([])),
  )
  assert_true(
    expand_document("{\"@language\": \"en\", \"@value\": \"hi\"}", options)
    is Ok(Array([])),
  )
}

///|
/// ②批对拍：构造 context（terms 手工填充，不处理 @context 声明）下的
/// IRI 分拣链——term 精确 / compact / absolute / bnode / value 位原样
test "term/IRI chain with constructed context (②批对拍)" {
  let e = StandardExpander::{ }
  let terms : Map[String, TermDefinition] = Map([])
  terms["ex"] = TermDefinition::{
    iri: Some("http://example.com/"),
    datatype: None,
    container: None,
    reverse: None,
    local_context: None,
    context_base_url: None,
    is_protected: false,
    index_mapping: None,
    graph_secondary: None,
    language_mapping: None,
    direction_mapping: None,
    is_prefix: None,
    nest: None,
    simple_form: true,
  graph_set: false,
  }
  terms["name"] = TermDefinition::{
    iri: Some("http://example.com/name"),
    datatype: None,
    container: None,
    reverse: None,
    local_context: None,
    context_base_url: None,
    is_protected: false,
    index_mapping: None,
    graph_secondary: None,
    language_mapping: None,
    direction_mapping: None,
    is_prefix: None,
    nest: None,
    simple_form: true,
  graph_set: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  // term 精确查表（lookup_term 真行为）
  assert_true(
    IriExpander::lookup_term(e, active, "name") is Ok("http://example.com/name"),
  )
  // 链：term 命中（vocab 位；#ter48 oracle：@id 位 vocab=false 不查表——本测为
  // 键位对拍，vocab=true）
  assert_true(
    IriExpander::expand_iri(e, active, "name", false, true)
    is Ok("http://example.com/name"),
  )
  // 链：compact（prefix 已声明）
  assert_true(
    IriExpander::expand_iri(e, active, "ex:name", false, false)
    is Ok("http://example.com/name"),
  )
  assert_true(
    IriExpander::expand_compact(e, active, "ex:name", false, true)
    is Ok("http://example.com/name"),
  )
  // 链：未声明前缀 + 合法 scheme → absolute 原样（非 compact 非错误）
  assert_true(
    IriExpander::expand_iri(e, active, "other:x", false, false) is Ok("other:x"),
  )
  // 链：bnode 原样
  assert_true(
    IriExpander::expand_iri(e, active, "_:b0", false, false) is Ok("_:b0"),
  )
  // 链：无 vocab 无 base 无 term → 原样（value 位行为）
  assert_true(
    IriExpander::expand_iri(e, active, "plain", false, false) is Ok("plain"),
  )
}

///|
/// ②批对拍：base 相对解析（resolve_base 真行为 + 链行为）
test "base-relative resolution (②批对拍)" {
  let e = StandardExpander::{ }
  let terms : Map[String, TermDefinition] = Map([])
  let based = ActiveContext::{
    base: Some("http://example.org/"),
    vocab: None,
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  assert_true(
    IriExpander::resolve_base(e, based, "zzz") is Ok("http://example.org/zzz"),
  )
  // document-relative 位（docRel=true）才落 base merge——vocab 位键展开
  // docRel=false 原样返回（「vocab 位 base 门控批」#t0003 oracle）
  assert_true(
    IriExpander::expand_iri(e, based, "zzz", true, false)
    is Ok("http://example.org/zzz"),
  )
  assert_true(
    IriExpander::expand_iri(e, based, "zzz", false, false) is Ok("zzz"),
  )
}

///|
/// ②批对拍：属性键路由经链（term 键 → 定义 IRI）
test "property key routing via chain (②批)" {
  let e = StandardExpander::{ }
  let terms : Map[String, TermDefinition] = Map([])
  terms["name"] = TermDefinition::{
    iri: Some("http://example.com/name"),
    datatype: None,
    container: None,
    reverse: None,
    local_context: None,
    context_base_url: None,
    is_protected: false,
    index_mapping: None,
    graph_secondary: None,
    language_mapping: None,
    direction_mapping: None,
    is_prefix: None,
    nest: None,
    simple_form: true,
  graph_set: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let doc = match parse_json("{\"name\": \"hi\"}") {
    Ok(doc) => doc
    Err(_) => fail("parse failed")
  }
  match StandardExpander::expand_object(e, active, doc, None, options) {
    Ok(Some(ExpandedValue::Node(node))) => {
      assert_eq(node.properties.length(), 1)
      assert_eq(node.properties[0].0, "http://example.com/name")
      assert_eq(node.properties[0].1.length(), 1)
    }
    _ => fail("expected node with routed property")
  }
}

///|
/// concat_vocab 挂③断言（②批边界钉：ActiveContext 无 @vocab 字段）
test "concat_vocab stays unsupported until @context batch" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  // concat_vocab 已落码（③批）：@vocab 未声明 = Err 非静默拼接——烟雾活账翻转
  assert_true(
    IriExpander::concat_vocab(e, active, "t")
    is Err(InvalidValue("@vocab not declared")),
  )
}

///|
/// ③批对拍：内嵌 @context（simple term 声明）端到端
test "@context simple term declaration end-to-end (③批对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document(
      "{\"@context\": {\"name\": \"http://example.com/name\"}, \"name\": \"hi\"}",
      options,
    )
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.com/name",
                Array([Object([("@value", String("hi"))])]),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @nest 合并索引化对拍（顺序语义不变钉）：同键逐值追加、异键按**首见序**占位。
/// 两条 nest 条目交叉给出 {a,b} 与 {b,a} ⟹ 结果 a→[1,4]、b→[2,3]，键序 a,b
test "@nest indexed merge keeps order semantics (tn006/tn008 同族对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"ex:\", \"n\": \"@nest\"}, \"n\": [{\"a\": \"1\", \"b\": \"2\"}, {\"b\": \"3\", \"a\": \"4\"}]}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "ex:a",
                Array(
                  [
                    Object([("@value", String("1"))]),
                    Object([("@value", String("4"))]),
                  ]
                ),
              ),
              (
                "ex:b",
                Array(
                  [
                    Object([("@value", String("2"))]),
                    Object([("@value", String("3"))]),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// ③批对拍：@vocab 声明端到端（无冒号键 → vocab 拼接）
test "@vocab declaration end-to-end (③批对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document(
      "{\"@context\": {\"@vocab\": \"http://example.com/\"}, \"name\": \"hi\"}",
      options,
    )
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.com/name",
                Array([Object([("@value", String("hi"))])]),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// ter48 调试探针（一次性）：expand_iri("term", vocab=false) 应不查表
test "debug ter48: vocab=false excludes term lookup" {
  let e = StandardExpander::{ }
  let terms : Map[String, TermDefinition] = Map([])
  terms["term"] = TermDefinition::{
    iri: Some("http://example.com/terms-are-not-considered-in-id"),
    datatype: None,
    container: None,
    reverse: None,
    local_context: None,
    context_base_url: None,
    is_protected: false,
    index_mapping: None,
    graph_secondary: None,
    language_mapping: None,
    direction_mapping: None,
    is_prefix: None,
    nest: None,
    simple_form: true,
  graph_set: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: Some("http://example.org/vocab-is-not-considered-for-id"),
    terms,
    previous: None,
    default_language: None,
    default_direction: None,
  }
  assert_true(
    IriExpander::expand_iri(e, active, "term", true, false) is Ok("term"),
  )
}

///|
/// ③批 @version 落码对拍：接受 json-ld-1.1 / 拒绝其他值
test "@version declaration (③批对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([("@version", JsonValue::String("json-ld-1.1"))])
  assert_true(
    ContextProcessor::process_context(
      e,
      active,
      ctx,
      ContextFlags::element(),
      options,
    )
    is Ok(_),
  )
}

///|
test "invalid @version rejected (③批对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([("@version", JsonValue::String("json-ld-1.2"))])
  match
    ContextProcessor::process_context(
      e,
      active,
      ctx,
      ContextFlags::element(),
      options,
    ) {
    Err(JsonLdError::InvalidContext(m)) =>
      assert_true(m.contains("invalid @version"))
    _ => fail("expected @version rejection")
  }
}

///|
/// merge 绝对路径引用对拍（#t0051 oracle："/" 开头引用 → authority 保留、
/// path 整体替换；相对引用仍截最后段——#t0129/#t0130 回归钉）
test "merge_base_reference absolute-path reference (t0051 对拍)" {
  assert_true(
    merge_base_reference(
      "https://w3c.github.io/json-ld-api/tests/expand/", "/issue/1",
    )
    is "https://w3c.github.io/issue/1",
  )
  assert_true(
    merge_base_reference("http://example/base", "/x") is "http://example/x",
  )
  // 无 authority 形态（链式相对 base，契约外输入）→ 落回相对合并截段分支，
  // 引用自带 "/" → 退化出双斜杠（仅此退化形态，正规 base 不经此路；
  // authority 感知边界后 = 截段 + 引用，旧魔数分支为追加）
  assert_true(merge_base_reference("a/b", "/c") is "a//c")
  // 相对引用回归钉
  assert_true(
    merge_base_reference("http://example", "relative-iri")
    is "http://example/relative-iri",
  )
  assert_true(
    merge_base_reference("http://example/base", "relative-iri")
    is "http://example/relative-iri",
  )
}

///|
/// ③细化对拍：简单 term 定义的值 IRI 展开（#t0072 oracle：重定义为自身时用 @vocab）
test "term value expands against in-progress vocab (t0072 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([
    ("@vocab", JsonValue::String("http://example.com/anotherVocab#")),
    ("term", JsonValue::String("term")),
  ])
  let built = match
    ContextProcessor::process_context(
      e,
      active,
      ctx,
      ContextFlags::element(),
      options,
    ) {
    Ok(built) => built
    Err(_) => fail("process failed")
  }
  match built.terms.get("term") {
    Some(td) =>
      assert_true(td.iri is Some("http://example.com/anotherVocab#term"))
    None => fail("term missing")
  }
}

///|
/// scoped-context 批对拍①（#tc037 oracle）：@nest 别名 term 的属性作用域
/// context 作用于其值——嵌套对象内的 "property" 按 scoped @vocab 展开
test "property-scoped context on @nest alias term (#tc037 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@version\": 1.1, \"@vocab\": \"http://example.org/\", \"nest\": {\"@id\": \"@nest\", \"@context\": {\"@vocab\": \"http://example.org/nest/\"}}}, \"nest\": {\"property\": \"should be in /nest\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.org/nest/property",
                Array([Object([("@value", String("should be in /nest"))])]),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// scoped-context 批对拍②（#tin06 同族 oracle）：scoped context 的
/// {"term": null} = null IRI 映射——该键在作用域内**整体丢弃**，而非 vocab
/// 拼成属性、也非按 @nest 语义上浮（后者对串值会报 invalid @nest value）
test "scoped context nullifies term: key dropped (#tin06 同族对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"http://example.org/\", \"data\": \"@nest\", \"c\": {\"@context\": {\"data\": null}}}, \"c\": {\"data\": \"x\", \"keep\": \"y\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.org/c",
                Array(
                  [
                    Object(
                      [
                        (
                          "http://example.org/keep",
                          Array([Object([("@value", String("y"))])]),
                        ),
                      ]
                    ),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// scoped-context 批对拍③（#tc033 oracle）：未使用的嵌入 context 仍须在
/// **定义期**校验——内层 term 无 @id 且无 @vocab → invalid IRI mapping，
/// 外层按 invalid scoped context 报错（REC 4.2.2 @context 臂）
test "unused embedded context still checked (#tc033 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@version\": 1.1, \"t1\": {\"@id\": \"ex:t1\", \"@context\": {\"t2\": {\"@context\": {\"type\": null}}}}}}"
  match expand_document(input, options) {
    Err(InvalidContext(_)) => ()
    Err(_) => fail("expected invalid scoped context")
    Ok(_) => fail("expected invalid scoped context")
  }
}

///|
/// type-scoped 批对拍①（#t0073 oracle）：元素级 @context 先于主键循环处理——
/// 文档中排在 @context **之前**的键亦须看到它
test "element @context applies regardless of position (#t0073 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"name\": \"x\", \"@context\": {\"name\": \"http://example.com/name\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.com/name",
                Array([Object([("@value", String("x"))])]),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// type-scoped 批对拍②（#tc009 oracle）：type-scoped context 作用于**该节点**，
/// **不跨新节点**（嵌套节点回退 previous——"term-scoped context 不跨新节点"）
test "type-scoped context does not propagate to nested node (#tc009 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"http://example/\", \"Foo\": {\"@context\": {\"baz\": {\"@type\": \"@vocab\"}}}}, \"@type\": \"Foo\", \"bar\": {\"baz\": \"buzz\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              ("@type", Array([String("http://example/Foo")])),
              (
                "http://example/bar",
                Array(
                  [
                    Object(
                      [
                        (
                          "http://example/baz",
                          Array([Object([("@value", String("buzz"))])]),
                        ),
                      ]
                    ),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// type-scoped 批对拍③（#tc015 同族 oracle）：单 @id 形值**不回退**——
/// type-scoped @base 对 {"@id": …} 单键值仍生效；多键嵌套节点回退 outer base
test "single-@id shaped value keeps type-scoped base (#tc015 同族对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: Some("http://example/base-base"),
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@base\": \"http://example/base-base\", \"@vocab\": \"http://example/\", \"Type\": {\"@context\": {\"@base\": \"http://example/typed-base\"}}}, \"p\": {\"@type\": \"Type\", \"single\": {\"@id\": \"#single-id\"}, \"nested\": {\"@id\": \"#nested-id\", \"foo\": \"bar\"}}}"
  let expanded = match expand_document(input, options) {
    Ok(value) => value
    Err(_) => fail("expected success")
  }
  let repr = "\{expanded.to_repr()}"
  assert_true(repr.contains("http://example/typed-base#single-id"))
  assert_true(repr.contains("http://example/base-base#nested-id"))
}

///|
/// type-scoped 批对拍④（#tc029/#tc030 oracle）：@propagate 校验——
/// 非布尔 → invalid @propagate value；1.0 模式 → invalid context entry
test "@propagate must be boolean and 1.1-only (#tc029/#tc030 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
  }
  let options_11 = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let bad = JsonValue::Object([("@propagate", JsonValue::String("yes"))])
  match
    ContextProcessor::process_context(
      e,
      active,
      bad,
      ContextFlags::element(),
      options_11,
    ) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid @propagate value"))
    _ => fail("expected invalid @propagate value")
  }
  let options_10 = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd10,
  }
  let flag = JsonValue::Object([("@propagate", JsonValue::Bool(true))])
  match
    ContextProcessor::process_context(
      e,
      active,
      flag,
      ContextFlags::element(),
      options_10,
    ) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid context entry"))
    _ => fail("expected invalid context entry")
  }
}

///|
/// @protected 批对拍①（#pr23/#pr42 oracle）：等价重定义**允许且保留保护位**；
/// 不等价重定义 → protected term redefinition（判据看**旧定义**是否受保护）
test "protected term: equivalent redefinition keeps protection (#pr42 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  // 等价（同一 IRI）重定义 → 允许，保护位保留
  let equivalent = "{\"@context\": [{\"@protected\": true, \"p\": \"ex:p\"}, {\"p\": \"ex:p\"}, {\"p\": \"ex:q\"}]}"
  assert_true(expand_document(equivalent, options) is Err(InvalidContext(_)))
  let allowed = "{\"@context\": [{\"@protected\": true, \"p\": \"ex:p\"}, {\"p\": \"ex:p\"}], \"p\": \"x\"}"
  assert_true(expand_document(allowed, options) is Ok(_))
  // 除 protected 位外等价 ⇒ 允许（#pr27 oracle："same definition modulo protected flag"）
  let modulo_flag = "{\"@context\": [{\"@protected\": true, \"p\": \"ex:p\"}, {\"p\": {\"@id\": \"ex:p\", \"@protected\": false}}], \"p\": \"x\"}"
  assert_true(expand_document(modulo_flag, options) is Ok(_))
}

///|
/// @protected 批对拍②（#pr17 vs #pr06 oracle）：override protected 的**面**差异——
/// type-scoped 应用不传（默认 false）⇒ 空化保护 term 即错；property-scoped 面传
/// true ⇒ 同一空化形态允许
test "override protected faces: type-scoped vs property-scoped (#pr17/#pr06 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let type_scoped = "{\"@context\": {\"@vocab\": \"ex:\", \"@protected\": true, \"Foo\": {\"@context\": [null]}}, \"@type\": \"Foo\", \"p\": \"x\"}"
  match expand_document(type_scoped, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid context nullification"))
    _ => fail("expected invalid context nullification")
  }
  let property_scoped = "{\"@context\": {\"@protected\": true, \"p\": {\"@id\": \"ex:p\", \"@context\": null}}, \"p\": \"x\"}"
  assert_true(expand_document(property_scoped, options) is Ok(_))
}

///|
/// @protected 批对拍③（td 键面）：未知键 → invalid term definition（REC 键白名单）；
/// 未落码键（@index/@direction）→ Unsupported（落码活账，禁静默忽略）
test "td unknown key vs unimplemented key (#ter56 同族对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let unknown = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"bogus\": 1}}}"
  match expand_document(unknown, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid term definition"))
    _ => fail("expected invalid term definition")
  }
  // @index mapping 已落码（@index mapping 批）：容器不含 @index ⇒ invalid term definition
  let index_without_container = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"@index\": \"i\"}}}"
  match expand_document(index_without_container, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid term definition"))
    _ => fail("expected invalid term definition")
  }
  // @direction 已落码（丙批）：合法 ltr 接受；非法值 → invalid base direction
  let direction_ok = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"@direction\": \"ltr\"}}}"
  assert_true(expand_document(direction_ok, options) is Ok(_))
  let direction_bad = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"@direction\": \"sideways\"}}}"
  match expand_document(direction_bad, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid base direction"))
    _ => fail("expected invalid base direction")
  }
}

///|
/// @container 映射批对拍①（#tm003/#tm017 oracle）：type map = 键按 vocab 展开为
/// @type **前插**；值层字符串经**隐式 @id** type mapping 成节点引用
test "type map: prepend @type + implicit @id mapping (#tm003/#tm017 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: Some("http://example.org/base/"),
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"http://example.org/ns/\", \"@base\": \"http://example.org/base/\", \"foo\": {\"@container\": \"@type\"}}, \"foo\": {\"bar\": \"baz\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example.org/ns/foo",
                Array(
                  [
                    Object(
                      [
                        ("@id", String("http://example.org/base/baz")),
                        ("@type", Array([String("http://example.org/ns/bar")])),
                      ]
                    ),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @container 映射批对拍②（#tc013 同族 oracle）：index map = 条目无 @index 时写入
/// **原始索引键**；值为对象按常规展开
test "index map: writes @index from map key (#tc013 同族对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"http://example/\", \"idx\": {\"@container\": \"@index\"}}, \"idx\": {\"k\": {\"@id\": \"ex:i\"}}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example/idx",
                Array(
                  [Object([("@id", String("ex:i")), ("@index", String("k"))])]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @container 映射批对拍③（#tm020 oracle）：容器含 @type 时 type mapping 只允许
/// @id/@vocab（显式其它值 → invalid type mapping）
test "container @type restricts type mapping to @id/@vocab (#tm020 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let bad = "{\"@context\": {\"foo\": {\"@type\": \"literal\", \"@container\": \"@type\"}}, \"foo\": {}}"
  match expand_document(bad, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid type mapping"))
    _ => fail("expected invalid type mapping")
  }
  let vocab_ok = "{\"@context\": {\"@vocab\": \"ex:\", \"foo\": {\"@type\": \"@vocab\", \"@container\": \"@type\"}}, \"foo\": {\"bar\": \"baz\"}}"
  assert_true(expand_document(vocab_ok, options) is Ok(_))
}

///|
/// @id 容器 + language map 批对拍①（#tm001/#tm002/#tm005 oracle）：id map——
/// 条目无 @id ⇒ 写**document-relative**展开的索引；已有 @id 保留
test "id map: writes document-relative @id, keeps existing (#tm001/#tm005 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: Some("http://example.org/"),
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@vocab\": \"http://example/\", \"idmap\": {\"@container\": \"@id\"}}, \"idmap\": {\"foo\": {\"label\": \"x\"}, \"http://example.org/bar\": {\"@id\": \"http://example.org/baz\"}}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "http://example/idmap",
                Array(
                  [
                    Object(
                      [
                        ("@id", String("http://example.org/foo")),
                        (
                          "http://example/label",
                          Array([Object([("@value", String("x"))])]),
                        ),
                      ]
                    ),
                    Object([("@id", String("http://example.org/baz"))]),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @id 容器 + language map 批对拍②（#tm009/#tm010/#tl001 oracle）：language map——
/// 语言键非 @none（含**别名**）加 @language；条目值与数组内 null 跳过
test "language map: @none alias and null skip (#tm010/#tl001 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"vocab\": \"ex:v/\", \"label\": {\"@id\": \"ex:v/label\", \"@container\": \"@language\"}, \"none\": \"@none\"}, \"label\": {\"en\": \"The Queen\", \"none\": null, \"de\": [\"K\", null]}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "ex:v/label",
                Array(
                  [
                    Object(
                      [
                        ("@value", String("The Queen")),
                        ("@language", String("en")),
                      ]
                    ),
                    Object(
                      [("@value", String("K")), ("@language", String("de"))]
                    ),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @id 容器 + language map 批对拍③（#t0040 oracle）：容器为 map 类但**值非 map**
/// ⇒ 落通用分支；数组逐项按元素语义展开（**不重入容器壳**——否则 `{"@id": …}`
/// 项会被误当索引键条目）
test "map container with array value falls through per element (#t0040 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: Some("http://example.com/base/"),
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"indexes\": {\"@id\": \"ex:index\", \"@container\": \"@index\"}}, \"indexes\": [\"No\", {\"@id\": \"isn\"}]}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              (
                "ex:index",
                Array(
                  [
                    Object([("@value", String("No"))]),
                    Object([("@id", String("http://example.com/base/isn"))]),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @index mapping 批对拍①（#tpi06/#tpi07/#tpi10 oracle）：index key ≠ @index ⇒
/// 索引键写成**一条属性**（值 = 索引，追加在既有值之前）；`@none` 条目不写属性
test "index mapping: index written as property, appended before existing (#tpi 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: Some("http://example.com/"),
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"@version\": 1.1, \"@base\": \"http://example.com/\", \"@vocab\": \"http://example.com/\", \"author\": {\"@type\": \"@id\", \"@container\": \"@index\", \"@index\": \"prop\"}}, \"@id\": \"article\", \"author\": {\"regular\": \"person/1\", \"@none\": \"person/9\"}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              ("@id", String("http://example.com/article")),
              (
                "http://example.com/author",
                Array(
                  [
                    Object(
                      [
                        ("@id", String("http://example.com/person/1")),
                        (
                          "http://example.com/prop",
                          Array([Object([("@value", String("regular"))])]),
                        ),
                      ]
                    ),
                    Object([("@id", String("http://example.com/person/9"))]),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// @index mapping 批对拍②（#tpi01/#tpi03/#tpi04/#tpi05 oracle）：索引映射校验——
/// 1.0 / 非串 / 展开非 IRI → invalid term definition；值对象条目加索引属性 →
/// invalid value object
test "index mapping validation + value object rejection (#tpi 负例对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let keyword_value = "{\"@context\": {\"@version\": 1.1, \"p\": {\"@id\": \"ex:p\", \"@container\": \"@index\", \"@index\": \"@id\"}}}"
  match expand_document(keyword_value, options) {
    Err(InvalidContext(message)) =>
      assert_true(message.contains("invalid term definition"))
    _ => fail("expected invalid term definition")
  }
  let not_a_string = "{\"@context\": {\"@version\": 1.1, \"p\": {\"@id\": \"ex:p\", \"@container\": \"@index\", \"@index\": 7}}}"
  assert_true(expand_document(not_a_string, options) is Err(InvalidContext(_)))
  let options_10 = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd10,
  }
  let in_10 = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"@container\": \"@index\", \"@index\": \"q\"}}}"
  assert_true(expand_document(in_10, options_10) is Err(InvalidContext(_)))
  let value_object = "{\"@context\": {\"@version\": 1.1, \"@vocab\": \"ex:\", \"p\": {\"@container\": \"@index\", \"@index\": \"q\"}}, \"p\": {\"k\": {\"@value\": \"v\"}}}"
  match expand_document(value_object, options) {
    Err(InvalidValue(message)) =>
      assert_true(message.contains("invalid value object"))
    _ => fail("expected invalid value object")
  }
}

///|
/// @index mapping 批对拍③（#t0063/#t0131 oracle）：reverse 项**允许** @set/@index
/// 容器（白名单放宽）；**reverse-bearing 节点不是自由浮动**（仅 @reverse 的根节点保留）
test "reverse term with index container keeps reverse-only node (#t0063/#t0131 对拍)" {
  let options = JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let input = "{\"@context\": {\"isKnownBy\": {\"@reverse\": \"ex:knows\", \"@container\": \"@index\"}}, \"@id\": \"ex:me\", \"isKnownBy\": {\"Dave\": {\"@id\": \"ex:dave\"}}}"
  assert_true(
    expand_document(input, options)
    is Ok(
      Array(
        [
          Object(
            [
              ("@id", String("ex:me")),
              (
                "@reverse",
                Object(
                  [
                    (
                      "ex:knows",
                      Array(
                        [
                          Object(
                            [
                              ("@id", String("ex:dave")),
                              ("@index", String("Dave")),
                            ]
                          ),
                        ]
                      ),
                    ),
                  ]
                ),
              ),
            ]
          ),
        ]
      )
    ),
  )
}

///|
/// B组边界钉：merge_base_reference 三形臂位（spec §IRI 解析实现边界）——
/// 短 scheme 角（套件不可达）经 authority 感知边界后仍走目录替换臂
///（RFC 5.2.3：base.path 截最后 "/" 含 + 引用）
test "merge_base_reference short-scheme authority-aware boundary" {
  // 短 scheme + authority + 路径：截段（曾误走补根臂 idx>6 魔数）
  assert_eq(merge_base_reference("a://b/c", "d"), "a://b/d")
  // scheme-only 带路径：目录替换
  assert_eq(merge_base_reference("ex:/a", "b"), "ex:/b")
  // authority 形 path 空：补根（#t0129 oracle 保持）
  assert_eq(merge_base_reference("http://a", "g"), "http://a/g")
  // scheme-only 全串无 "/"：整段替换（#t0130/#tli11 oracle）
  assert_eq(merge_base_reference("tag:example", "a"), "tag:a")
  assert_eq(merge_base_reference("ex:", "test"), "ex:test")
  // scheme-only 多段：截最后 "/"（#t0131/#t0132 oracle 保持）
  assert_eq(merge_base_reference("tag:example/foo", "a"), "tag:example/a")
  assert_eq(merge_base_reference("tag:example/foo/", "a"), "tag:example/foo/a")
}

///|
/// C组成分门钉：nq_iri_chars_legal fragment 位判别（#te111/#te112 oracle——
/// spec 附录 IRI 正则 fragment 内不容第二 "#"；B组②平面门在其上）
test "nq_iri_chars_legal fragment component gate" {
  // fragment 位第二 "#" 非法 → 弃（te111 #fragment-works 键）
  assert_true(
    !nq_iri_chars_legal("http://example.com/vocabulary/./rel2##fragment-works"),
  )
  // fragment 位 "?" 与 "/" 合法 → 留
  assert_true(
    nq_iri_chars_legal("http://example.com/vocabulary/./rel2#?query=works"),
  )
  assert_true(
    nq_iri_chars_legal("http://example.com/vocabulary/./rel2#../parent"),
  )
  // 平面门：文法外字符弃（tli12）
  assert_true(!nq_iri_chars_legal("http://invalid/<>/test"))
}

///|
/// J3.2 数值典范形判定钉（REC §6.4）：整形判据=值整+|v|<1e21，非词面 e 有无；
/// 整数形无前导零/-0 归 "0"；double 形首位+.尾（个位保 .0）、E 后无 +/前导零。
test "nq_canonical_number canonical form pinning" {
  // 整数形（lexical 无 e 且值整）
  assert_eq(nq_canonical_number("42", false).0, "42")
  assert_true(!nq_canonical_number("42", false).1)
  assert_eq(nq_canonical_number("007", false).0, "7") // 前导零剥除
  assert_eq(nq_canonical_number("1.0", false).0, "1") // 值整→整数形
  assert_eq(nq_canonical_number("-0e0", false).0, "0") // trt01 oracle：-0 归 "0"
  // 1e21 边界：shift ≥ 21 → double 形（t0022 oracle）
  assert_eq(nq_canonical_number("1e21", false), ("1.0E21", true))
  // double 形：首位+.尾，个位保 .0；E 后无 +/前导零
  assert_eq(nq_canonical_number("1.5", false), ("1.5E0", true))
  assert_eq(nq_canonical_number("123.45", false), ("1.2345E2", true))
  assert_eq(nq_canonical_number("0.5", false), ("5.0E-1", true))
  // datatype 强制：xsd:double 面上整值也走 double 形（te061）
  assert_eq(nq_canonical_number("1", true), ("1.0E0", true))
  assert_eq(nq_canonical_number("0", true), ("0.0E0", true))
}
