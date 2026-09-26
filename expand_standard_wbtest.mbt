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
  }
  assert_true(
    IriExpander::expand_iri(e, active, "_:b0", true, false) is Ok("_:b0"),
  )
}

///|
/// #t0001 端到端：仅 @id 的顶层节点 → free-floating → []
test "t0001 end-to-end: drop free-floating node (#t0001 对拍)" {
  let options = JsonLdOptions::{
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
  }
  let options = JsonLdOptions::{
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
    is_protected: false,
  }
  terms["name"] = TermDefinition::{
    iri: Some("http://example.com/name"),
    datatype: None,
    container: None,
    reverse: None,
    local_context: None,
    is_protected: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms,
    previous: None,
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
    is_protected: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: None,
    terms,
    previous: None,
  }
  let options = JsonLdOptions::{
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
/// ③批对拍：@vocab 声明端到端（无冒号键 → vocab 拼接）
test "@vocab declaration end-to-end (③批对拍)" {
  let options = JsonLdOptions::{
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
    is_protected: false,
  }
  let active = ActiveContext::{
    base: None,
    vocab: Some("http://example.org/vocab-is-not-considered-for-id"),
    terms,
    previous: None,
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
  }
  let options = JsonLdOptions::{
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
  }
  let options = JsonLdOptions::{
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
  // 无 authority 形态（链式相对 base，契约外输入）→ 落回相对合并补根分支，
  // 引用自带 "/" → 退化出双斜杠（仅此退化形态，正规 base 不经此路）
  assert_true(merge_base_reference("a/b", "/c") is "a/b//c")
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
  }
  let options = JsonLdOptions::{
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
  }
  let options_11 = JsonLdOptions::{
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
  let unimplemented = "{\"@context\": {\"p\": {\"@id\": \"ex:p\", \"@index\": \"i\"}}}"
  assert_true(expand_document(unimplemented, options) is Err(Unsupported(_)))
}
