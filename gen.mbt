// ===== GENERATED FILE — DO NOT EDIT（生成物禁手写，世界宪法 §4.1）=====
// 源表：skelgen/jsonld_gen/jsonld_gen.toml（schema 1.0）
// 再生：moon run skelgen/jsonld_gen/cmd（改表 → 重跑 → 黄金门对拍）
// 绑定器：skelgen/jsonld_toml_gen.mbt（parse / validate / emit）

///|
/// 步骤表全量枚举（[[steps]]）
pub(all) enum JsonLdStep {
  ExpansionEntry
  ExpansionExpandValue
  ExpansionExpandArray
  ExpansionExpandObject
  ExpansionPostprocess
  TorfEntry
  TorfEmit
}

///|
/// 步骤 id（账面对照用）
pub fn JsonLdStep::id(self : JsonLdStep) -> String {
  match self {
    ExpansionEntry => "expansion.entry"
    ExpansionExpandValue => "expansion.expand_value"
    ExpansionExpandArray => "expansion.expand_array"
    ExpansionExpandObject => "expansion.expand_object"
    ExpansionPostprocess => "expansion.postprocess"
    TorfEntry => "torf.entry"
    TorfEmit => "torf.emit"
  }
}

///|
/// next 边（[[steps]].next；缺省 = 本阶段终点）
pub fn JsonLdStep::next_step(self : JsonLdStep) -> JsonLdStep? {
  match self {
    ExpansionEntry => None
    ExpansionExpandValue => Some(ExpansionPostprocess)
    ExpansionExpandArray => Some(ExpansionPostprocess)
    ExpansionExpandObject => Some(ExpansionPostprocess)
    ExpansionPostprocess => None
    TorfEntry => Some(TorfEmit)
    TorfEmit => None
  }
}

///|
/// 形态分派（[[steps]].dispatch；词表 scalar/array/object；未声明步 → None）
pub fn JsonLdStep::dispatch(self : JsonLdStep, shape : String) -> JsonLdStep? {
  match self {
    ExpansionEntry =>
      match shape {
        "scalar" => Some(ExpansionExpandValue)
        "array" => Some(ExpansionExpandArray)
        "object" => Some(ExpansionExpandObject)
        _ => None
      }
    _ => None
  }
}

///|
/// 步骤手写落点（[[steps]].handler_hook；None = 无手写，调度直通）
pub fn JsonLdStep::handler(self : JsonLdStep) -> String? {
  match self {
    ExpansionEntry => None
    ExpansionExpandValue => Some("Expander::expand_value")
    ExpansionExpandArray => Some("Expander::expand_array")
    ExpansionExpandObject => None
    ExpansionPostprocess => Some("Expander::postprocess_value")
    TorfEntry => Some("ToRdfProcessor::node_to_quads")
    TorfEmit => None
  }
}

///|
/// 关键字路由行（[[keyword_dispatch]]；condition/result 为可枚举词表）
pub(all) struct JsonLdKeywordRoute {
  keyword : String
  condition : String
  action : String
  result : String
  args_vocab : Bool?
  args_document_relative : Bool?
  handler : String?
}

///|
/// 关键字路由（未知键落缺省臂 _term；表无缺省臂时返回 None）
pub fn jsonld_keyword_route(keyword : String) -> JsonLdKeywordRoute? {
  match keyword {
    "@id" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@id",
        condition: "string",
        action: "expand_iri",
        result: "iri",
        args_vocab: Some(false),
        args_document_relative: Some(true),
        handler: Some("IriExpander::expand_iri"),
      })
    "@type" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@type",
        condition: "string_or_string_array",
        action: "expand_iri",
        result: "iri",
        args_vocab: Some(true),
        args_document_relative: Some(false),
        handler: Some("IriExpander::expand_iri"),
      })
    "@value" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@value",
        condition: "scalar_or_null",
        action: "expand_value",
        result: "value_object",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_value"),
      })
    "@language" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@language",
        condition: "string",
        action: "set_language",
        result: "value_object",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::set_language"),
      })
    "@direction" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@direction",
        condition: "ltr_or_rtl",
        action: "set_direction",
        result: "value_object",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::set_direction"),
      })
    "@list" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@list",
        condition: "array_or_object",
        action: "expand_list",
        result: "list_object",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_list"),
      })
    "@set" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@set",
        condition: "any",
        action: "expand_set",
        result: "array",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_set"),
      })
    "@graph" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@graph",
        condition: "any",
        action: "expand_graph",
        result: "graph",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_graph"),
      })
    "@reverse" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@reverse",
        condition: "object",
        action: "expand_reverse",
        result: "property",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_reverse"),
      })
    "@nest" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@nest",
        condition: "object",
        action: "expand_nest",
        result: "property",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_nest"),
      })
    "@included" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@included",
        condition: "object_or_array",
        action: "expand_included",
        result: "array",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_included"),
      })
    "@index" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@index",
        condition: "string",
        action: "set_index",
        result: "index",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::set_index"),
      })
    "@context" =>
      Some(JsonLdKeywordRoute::{
        keyword: "@context",
        condition: "object_or_array",
        action: "process_context",
        result: "context",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("ContextProcessor::process_context"),
      })
    _ =>
      Some(JsonLdKeywordRoute::{
        keyword: "_term",
        condition: "default",
        action: "expand_term",
        result: "property",
        args_vocab: None,
        args_document_relative: None,
        handler: Some("Expander::expand_term"),
      })
  }
}

///|
/// 关键字路由全表（表序；覆盖门用）
pub fn jsonld_keyword_routes() -> Array[JsonLdKeywordRoute] {
  [
    JsonLdKeywordRoute::{
      keyword: "@id",
      condition: "string",
      action: "expand_iri",
      result: "iri",
      args_vocab: Some(false),
      args_document_relative: Some(true),
      handler: Some("IriExpander::expand_iri"),
    },
    JsonLdKeywordRoute::{
      keyword: "@type",
      condition: "string_or_string_array",
      action: "expand_iri",
      result: "iri",
      args_vocab: Some(true),
      args_document_relative: Some(false),
      handler: Some("IriExpander::expand_iri"),
    },
    JsonLdKeywordRoute::{
      keyword: "@value",
      condition: "scalar_or_null",
      action: "expand_value",
      result: "value_object",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_value"),
    },
    JsonLdKeywordRoute::{
      keyword: "@language",
      condition: "string",
      action: "set_language",
      result: "value_object",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::set_language"),
    },
    JsonLdKeywordRoute::{
      keyword: "@direction",
      condition: "ltr_or_rtl",
      action: "set_direction",
      result: "value_object",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::set_direction"),
    },
    JsonLdKeywordRoute::{
      keyword: "@list",
      condition: "array_or_object",
      action: "expand_list",
      result: "list_object",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_list"),
    },
    JsonLdKeywordRoute::{
      keyword: "@set",
      condition: "any",
      action: "expand_set",
      result: "array",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_set"),
    },
    JsonLdKeywordRoute::{
      keyword: "@graph",
      condition: "any",
      action: "expand_graph",
      result: "graph",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_graph"),
    },
    JsonLdKeywordRoute::{
      keyword: "@reverse",
      condition: "object",
      action: "expand_reverse",
      result: "property",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_reverse"),
    },
    JsonLdKeywordRoute::{
      keyword: "@nest",
      condition: "object",
      action: "expand_nest",
      result: "property",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_nest"),
    },
    JsonLdKeywordRoute::{
      keyword: "@included",
      condition: "object_or_array",
      action: "expand_included",
      result: "array",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_included"),
    },
    JsonLdKeywordRoute::{
      keyword: "@index",
      condition: "string",
      action: "set_index",
      result: "index",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::set_index"),
    },
    JsonLdKeywordRoute::{
      keyword: "@context",
      condition: "object_or_array",
      action: "process_context",
      result: "context",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("ContextProcessor::process_context"),
    },
    JsonLdKeywordRoute::{
      keyword: "_term",
      condition: "default",
      action: "expand_term",
      result: "property",
      args_vocab: None,
      args_document_relative: None,
      handler: Some("Expander::expand_term"),
    },
  ]
}

///|
/// IRI 规则路由行（[[iri_rules]]；handler = None 的行走骨架缺省实现）
pub(all) struct JsonLdIriRoute {
  order : Int
  kind : String
  condition : String
  action : String
  handler : String?
}

///|
/// IRI 规则表（order 升序 = 求值顺序）
pub fn jsonld_iri_routes() -> Array[JsonLdIriRoute] {
  [
    JsonLdIriRoute::{
      order: 1,
      kind: "keyword",
      condition: "starts_with_at",
      action: "return_keyword",
      handler: Some("IriExpander::handle_keyword"),
    },
    JsonLdIriRoute::{
      order: 2,
      kind: "term",
      condition: "term_defined",
      action: "lookup_term",
      handler: Some("IriExpander::lookup_term"),
    },
    JsonLdIriRoute::{
      order: 3,
      kind: "bnode",
      condition: "is_bnode",
      action: "return_as_is",
      handler: None,
    },
    JsonLdIriRoute::{
      order: 4,
      kind: "compact",
      condition: "has_prefix",
      action: "expand_compact",
      handler: Some("IriExpander::expand_compact"),
    },
    JsonLdIriRoute::{
      order: 5,
      kind: "absolute",
      condition: "has_valid_scheme",
      action: "return_as_is",
      handler: None,
    },
    JsonLdIriRoute::{
      order: 6,
      kind: "vocab",
      condition: "vocab_base_set",
      action: "concat_vocab",
      handler: Some("IriExpander::concat_vocab"),
    },
    JsonLdIriRoute::{
      order: 7,
      kind: "relative",
      condition: "base_set",
      action: "resolve_base",
      handler: Some("IriExpander::resolve_base"),
    },
  ]
}
