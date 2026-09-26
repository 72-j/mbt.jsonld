///|
/// 活动 context：term 定义 + 作用域链
/// 作用域是树递归的关键——子节点继承父节点 context
pub(all) struct ActiveContext {
  base : String?
  vocab : String? // @vocab 声明（③批；相对 IRI 已按 base 解析为绝对）
  terms : Map[String, TermDefinition]
  // @language/@direction 默认值待后续批扩
}

///|
/// term 定义
pub(all) struct TermDefinition {
  iri : String?
  datatype : String? // @type 在 term 定义里指向 datatype IRI
  container : ContainerType?
  reverse : String? // @reverse 映射（reverse 批）
  // ...待 J2 扩
}

///|
/// container 类型
pub(all) enum ContainerType {
  List
  Set
  Language
  Index
  Id
  Type
  Graph
}

///|
/// Context 处理接口 —— 手写实现（递归策略不 gen）
pub(open) trait ContextProcessor {
  /// 处理本地 context，产新的 ActiveContext（作用域继承）
  fn process_context(
    Self,
    active : ActiveContext,
    local_context : JsonValue,
    options : JsonLdOptions,
  ) -> Result[ActiveContext, JsonLdError]
}
