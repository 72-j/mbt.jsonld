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
  previous : PreviousContext?
  /// 默认语言（@context @language 成员——丙批）：串值无语言时注入
  default_language : String?
  /// 默认文字方向（@context @direction 成员——丙批）：ltr/rtl
  default_direction : String?
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
  /// @graph 组合次级容器（graph 容器族：[@graph, @set|@id|@index] 的次级——
  /// 裸 @graph 为 None；展开期定条目键附挂形态，#t0085/#tm013 oracle）
  graph_secondary : ContainerType?
  /// 属性作用域 context（scoped-context 批）：td 的 @context 值原样保留。
  /// 定义期已调用 Context Processing 校验（任何错误 → invalid scoped context，
  /// #tc032/#tc033 oracle）；展开期在该 term 的值展开前再处理并套用
  /// （#tc037/#tc038/#tin06 oracle）
  local_context : JsonValue?
  /// 定义期 base URL 快照（庚批——#tc031 oracle）：term 所在 context 的装载
  /// base URL（flags.base_url，缺省回落 documentUrl）。td 若来自远程 context，
  /// 其 scoped context 应用期须锚定**本快照**装载引用（不得回落 documentUrl）
  context_base_url : String?
  /// 索引映射（@index mapping 批——REC 4.2.2：`@index` 值须 IRI 展开成 **IRI**，
  /// 且仅在 1.1 模式与容器含 `@index` 时合法）：容器含 @index 且本映射 ≠ "@index" 时，
  /// 索引键写成**一条属性**（值 = 索引）而非 `@index` 条目（#tpi06~#tpi10 oracle）
  index_mapping : String?
  /// 保护位（@protected 批）：上下文级 `@protected` 成员为默认、td 级 `@protected`
  /// 覆盖。受保护定义不可被**不等价**重定义覆盖；等价重定义允许且**保留旧定义**
  /// （保护位不丢——#pr42 oracle）
  is_protected : Bool
  /// @prefix 标记三态（@vocab 动态形态批——REC 4.2.2）：None 未声明（compact
  /// 可用）/ Some(false) 显式抑制（#tpr29 oracle）/ Some(true) 显式允许
  is_prefix : Bool?
  /// 语言映射三态（丙批）：None = 未声明（串值继承 context 默认语言）；
  /// Null = 显式压制（@language: null）；Set = 覆盖（#t0018/#tdi06 oracle）
  language_mapping : LanguageMember?
  /// 方向映射三态（丙批）：同上三态；#tdi01/#tdi04~#tdi07 oracle
  direction_mapping : LanguageMember?
}

///|
/// 语言/方向成员三态（丙批）
pub(all) enum LanguageMember {
  Set(String)
  Null
}

///|
/// Context Processing 的调用面旗标（REC 4.1.2 的可选输入；己批扩到五件）——
/// 用结构体而非相邻裸 bool，防调用点位置错配；面语义见各构造器注释
pub(all) struct ContextFlags {
  /// false = 置 previous context（供新节点回退）
  propagate : Bool
  /// true = 允许覆盖受保护 term
  override_protected : Bool
  /// 步 5.2.1 的 base URL（**独立于 active.base** 的算法输入，随装载递归传播为
  /// documentUrl；None = 回落 options.base 即 documentUrl——引用解析**不随
  /// active @base 覆写走**，#tc031 oracle）
  base_url : String?
  /// 步 5.2 的 remote contexts 链（"used to detect cyclical context inclusions"）；
  /// 默认新空数组，递归边界取**副本**（新建数组）
  remote_contexts : Array[String]
  /// 步 5.2.2 的 validate scoped context（默认 true；td 定义期校验传 false =
  /// 链上已有则**跳过非错误**——破环主机制）
  validate_scoped : Bool
}

///|
/// REC 4.1.2 步 5.2.3 的 processor-defined limit（context overflow 触发深度）——
/// 套件最深链 4，取 32 余量充足；validate=true 的文档级环靠此截断（有界装载，
/// 无超时面）
const CONTEXT_CHAIN_LIMIT : Int = 32

///|
/// type-scoped 应用面（REC 5.1.2：不传 override protected、`false for propagate`）——
/// 故 type-scoped 内空化保护 term 即错（#pr17/#pr18/#pr20/#pr21 oracle）。
/// 应用面取**新空链** + validate=true（REC expansion 算法不传 remote contexts）
pub fn ContextFlags::type_scoped() -> ContextFlags {
  {
    propagate: false,
    override_protected: false,
    base_url: None,
    remote_contexts: [],
    validate_scoped: true,
  }
}

///|
/// property-scoped 应用面（REC 5.1.2："and true for override protected"；propagate
/// 默认 true）——故属性作用域内可清保护（#pr06/#pr14/#pr15/#pr16 oracle）。
/// 应用面取**新空链** + validate=true（REC expansion 13.9.6 不传 remote contexts）
pub fn ContextFlags::property_scoped() -> ContextFlags {
  {
    propagate: true,
    override_protected: true,
    base_url: None,
    remote_contexts: [],
    validate_scoped: true,
  }
}

///|
/// 元素级 @context 面（propagate 默认 true、override protected 默认 false）——
/// 新空链 + validate=true；base_url 留 None（回落 options.base——documentUrl）
pub fn ContextFlags::element() -> ContextFlags {
  {
    propagate: true,
    override_protected: false,
    base_url: None,
    remote_contexts: [],
    validate_scoped: true,
  }
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
