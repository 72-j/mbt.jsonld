///|
/// toRDF 处理接口 —— 手写实现（J3 落码；J1 定契约）
/// 契约面与 jsonld_gen.toml 的 handler_hook 对应（接口一致门钉住）。
pub(open) trait ToRdfProcessor {
  /// 展开后的节点对象图 → 四元组（@graph 图名与数据集处理在此）
  fn node_to_quads(
    Self,
    expanded : Array[ExpandedValue],
    options : JsonLdOptions,
  ) -> Result[Array[JsonLdQuad], JsonLdError]
}
