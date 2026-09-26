///|
/// #t0001 方法级对拍：expand_iri 绝对 IRI 原样返回（@id 键的身份展开）

///|
test "expand_iri absolute passthrough (#t0001 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
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
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
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
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
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
  }
  terms["name"] = TermDefinition::{
    iri: Some("http://example.com/name"),
    datatype: None,
    container: None,
    reverse: None,
  }
  let active = ActiveContext::{ base: None, vocab: None, terms, }
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
  }
  let active = ActiveContext::{ base: None, vocab: None, terms, }
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
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
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
  }
  let active = ActiveContext::{
    base: None,
    vocab: Some("http://example.org/vocab-is-not-considered-for-id"),
    terms,
  }
  assert_true(
    IriExpander::expand_iri(e, active, "term", true, false) is Ok("term"),
  )
}

///|
/// ter48 端到端调试（一次性）：最小输入应 Err
test "debug ter48 e2e minimal (throwaway)" {
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document(
      "{\"@context\": {\"term\": \"http://example.com/terms-are-not-considered-in-id\"}, \"@id\": \"term\"}",
      options,
    )
    is Err(_),
  )
}

///|
/// ter48 完整输入调试（一次性）：与最小输入对照
test "debug ter48 full input (throwaway)" {
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  assert_true(
    expand_document(
      "{\"@context\": {\"term\": \"http://example.com/terms-are-not-considered-in-id\", \"compact-iris\": \"http://example.com/compact-iris#\", \"property\": \"http://example.com/property\", \"@vocab\": \"http://example.org/vocab-is-not-considered-for-id\"}, \"@id\": \"term\", \"property\": [{\"@id\": \"compact-iris:are-considered\", \"property\": \"a\"}]}",
      options,
    )
    is Err(_),
  )
}

///|
/// ③批 @version 落码对拍：接受 json-ld-1.1 / 拒绝其他值
test "@version declaration (③批对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([("@version", JsonValue::String("json-ld-1.1"))])
  assert_true(
    ContextProcessor::process_context(e, active, ctx, options) is Ok(_),
  )
}

///|
test "invalid @version rejected (③批对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([("@version", JsonValue::String("json-ld-1.2"))])
  match ContextProcessor::process_context(e, active, ctx, options) {
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
/// t0091 链路调试（一次性）
test "debug t0091 chain (throwaway)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let c1 = match parse_json("{\"@base\": \"http://foo.bar/./baz/\"}") {
    Ok(c) => c
    Err(_) => fail("c1")
  }
  let a1 = match ContextProcessor::process_context(e, active, c1, options) {
    Ok(a) => a
    Err(_) => fail("c1 process")
  }
  let c2 = match parse_json("{\"@base\": \"example/\"}") {
    Ok(c) => c
    Err(_) => fail("c2")
  }
  let a2 = match ContextProcessor::process_context(e, a1, c2, options) {
    Ok(a) => a
    Err(_) => fail("c2 process")
  }
  assert_true(a2.base is Some("http://foo.bar/baz/example/"))
}

///|
/// ③细化对拍：简单 term 定义的值 IRI 展开（#t0072 oracle：重定义为自身时用 @vocab）
test "term value expands against in-progress vocab (t0072 对拍)" {
  let e = StandardExpander::{ }
  let active = ActiveContext::{ base: None, vocab: None, terms: Map([]), }
  let options = JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
  }
  let ctx = JsonValue::Object([
    ("@vocab", JsonValue::String("http://example.com/anotherVocab#")),
    ("term", JsonValue::String("term")),
  ])
  let built = match ContextProcessor::process_context(e, active, ctx, options) {
    Ok(built) => built
    Err(_) => fail("process failed")
  }
  match built.terms.get("term") {
    Some(td) =>
      assert_true(td.iri is Some("http://example.com/anotherVocab#term"))
    None => fail("term missing")
  }
}
