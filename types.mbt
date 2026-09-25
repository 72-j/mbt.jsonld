///|
/// JSON-LD 处理阶段的错误
pub(all) enum JsonLdError {
  Syntax(String) // JSON 文本语法错误（解析层包装，2026-09-25 增）
  InvalidContext(String) // context 处理失败
  InvalidIri(String) // IRI 展开失败
  InvalidValue(String) // @value 形态非法
  InvalidList(String) // @list 形态非法
  Unsupported(String) // 未实现/不在范围（如 framing）
}

///|
/// 处理选项（对应 expansion 的 options）
pub(all) struct JsonLdOptions {
  base : String? // 文档基 IRI
  expand_context : JsonValue? // 外部 context（可为空）
  processing_mode : ProcessingMode
} derive(Debug)

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend JsonLdQuad with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend ExpandedLiteral with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend ExpandedValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend ExpandedNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend ProcessingMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// [0079] 消警：Debug 派生的 to_repr 显式升格（2026-09-25）
pub extend JsonLdOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 处理模式：json-ld-1.0 / json-ld-1.1
pub(all) enum ProcessingMode {
  JsonLd10
  JsonLd11
} derive(Debug)

///|
/// 展开后的节点对象（树递归的中间态）
/// 字段只列骨架需要的；完整字段待 J2 扩
pub(all) struct ExpandedNode {
  id : String?
  types : Array[String]
  properties : Array[(String, Array[ExpandedValue])]
} derive(Debug)

///|
/// 展开后的值（@value / @list / @set / 节点）
pub(all) enum ExpandedValue {
  Node(ExpandedNode)
  Value(ExpandedLiteral)
  List(Array[ExpandedValue])
} derive(Debug)

///|
/// 展开后的字面量
pub(all) struct ExpandedLiteral {
  value : String
  datatype : String?
  language : String?
  direction : String?
} derive(Debug)

///|
/// RDF 四元组（与现有 trig/nquads 产物同形，便于复用发射层）
pub(all) struct JsonLdQuad {
  subject : String
  predicate : String
  object : String
  graph : String?
} derive(Debug)
