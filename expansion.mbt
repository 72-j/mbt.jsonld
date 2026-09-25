///|
/// Expansion 接口 —— 手写实现（树递归）
/// 契约面与 jsonld_gen.toml 的 handler_hook 一一对应（接口一致门
/// `interface_gate_test.mbt` 钉住：trait 方法改名 ⇒ 门红）。
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

  /// 展开数组：逐元素处理（滤 null），步骤图无环——元素循环在钩子内
  fn expand_array(
    Self,
    active : ActiveContext,
    items : Array[JsonValue],
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// 非关键字键（term）展开：属性位语义——返回该属性的值数组（滤 dropped；
  /// 空数组 = 属性丢弃）。datatype coercion / 节点引用判定在此
  fn expand_term(
    Self,
    active : ActiveContext,
    term : String,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[Array[ExpandedValue], JsonLdError]

  /// value object 归一：@value 形态、@type/@language/@direction 归位
  fn postprocess_value(Self, active : ActiveContext, value : ExpandedValue) -> Result[
    ExpandedValue,
    JsonLdError,
  ]

  /// @language：语言标注
  fn set_language(Self, active : ActiveContext, value : JsonValue) -> Result[
    ExpandedValue,
    JsonLdError,
  ]

  /// @direction：方向标注
  fn set_direction(Self, active : ActiveContext, value : JsonValue) -> Result[
    ExpandedValue,
    JsonLdError,
  ]

  /// @list：列表对象
  fn expand_list(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @set：集合（展开为数组）
  fn expand_set(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @graph：图对象
  fn expand_graph(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @reverse：反向属性
  fn expand_reverse(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @nest：嵌套属性组
  fn expand_nest(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @included：引入节点对象
  fn expand_included(
    Self,
    active : ActiveContext,
    value : JsonValue,
    active_property : String?,
    options : JsonLdOptions,
  ) -> Result[ExpandedValue, JsonLdError]

  /// @index：索引标注
  fn set_index(Self, active : ActiveContext, value : JsonValue) -> Result[
    ExpandedValue,
    JsonLdError,
  ]
}
