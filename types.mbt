///|
/// JSON-LD 处理阶段的错误
pub(all) enum JsonLdError {
  Syntax(String) // JSON 文本语法错误（解析层包装，2026-09-25 增）
  InvalidContext(String) // context 处理失败
  InvalidIri(String) // IRI 展开失败
  InvalidValue(String) // @value 形态非法
  InvalidList(String) // @list 形态非法
  Unsupported(String) // 未实现/不在范围（如 framing）
  ContextOverflow(String) // 远程 context 链深超限（己批——REC 4.1.2 步 5.2.3）
}

///|
/// 处理选项（对应 expansion 的 options）
pub(all) struct JsonLdOptions {
  base : String? // 文档基 IRI
  expand_context : JsonValue? // 外部 context（可为空）
  processing_mode : ProcessingMode
  /// 远程 context 装载器（己递归 scoped 批——REC 4.1.2 步 5.2.5）：入参 = core
  /// 解析后的绝对 context URL，返回 = 文档原文 / 错误消息。core 包无 fs，IO
  /// 由调用方注入；None + string context → Unsupported（红非静默）。同步闭包
  /// ——expand_document 保持同步。fn 字段不可派生 Debug，故本结构不再 derive
  load_context : ((String) -> Result[String, String])?
  /// toRdf 面（J3.4——spec §8.36）：@direction 序列化模式。None = 方向弃；
  /// "i18n-datatype" = ^^<i18n#lang_dir>；"compound-literal" = bnode +
  /// rdf:value/language/direction 三元组组
  rdf_direction : String?
  /// toRdf 面（J3.4）：广义三元组放行——谓词位 bnode（#t0118/#te075 oracle）
  produce_generalized_rdf : Bool
  /// compaction 面（J6——spec §8.41）：数组塌缩（单值数组解包）——REC 默认
  /// true；compact suite 的 compactArrays=false 件（×3）保数组形
  compact_arrays : Bool
  /// compaction 面（J6）：IRI 相对化（base 前缀剥除）——REC 默认 true；
  /// compactToRelative=false 件（×1）保绝对词面
  compact_to_relative : Bool
  /// framing 面（J5——spec §8.96 帧旗矩阵）：frame 文档保形展开（framing
  /// 旗/@default 对象/通配 pattern 过展开不弃）。REC JsonLdOptions/frame-
  /// Expansion 缺省 false；frame_document 内部对 frame 展开置 true，输入
  /// 展开恒 false
  frame_expansion : Bool
  /// framing 面（J5——spec §8.99 embed 批）：顶层 @graph 包裹豁免——REC
  /// JsonLdOptions/omitGraph 缺省 false（恒包裹）；true ⇒ 单节点不包裹
  /// （tg001 manifest 件）
  omit_graph : Bool
  /// fromRDF 面（役57——spec §8.130）：native 词形还原（integer/double/
  /// decimal/boolean）——REC 缺省 false
  use_native_types : Bool
  /// fromRDF 面（役57）：rdf:type 保留属性形——REC 缺省 false
  use_rdf_type : Bool
}

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
/// 处理模式：json-ld-1.0 / json-ld-1.1
pub(all) enum ProcessingMode {
  JsonLd10
  JsonLd11
} derive(Debug)

///|
/// 展开后的节点对象（树递归的中间态）
/// 字段只列骨架需要的；完整字段待 J2 扩
pub(all) struct ExpandedNode {
  /// 节点标识（@container @id 映射批起为 mut：条目无 @id 时由 id map 索引写入——
  /// REC "if item does not have the entry @id, add …"，#tm001/#tm005 oracle）
  mut id : String?
  types : Array[String]
  properties : Array[(String, Array[ExpandedValue])]
  reverse_props : Array[(String, Array[ExpandedValue])] // @reverse 映射（reverse 批）
  /// mut（J3.4 F2 同 id 预合并——首见对象原地并集图内容）
  mut graph : Array[ExpandedValue]? // 节点位 @graph（文档级批——t0020 保留 / t0009 顶层表面化）
  // Included Blocks（@included 纯形批——in01-in04 oracle：@included 作为节点
  // 对象键渲染，非顶层拼接；嵌套 included 随序列化递归自展）
  /// mut（J3.4 F2 同 id 预合并——首见对象原地并集 included）
  mut included : Array[ExpandedNode]?
  /// 节点 @index（@container 映射批：index map 应用——#tc013 oracle：index map
  /// 的键写入条目 @index；值对象位未落，挂后续 index 批）
  mut index : String?
} derive(Debug)

///|
/// 展开后的值（@value / @list / @set / 节点）
pub(all) enum ExpandedValue {
  Node(ExpandedNode)
  Value(ExpandedLiteral)
  /// index 槽（役23——{@index,@list} 值对象贯通：展开收 index、压缩出
  /// {@list,@index} 形——#t0041 oracle；缺省 None 零扰动存量构造/匹配）
  List(Array[ExpandedValue], index~ : String?)
} derive(Debug)

///|
/// @id 显式 null 哨兵（t0122/t0060 批——REC §5.2 IRI 展开：keyword 形非关键字
/// `@1*ALPHA` 返回 null「reserved for future use... ignored」）：@id 值命中时
/// 节点保留、id 位以**字面 null** 序列化（t0122 oracle：{"@id": null}）。
/// 空串不可能是合法展开 IRI/bnode——哨兵无碰撞面。
const EXPLICIT_NULL_ID : String = ""

///|
/// 展开后的字面量
/// datatype = @type（IRI）；数值/布尔字面量以词形入 value（xsd 词形挂 toRDF 役）
pub(all) struct ExpandedLiteral {
  mut value : String
  mut datatype : String?
  mut language : String?
  mut direction : String?
  /// 原始标量（number/bool 保形用；string 为 None——序列化时按词形输出）
  mut raw : JsonValue?
  /// 值对象 @index（@index mapping 批——#t0036 oracle：index map 的字面量条目写
  /// `@index`；已有 @index 保留）
  mut index : String?
  /// Included Blocks 于值对象位保形（#tin05 oracle：值对象内 @included 不弃，
  /// 内层照节点对象展开——展开后随字面量携带，序列化还原 "@included" 键）
  mut included : Array[ExpandedNode]?
} derive(Debug)

///|
/// RDF 四元组（与现有 trig/nquads 产物同形，便于复用发射层）
pub(all) struct JsonLdQuad {
  subject : String
  predicate : String
  object : String
  graph : String?
} derive(Debug)
