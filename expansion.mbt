///| Expansion 接口 —— 手写实现（树递归）
pub(open) trait Expander {
  /// 展开一个 element（递归入口）
  fn expand_element(
    Self,
    active : ActiveContext,
    element : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// 展开一个 value（@value 处理）
  fn expand_value(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
  ) -> Result[ExpandedValue, JsonLdError]
}