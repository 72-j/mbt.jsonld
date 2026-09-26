///|
/// 活动 context：term 定义 + 作用域链
/// 作用域是树递归的关键——子节点继承父节点 context
pub(all) struct ActiveContext {
  base : String?
  vocab : String? // @vocab 声明（③批；相对 IRI 已按 base 解析为绝对）
  terms : Map[String, TermDefinition]
  /// 「前一 context」快照（REC 4.1.2 步 3：propagate=false 且 result 尚无 previous
  /// 时置位）——展开**新节点对象**时回退到此（"term-scoped context 不跨新节点"。
  /// type-scoped 批）。平铺结构（不复用 ActiveContext）以免自引用类型；规格只
  /// 单层回退，「已有 previous 不覆盖」语义由本字段的表达方式承担。
  /// @language/@direction 默认值待后续批扩
  previous : PreviousContext?
}

///|
/// 前一 context 快照（type-scoped 批）：只承载回退所需的三个字段
pub(all) struct PreviousContext {
  base : String?
  vocab : String?
  terms : Map[String, TermDefinition]
}

///|
/// term 定义
pub(all) struct TermDefinition {
  iri : String?
  datatype : String? // @type 在 term 定义里指向 datatype IRI
  container : ContainerType?
  reverse : String? // @reverse 映射（reverse 批）
  /// 属性作用域 context（scoped-context 批）：td 的 @context 值原样保留。
  /// 定义期已调用 Context Processing 校验（任何错误 → invalid scoped context，
  /// #tc032/#tc033 oracle）；展开期在该 term 的值展开前再处理并套用
  /// （#tc037/#tc038/#tin06 oracle）
  local_context : JsonValue?
  /// 保护位（@protected 批）：上下文级 `@protected` 成员为默认、td 级 `@protected`
  /// 覆盖。受保护定义不可被**不等价**重定义覆盖；等价重定义允许且**保留旧定义**
  /// （保护位不丢——#pr42 oracle）
  is_protected : Bool
}

///|
/// Context Processing 的调用面旗标（REC 4.1.2 的两个可选输入）——用结构体而非
/// 相邻两个裸 bool，防调用点位置错配；四面语义见各构造器注释
pub(all) struct ContextFlags {
  /// false = 置 previous context（供新节点回退）
  propagate : Bool
  /// true = 允许覆盖受保护 term
  override_protected : Bool
}

///|
/// type-scoped 应用面（REC 5.1.2：不传 override protected、`false for propagate`）——
/// 故 type-scoped 内空化保护 term 即错（#pr17/#pr18/#pr20/#pr21 oracle）
pub fn ContextFlags::type_scoped() -> ContextFlags {
  { propagate: false, override_protected: false, }
}

///|
/// property-scoped 应用面（REC 5.1.2："and true for override protected"；propagate
/// 默认 true）——故属性作用域内可清保护（#pr06/#pr14/#pr15/#pr16 oracle）
pub fn ContextFlags::property_scoped() -> ContextFlags {
  { propagate: true, override_protected: true, }
}

///|
/// 元素级 @context 面（propagate 默认 true、override protected 默认 false）
pub fn ContextFlags::element() -> ContextFlags {
  { propagate: true, override_protected: false, }
}

///|
/// td 定义期 scoped 校验面（REC 4.2.2 @context 臂："true for override protected"）
pub fn ContextFlags::scoped_validation() -> ContextFlags {
  { propagate: true, override_protected: true, }
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
  /// `flags`：**调用方默认**（四面见 ContextFlags 构造器）——local context 自带的
  /// `@propagate` 成员（REC 4.1.2 步 2）优先于 propagate 默认值
  fn process_context(
    Self,
    active : ActiveContext,
    local_context : JsonValue,
    flags : ContextFlags,
    options : JsonLdOptions,
  ) -> Result[ActiveContext, JsonLdError]
}
