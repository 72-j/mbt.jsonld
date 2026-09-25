///|
/// IRI 展开接口
/// 契约面与 jsonld_gen.toml iri_rules / keyword_dispatch 的 handler 一一对应
/// （接口一致门钉住：方法改名 ⇒ 门红）。
pub(open) trait IriExpander {
  /// 展开 IRI：相对/绝对/compact/vocab 相对/bnode
  fn expand_iri(
    Self,
    active : ActiveContext,
    value : String,
    document_relative : Bool,
    vocab : Bool,
  ) -> Result[String, JsonLdError]

  /// 关键字原样通过（@xxx 不展开）
  fn handle_keyword(Self, value : String) -> Result[String, JsonLdError]

  /// compact IRI 展开（前缀在 active context 已声明）
  fn expand_compact(
    Self,
    active : ActiveContext,
    value : String,
    document_relative : Bool,
    vocab : Bool,
  ) -> Result[String, JsonLdError]

  /// vocab 相对拼接（@vocab 基）
  fn concat_vocab(Self, active : ActiveContext, value : String) -> Result[
    String,
    JsonLdError,
  ]

  /// 相对 base 解析
  fn resolve_base(Self, active : ActiveContext, value : String) -> Result[
    String,
    JsonLdError,
  ]

  /// term 查表（active context terms 命中）
  fn lookup_term(Self, active : ActiveContext, value : String) -> Result[
    String,
    JsonLdError,
  ]
}
