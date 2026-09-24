///| 活动 context：term 定义 + 作用域链
/// 作用域是树递归的关键——子节点继承父节点 context
pub(all) struct ActiveContext {
  base : String?
  terms : Map[String, TermDefinition]
  // 骨架阶段只列必要字段；@vocab/@language/@direction 待 J2 扩
}

///| term 定义
pub(all) struct TermDefinition {
  iri : String?
  type : String?
  container : ContainerType?
  // ...待 J2 扩
}

///| container 类型
pub(all) enum ContainerType {
  List
  Set
  Language
  Index
  Id
  Type
  Graph
}

///| Context 处理接口 —— 手写实现（递归策略不 gen）
pub(open) trait ContextProcessor {
  /// 处理本地 context，产新的 ActiveContext（作用域继承）
  fn process_context(
    Self,
    active : ActiveContext,
    local : JsonValue,
    options : JsonLdOptions,
  ) -> Result[ActiveContext, JsonLdError]
}