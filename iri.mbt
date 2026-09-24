///| IRI 展开接口
pub(open) trait IriExpander {
  /// 展开 IRI：相对/绝对/compact/vocab 相对/bnode
  fn expand_iri(
    Self,
    active : ActiveContext,
    value : String,
    document_relative : Bool,
    vocab : Bool,
  ) -> Result[String, JsonLdError]
}