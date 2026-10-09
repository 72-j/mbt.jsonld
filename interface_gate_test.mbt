///|
/// 接口一致门（对账红线第一件：骨架 handler ↔ 手写 trait 方法逐一对应）。
/// 拦截两类漂移：① 生成面 handler 指向未声明的 trait/方法；② trait 方法改名后生成面未同步。
/// 机制：mock 全实现四 trait（`with` 形逐条，编译器钉住 trait 声明面）+
/// table_handlers 清单与生成面 handler 集合双向对表（多一少一即红）。
/// 生成面增删 ⇒ 同笔补 mock 分支 + 本清单（生成物 ≡ 源表由外层黄金门把关）。

///|
/// 表引用的全部 handler 方法名（与 mock 实现面一致）
let table_handlers : Array[String] = [
  // [[steps]].handler_hook
  "expand_value", "expand_array", "postprocess_value", "node_to_quads",
  // [[keyword_dispatch]].handler_hook
   "expand_iri", "set_language", "set_direction", "expand_list", "expand_set", "expand_graph",
  "expand_reverse", "expand_nest", "expand_included", "set_index", "process_context",
  "expand_term",
  // [[iri_rules]].handler_hook
   "handle_keyword", "expand_compact", "concat_vocab", "resolve_base", "lookup_term",
]

///|
/// handler 所属 trait 白名单
let trait_whitelist : Array[String] = [
  "Expander", "IriExpander", "ContextProcessor", "ToRdfProcessor",
]

///|
/// mock 统一失败体
fn[T] mock_err() -> Result[T, @jsonld.JsonLdError] {
  Err(@jsonld.JsonLdError::Unsupported("interface gate mock"))
}

///|
/// mock 载体（空结构体；trait 面由下方 with 形逐条实现）
struct MockHooks {}

///|
/// Expander 全量 mock（with 形逐条实现）
impl @jsonld.Expander for MockHooks with fn expand_element(
  _self,
  _active,
  _element,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_value(
  _self,
  _active,
  _value,
  _active_property,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_array(
  _self,
  _active,
  _items,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_term(
  _self,
  _active,
  _term,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn postprocess_value(
  _self,
  _active,
  _value,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn set_language(_self, _active, _value) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn set_direction(
  _self,
  _active,
  _value,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_list(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_set(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_graph(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_reverse(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_nest(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn expand_included(
  _self,
  _active,
  _value,
  _active_property,
  _options,
) {
  mock_err()
}

///|
impl @jsonld.Expander for MockHooks with fn set_index(_self, _active, _value) {
  mock_err()
}

///|
/// IriExpander 全量 mock（with 形逐条实现）
impl @jsonld.IriExpander for MockHooks with fn expand_iri(
  _self,
  _active,
  _value,
  _document_relative,
  _vocab,
) {
  mock_err()
}

///|
impl @jsonld.IriExpander for MockHooks with fn handle_keyword(_self, _value) {
  mock_err()
}

///|
impl @jsonld.IriExpander for MockHooks with fn expand_compact(
  _self,
  _active,
  _value,
  _document_relative,
  _vocab,
) {
  mock_err()
}

///|
impl @jsonld.IriExpander for MockHooks with fn concat_vocab(
  _self,
  _active,
  _value,
) {
  mock_err()
}

///|
impl @jsonld.IriExpander for MockHooks with fn resolve_base(
  _self,
  _active,
  _value,
) {
  mock_err()
}

///|
impl @jsonld.IriExpander for MockHooks with fn lookup_term(
  _self,
  _active,
  _value,
) {
  mock_err()
}

///|
/// ContextProcessor 全量 mock（with 形逐条实现）
impl @jsonld.ContextProcessor for MockHooks with fn process_context(
  _self,
  _active,
  _local_context,
  _flags,
  _options,
) {
  mock_err()
}

///|
/// ToRdfProcessor 全量 mock（with 形逐条实现）
impl @jsonld.ToRdfProcessor for MockHooks with fn node_to_quads(
  _self,
  _expanded,
  _options,
) {
  mock_err()
}

///|
/// 生成面全量步骤（JsonLdStep 变体；生成物每加一步须同笔补此处 —— 与 table_handlers 同款双录）
fn all_jsonld_steps() -> Array[@jsonld.JsonLdStep] {
  [
    @jsonld.JsonLdStep::ExpansionEntry,
    @jsonld.JsonLdStep::ExpansionExpandValue,
    @jsonld.JsonLdStep::ExpansionExpandArray,
    @jsonld.JsonLdStep::ExpansionExpandObject,
    @jsonld.JsonLdStep::ExpansionPostprocess,
    @jsonld.JsonLdStep::TorfEntry,
    @jsonld.JsonLdStep::TorfEmit,
  ]
}

///|
/// 门体：生成面 handler 集合 ⟷ mock 面（table_handlers）双向对表。
/// 数据源 = 编译后的生成模块 pub 面（JsonLdStep::handler / jsonld_keyword_routes()
/// / jsonld_iri_routes()）；该生成物 ≡ 源表（jsonld_gen.toml）由**外层**黄金门
/// 逐字节把关，故本门不再直读 toml —— 本仓据此去除对 `thy1016/bitbang/skelgen` 的依赖。
async test "interface gate: every generated handler resolves to a declared trait method" {
  let hooks : Array[String?] = []
  for step in all_jsonld_steps() {
    hooks.push(step.handler())
  }
  for row in @jsonld.jsonld_keyword_routes() {
    hooks.push(row.handler)
  }
  for row in @jsonld.jsonld_iri_routes() {
    hooks.push(row.handler)
  }
  let seen : Map[String, Int] = Map([])
  for hook in hooks {
    match hook {
      Some(h) =>
        match h.split("::").to_array() {
          [trait_name, handler_method] => {
            assert_true(trait_whitelist.contains(trait_name.to_owned()))
            seen[handler_method.to_owned()] = 1
          }
          _ => fail("handler must be Trait::method: \{h}")
        }
      None => ()
    }
  }
  // 双向对表：生成面引用集合 == mock 面（多一少一即红）
  assert_eq(seen.length(), table_handlers.length())
  for handler_method in table_handlers {
    assert_true(seen.contains(handler_method))
  }
}

///|
/// mock 可用性烟雾：四 trait 各调一法，命中 Unsupported 即通过（impl 非死码）
async test "interface gate smoke: mock surface is callable" {
  let mock = MockHooks::{ }
  let active = @jsonld.ActiveContext::{
    base: None,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
    compact_by_iri: None,
    compact_reverse: None,
    compact_prefixes: None,
  }
  let options = @jsonld.JsonLdOptions::{
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    base: None,
    expand_context: None,
    processing_mode: @jsonld.ProcessingMode::JsonLd11,
    use_native_types: false,
    use_rdf_type: false,
  }
  match @jsonld.Expander::set_language(mock, active, @jsonld.JsonValue::Null) {
    Err(@jsonld.JsonLdError::Unsupported(_)) => ()
    _ => fail("expected Unsupported")
  }
  match @jsonld.IriExpander::handle_keyword(mock, "@id") {
    Err(@jsonld.JsonLdError::Unsupported(_)) => ()
    _ => fail("expected Unsupported")
  }
  match
    @jsonld.ContextProcessor::process_context(
      mock,
      active,
      @jsonld.JsonValue::Null,
      @jsonld.ContextFlags::element(),
      options,
    ) {
    Err(@jsonld.JsonLdError::Unsupported(_)) => ()
    _ => fail("expected Unsupported")
  }
  match @jsonld.ToRdfProcessor::node_to_quads(mock, [], options) {
    Err(@jsonld.JsonLdError::Unsupported(_)) => ()
    _ => fail("expected Unsupported")
  }
}

///|
/// 役C3 移防②（gen.mbt 35/55/57）：生成面步进表直调钉——next_step 全变体
/// 邻接契约 + dispatch 形状白名单外 / 非入口步两兜底臂。next_step 生产面
/// 零调用（调度走 dispatch），生成物契约面直调保活
test "gen surface: next_step table + dispatch fallback arms (35/55/57)" {
  let expect_next : Array[String] = [
    "", "expansion.postprocess", "expansion.postprocess", "expansion.postprocess",
    "", "torf.emit", "",
  ]
  let steps = all_jsonld_steps()
  for i in 0..<steps.length() {
    match steps[i].next_step() {
      Some(next) => assert_eq(next.id(), expect_next[i])
      None => assert_eq(expect_next[i], "")
    }
  }
  // dispatch 形状白名单 {scalar,array,object} 外 → None（55）
  assert_true(@jsonld.JsonLdStep::ExpansionEntry.dispatch("weird") is None)
  // 非入口步（分派仅 ExpansionEntry 声明）→ None（57）
  assert_true(
    @jsonld.JsonLdStep::ExpansionPostprocess.dispatch("scalar") is None,
  )
}
