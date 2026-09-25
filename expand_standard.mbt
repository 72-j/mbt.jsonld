///|
/// 标准 expansion 实现（手写树递归；ADR-JL-4 纯函数，ActiveContext 不可变）。
/// 落码节奏：按套件迁移顺序逐方法落码——每落一个方法配一个对拍；
/// 未落码方法一律 `Unsupported("pending …")`（红而非错），禁止猜测语义。
/// **挂账红语义**：未落码方法的 `Unsupported` = 内部标记 + 账记，**门仍绿**
/// （deny-warn 双档含 stub 全过）——"全绿"≠"全实现"；落码进度 = 契约烟雾的
/// Unsupported 计数（expand_standard_wbtest.mbt，常驻活账）。
/// 当前覆盖：#t0001（@id + free-floating drop）+ #t0045（顶层值对象丢弃）+
/// ①批 coercion **形态 A**（显式 @type → datatype）+ ②批 term/IRI 分拣链 +
/// ③批 @context 简单形态（term→IRI / @vocab / @base）+ #ter48（@id 位相对拒绝）。
/// **形态边界**：本批仅形态 A；形态 B（@id coercion）/ 形态 C（@json）挂 term/IRI 批后。

///|
pub(all) struct StandardExpander {}

///|
/// 显式升格（const §5 同款纪律）——仅列被 Type::method / 引擎形式调用的方法
extend StandardExpander with Expander::{
  expand_element,
  expand_value,
  expand_array,
  expand_term,
}

///|
/// IRI 合法性（形态 A 片）：含 scheme 冒号且无空白（"baz z" 类拒之——#t0123）
fn is_valid_absolute_iri(value : String) -> Bool {
  // scheme 冒号须在非首位（":fish" 空 scheme 非绝对——#t0118 oracle：走 vocab 拼接）；
  // scheme 首字符须为 ALPHA（RFC 3986 scheme 文法，规范 IRI 正则同款——"_:dt"
  // 的 scheme "_" 非法 ⇒ 非绝对，#ter40 oracle：bnode 不得作 datatype）
  let mut i = 0
  let mut has_colon = false
  let mut scheme_initial_alpha = false
  for ch in value {
    if i == 0 {
      scheme_initial_alpha = ch is ('a'..='z' | 'A'..='Z')
    }
    if ch is ':' && i > 0 {
      has_colon = true
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      return false
    }
    i += 1
  }
  scheme_initial_alpha && has_colon
}

///|
/// bnode 判定（_: 前缀）
fn is_bnode_label(value : String) -> Bool {
  match value.get_char(0) {
    Some('_') =>
      match value.get_char(1) {
        Some(':') => true
        _ => false
      }
    _ => false
  }
}

///|
/// 首个冒号的代码单元索引（compact 分段用；冒号为 BMP ⇒ 切片边界必合法）
fn colon_index(value : String) -> Int? {
  let mut i = 0
  for ch in value {
    if ch is ':' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 冒号切分（平台中立：字符迭代拼装，避免 StringView 切片的抛错面差异）。
/// 语义：at 位为冒号本身——prefix = at 之前、suffix = at 之后（冒号丢弃）
fn split_first_colon(value : String, at : Int) -> (String, String) {
  let pre = StringBuilder()
  let suf = StringBuilder()
  let mut i = 0
  for ch in value {
    if i < at {
      pre <+ "\{ch}"
    } else if i > at {
      suf <+ "\{ch}"
    }
    i += 1
  }
  (pre.to_string(), suf.to_string())
}

///|
/// @base 相对值解析（套件 oracle #t0090/#t0091；算法移植子仓 gen_nquads/iri.mbt
/// fn_remove_dot_segments）：合并 = raw 拼接 + ".." 段弹出；
/// "." 与 "" 段保留（#t0091 期望保留 /./）；value 绝对 → 原样（不做点段归一）

///|
/// RFC 3986 5.2.3 merge：value 相对 → base 截最后 "/"（含）+ value；
/// base 无 "/" → 补根 "/"（#t0129/#t0130 oracle：/example + relative-iri →
/// /example/relative-iri）
fn merge_base_reference(base : String, reference : String) -> String {
  if base is "" {
    return reference
  }
  // authority 后无 "/"（base 仅到 host）→ 补根 "/"；有 → 截最后 "/"（含）
  match base.rev_find("/") {
    Some(idx) =>
      if idx > 6 {
        let head = base[:idx + 1].to_owned()
        "\{head}\{reference}"
      } else {
        "\{base}/\{reference}"
      }
    None => "\{base}/\{reference}"
  }
}

///|
fn resolve_base_value(value : String, previous : String?) -> String {
  if is_valid_absolute_iri(value) {
    return value
  }
  let prev = match previous {
    Some(b) => b
    None => ""
  }
  let merged = merge_base_reference(prev, value)
  let segs : Array[String] = []
  for seg in merged.split("/").to_array() {
    let seg = seg.to_owned()
    if seg is ".." {
      // RFC 3986 5.2.4：".." 弹前段并补根段（/base/.. → /）
      if segs.length() > 1 {
        let _ = segs.pop()
        segs.push("")
      } else {
        segs.push("")
      }
    } else if seg is "." {
      // "." 段消除（RFC 3986 5.2.4；#t0091 oracle 期望 /./ 不保留）
    } else {
      segs.push(seg)
    }
  }
  let out = StringBuilder()
  for i, seg in segs {
    if i > 0 {
      out <+ "/"
    }
    out <+ "\{seg}"
  }
  out.to_string()
}

///|
/// 字面量构造（raw = 原始标量：number/bool 保形；string 为 None）
fn literal_of(value : String, raw : JsonValue?) -> ExpandedValue {
  ExpandedValue::Value(ExpandedLiteral::{
    value,
    datatype: None,
    language: None,
    direction: None,
    raw,
  })
}

///|
/// IRI 展开（②批分拣链 + ③批 vocab/vocab 位门控）：对齐 iri_rules 表序
/// （keyword → term[仅 vocab 位] → bnode → compact → absolute → vocab relative → relative）。
/// **#ter48 oracle**：@id 位 terms-are-not-considered（vocab=false ⇒ 不查表不拼 vocab）。
/// **边界行为**：term 未命中/前缀未声明 = 非错误落链；value 位无 vocab 无 base = 原样。
impl IriExpander for StandardExpander with fn expand_iri(
  _self,
  active : ActiveContext,
  value : String,
  _document_relative : Bool,
  vocab : Bool,
) -> Result[String, JsonLdError] {
  // 1 keyword：@ 前缀原样（未知 @word 不校验集合，挂负例校准）
  if value.get_char(0) is Some('@') {
    return Ok(value)
  }
  // 2 term 精确查表：仅 vocab 位
  if vocab {
    match active.terms.get(value) {
      Some(td) =>
        match td.iri {
          Some(iri) => return Ok(iri)
          None => ()
        }
      None => ()
    }
  }
  // 3 bnode：_: 前缀原样
  if is_bnode_label(value) {
    return Ok(value)
  }
  // 4 compact：prefix ∈ terms → 定义 IRI + suffix
  match colon_index(value) {
    Some(at) => {
      let (prefix, suffix) = split_first_colon(value, at)
      match active.terms.get(prefix) {
        Some(td) =>
          match td.iri {
            Some(base_iri) => return Ok("\{base_iri}\{suffix}")
            None => ()
          }
        None => ()
      }
    }
    None => ()
  }
  // 5 absolute：scheme 冒号 + 无空白 → 原样
  if is_valid_absolute_iri(value) {
    return Ok(value)
  }
  // 6 vocab relative：无冒号 + vocab 位为真 → 拼接（③批解挂；
  // #ter48 oracle：@id 位 vocab=false ⇒ @vocab 不参与）
  let meaningful_colon = colon_index(value) is Some(at) && at > 0
  if !meaningful_colon && vocab {
    match active.vocab {
      Some(v) => return Ok("\{v}\{value}")
      None => ()
    }
  }
  // 7 relative：RFC 3986 5.2.3 merge（base 截最后 "/" 含 + 引用）；
  // 无 base → 原样（value 位）
  match active.base {
    Some(base) => Ok(merge_base_reference(base, value))
    None => Ok(value)
  }
}

///|
impl IriExpander for StandardExpander with fn handle_keyword(
  _self,
  value : String,
) -> Result[String, JsonLdError] {
  // 关键字原样通过（@xxx 不展开）
  Ok(value)
}

///|
/// compact 展开（②批）：prefix ∈ terms → 定义 IRI + suffix；
/// 未声明前缀 = 非错误拒绝（InvalidValue——落链语义由 expand_iri 负责）
impl IriExpander for StandardExpander with fn expand_compact(
  _self,
  active : ActiveContext,
  value : String,
  _document_relative : Bool,
  _vocab : Bool,
) -> Result[String, JsonLdError] {
  match colon_index(value) {
    Some(at) => {
      let (prefix, suffix) = split_first_colon(value, at)
      match active.terms.get(prefix) {
        Some(td) =>
          match td.iri {
            Some(base_iri) => Ok("\{base_iri}\{suffix}")
            None => Err(JsonLdError::InvalidValue("compact prefix without IRI"))
          }
        None => Err(JsonLdError::InvalidValue("compact prefix not declared"))
      }
    }
    None => Err(JsonLdError::InvalidValue("expand_compact: no colon"))
  }
}

///|
/// vocab 相对拼接（③批解挂）：@vocab 未声明 = Err 非静默拼接；命中 = vocab + value
impl IriExpander for StandardExpander with fn concat_vocab(
  _self,
  active : ActiveContext,
  value : String,
) -> Result[String, JsonLdError] {
  match active.vocab {
    Some(vocab) => Ok("\{vocab}\{value}")
    None => Err(JsonLdError::InvalidValue("@vocab not declared"))
  }
}

///|
/// base 相对解析（②批）：简单拼接（RFC3986 完整解析挂后续）
impl IriExpander for StandardExpander with fn resolve_base(
  _self,
  active : ActiveContext,
  value : String,
) -> Result[String, JsonLdError] {
  Ok(resolve_base_value(value, active.base))
}

///|
/// term 查表（②批）：s ∈ active.terms → 定义 IRI；未命中 = 非错误拒绝
/// （落链语义由 expand_iri 负责）
impl IriExpander for StandardExpander with fn lookup_term(
  _self,
  active : ActiveContext,
  value : String,
) -> Result[String, JsonLdError] {
  match active.terms.get(value) {
    Some(td) =>
      match td.iri {
        Some(iri) => Ok(iri)
        None => Err(JsonLdError::InvalidValue("term definition without IRI"))
      }
    None => Err(JsonLdError::Unsupported("term not in constructed context"))
  }
}

///|
/// 对象展开（①批 coercion + ③批 @context）：
/// @id（节点身份，绝对/bnode 校验）/ @type（节点类型数组 + 值对象 datatype 形态 A
/// 含四族验证）/ @value / @language / @direction（值对象族第一批）/
/// @context（③批解挂：process_context 构建/继承新 context，循环内经 current 传播）/
/// 非关键字键 → expand_term 属性位累加（键经 IRI 链展开）。
fn StandardExpander::expand_object(
  self : StandardExpander,
  active : ActiveContext,
  element : JsonValue,
  _active_property : String?,
  options : JsonLdOptions,
) -> Result[ExpandedValue?, JsonLdError] {
  let pairs = match element {
    JsonValue::Object(pairs) => pairs
    _ => return Err(JsonLdError::InvalidValue("expand_object: not an object"))
  }
  let mut node_id : String? = None
  let types : Array[String] = []
  let properties : Array[(String, Array[ExpandedValue])] = []
  let mut literal : ExpandedLiteral? = None
  let mut is_value_object = false
  let mut has_datatype = false
  let mut has_language = false
  let mut has_direction = false
  // current：@context 处理后的当前 context（③批；循环内可被 @context 键更新）
  let mut current = active
  for pair in pairs {
    // 键归一（#ter51 oracle）：字面 @ 键原样；term 键经 IRI 链展开一次——
    // 别名 term（IRI 即关键字）归一到关键字位，与字面关键字同路分派
    let expanded_key = match pair.0.get_char(0) {
      Some('@') => pair.0
      _ =>
        match IriExpander::expand_iri(self, current, pair.0, false, true) {
          Ok(k) => k
          Err(e) => return Err(e)
        }
    }
    // 关键字位判定按归一键：字面关键字与别名 term 汇流
    let routes_to_keyword = expanded_key.get_char(0) is Some('@')
    if !routes_to_keyword {
      // term 位（_term 缺省路由）：键已归一；属性值展开，键合法即累加
      let values = match
        StandardExpander::expand_term(
          self,
          current,
          pair.0,
          pair.1,
          _active_property,
          options,
        ) {
        Ok(values) => values
        Err(e) => return Err(e)
      }
      // 键合法性：绝对 IRI 或 bnode 标签（规范：expanded property 可为 blank
      // node identifier——scheme-ALPHA 收紧后 bnode 在此显式放行）
      if values.length() > 0 &&
        (is_valid_absolute_iri(expanded_key) || is_bnode_label(expanded_key)) {
        properties.push((expanded_key, values))
      }
      continue
    }
    // 关键字分派（按键名；@vocab/@base 等 context 层七键走手写——@context 批）
    match expanded_key {
      "@id" => {
        // 值对象内 @id = 意外关键字（#ter37 oracle）
        if is_value_object {
          return Err(JsonLdError::InvalidValue("invalid value object"))
        }
        match pair.1 {
          JsonValue::String(iri) =>
            match IriExpander::expand_iri(self, current, iri, true, false) {
              Ok(expanded) => {
                // @id 位：节点身份必须为绝对 IRI 或 bnode（#ter48 oracle：
                // 相对 @id 不可用 → invalid IRI mapping）
                if !(is_bnode_label(expanded) || is_valid_absolute_iri(expanded)) {
                  return Err(JsonLdError::InvalidIri("invalid IRI mapping"))
                }
                node_id = Some(expanded)
              }
              Err(e) => return Err(e)
            }
          _ =>
            return Err(JsonLdError::InvalidValue("@id value must be a string"))
        }
      }
      "@type" =>
        // @type 双侧：值对象内 = datatype（coercion 形态 A）；节点侧 = 类型数组
        match pair.1 {
          JsonValue::String(t) =>
            if is_value_object {
              // 形态 A：显式 @type → datatype（合法性钉——#t0123）
              match IriExpander::expand_iri(self, current, t, false, true) {
                Ok(dt) =>
                  if !is_valid_absolute_iri(dt) {
                    return Err(JsonLdError::InvalidValue("invalid typed value"))
                  } else if has_language {
                    // @type 与 @language 互斥（#ter38）
                    return Err(
                      JsonLdError::InvalidValue("invalid value object"),
                    )
                  } else if has_direction {
                    // @type 与 @direction 互斥（#tdi09，direction-在前序）
                    return Err(
                      JsonLdError::InvalidValue("invalid value object"),
                    )
                  } else if has_datatype {
                    return Err(JsonLdError::InvalidValue("invalid typed value"))
                  } else {
                    has_datatype = true
                    match literal {
                      Some(l) => l.datatype = Some(dt)
                      None => ()
                    }
                  }
                Err(e) => return Err(e)
              }
            } else {
              match IriExpander::expand_iri(self, current, t, false, true) {
                Ok(dt) => types.push(dt)
                Err(e) => return Err(e)
              }
            }
          JsonValue::Array(many) =>
            if is_value_object {
              // 值对象 @type 多值 → invalid typed value（#ter54）
              return Err(JsonLdError::InvalidValue("invalid typed value"))
            } else {
              for t in many {
                match t {
                  JsonValue::String(iri) =>
                    match
                      IriExpander::expand_iri(self, current, iri, false, true) {
                      Ok(dt) => types.push(dt)
                      Err(e) => return Err(e)
                    }
                  _ =>
                    return Err(
                      JsonLdError::InvalidValue("invalid type value"), // #ter28 同族
                    )
                }
              }
            }
          _ => return Err(JsonLdError::InvalidValue("invalid type value")) // #ter28
        }
      "@value" => {
        // @value：值对象核心（string/number/bool 词形保形；null → 值对象丢弃）
        is_value_object = true
        match pair.1 {
          JsonValue::Null => literal = None
          JsonValue::String(sv) =>
            literal = Some(
              match literal {
                Some(existing) => {
                  existing.value = sv
                  existing
                }
                None =>
                  ExpandedLiteral::{
                    value: sv,
                    datatype: None,
                    language: None,
                    direction: None,
                    raw: None,
                  }
              },
            )
          JsonValue::Number(nv) =>
            literal = Some(
              match literal {
                Some(existing) => {
                  existing.value = "\{nv}"
                  existing.raw = Some(JsonValue::Number(nv))
                  existing
                }
                None =>
                  ExpandedLiteral::{
                    value: "\{nv}",
                    datatype: None,
                    language: None,
                    direction: None,
                    raw: Some(JsonValue::Number(nv)),
                  }
              },
            )
          JsonValue::Bool(bv) =>
            literal = Some(
              match literal {
                Some(existing) => {
                  existing.value = "\{bv}"
                  existing.raw = Some(JsonValue::Bool(bv))
                  existing
                }
                None =>
                  ExpandedLiteral::{
                    value: "\{bv}",
                    datatype: None,
                    language: None,
                    direction: None,
                    raw: Some(JsonValue::Bool(bv)),
                  }
              },
            )
          _ =>
            return Err(
              JsonLdError::InvalidValue(
                "@value must be string, number, boolean or null",
              ),
            )
        }
      }
      "@language" =>
        // @language：与 datatype 互斥（#ter38）；键序无关（先记后合）
        match pair.1 {
          JsonValue::String(lang) => {
            if has_datatype {
              return Err(JsonLdError::InvalidValue("invalid value object"))
            }
            has_language = true
            match literal {
              Some(existing) => existing.language = Some(lang)
              None =>
                literal = Some(ExpandedLiteral::{
                  value: "",
                  datatype: None,
                  language: Some(lang),
                  direction: None,
                  raw: None,
                })
            }
          }
          JsonValue::Null =>
            match literal {
              Some(existing) => existing.language = None
              None => ()
            }
          _ =>
            return Err(
              JsonLdError::InvalidValue("@language must be a string or null"),
            )
        }
      "@direction" =>
        // @direction：与 datatype 互斥（#tdi09）
        match pair.1 {
          JsonValue::String(dir) => {
            if has_datatype {
              return Err(JsonLdError::InvalidValue("invalid value object"))
            }
            has_direction = true
            match literal {
              Some(existing) => existing.direction = Some(dir)
              None =>
                literal = Some(ExpandedLiteral::{
                  value: "",
                  datatype: None,
                  language: None,
                  direction: Some(dir),
                  raw: None,
                })
            }
          }
          JsonValue::Null =>
            match literal {
              Some(existing) => existing.direction = None
              None => ()
            }
          _ =>
            return Err(
              JsonLdError::InvalidValue("@direction must be a string or null"),
            )
        }
      "@context" =>
        // ③批解挂：@context 声明 → 构建/继承新 active context（后续键即用新 context）
        match pair.1 {
          JsonValue::Null => current = initial_context(options)
          _ =>
            match
              ContextProcessor::process_context(self, current, pair.1, options) {
              Ok(next) => current = next
              Err(e) => return Err(e)
            }
        }
      other =>
        return Err(
          JsonLdError::Unsupported(
            "keyword expansion pending later batches (\{other})",
          ),
        )
    }
  }
  // 形态判定：值对象（@value 键已见）优先于节点对象
  if is_value_object {
    match literal {
      Some(found) => {
        // @language 只配字符串 @value（#ter39 oracle）：@value 非串（raw 记录
        // Number/Bool 词形）而带 @language → invalid language-tagged value；
        // @value: null 在臂内已置 literal=None，先于本校验丢弃（规范次序）
        if has_language && found.raw is Some(_) {
          return Err(JsonLdError::InvalidValue("invalid language-tagged value"))
        }
        Ok(Some(ExpandedValue::Value(found)))
      }
      None => Ok(None) // @value: null → 整个值对象丢弃
    }
  } else {
    Ok(
      Some(
        ExpandedValue::Node(ExpandedNode::{ id: node_id, types, properties, }),
      ),
    )
  }
}

///|
impl Expander for StandardExpander with fn expand_element(
  self,
  active : ActiveContext,
  element : JsonValue,
  active_property : String?,
  options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  match element {
    JsonValue::Object(_) =>
      match
        StandardExpander::expand_object(
          self, active, element, active_property, options,
        ) {
        Ok(Some(other)) => Ok(other)
        Ok(None) =>
          Err(JsonLdError::Unsupported("empty node pending later cases"))
        Err(e) => Err(e)
      }
    JsonValue::Array(items) =>
      StandardExpander::expand_array(
        self, active, items, active_property, options,
      )
    _ => StandardExpander::expand_value(self, active, element, active_property)
  }
}

///|
impl Expander for StandardExpander with fn expand_value(
  _self,
  _active : ActiveContext,
  value : JsonValue,
  _active_property : String?,
) -> Result[ExpandedValue, JsonLdError] {
  // 标量位（顶层/数组元素）：字符串保留；number 保形；其余挂后续例
  match value {
    JsonValue::String(s) => Ok(literal_of(s, None))
    JsonValue::Number(nv) =>
      Ok(literal_of("\{nv}", Some(JsonValue::Number(nv))))
    _ =>
      Err(
        JsonLdError::Unsupported("scalar expansion pending later suite cases"),
      )
  }
}

///|
impl Expander for StandardExpander with fn expand_array(
  self,
  active : ActiveContext,
  items : Array[JsonValue],
  active_property : String?,
  options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  // 逐元素递归、滤 dropped（1.1 数组滤 null）；元素循环在钩子内（步骤图无环）
  let out : Array[ExpandedValue] = []
  for item in items {
    match
      StandardExpander::expand_element(
        self, active, item, active_property, options,
      ) {
      Ok(v) => out.push(v)
      Err(e) => return Err(e)
    }
  }
  Ok(ExpandedValue::List(out))
}

///|
/// term 位展开（①批语义）：对象 → 值对象/节点；数组 → 逐元素递归累加；
/// string → 字面量；number → 字面量（raw 保形）；bool/null → 丢弃（属性位）
impl Expander for StandardExpander with fn expand_term(
  self,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  active_property : String?,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  StandardExpander::expand_term_values(
    self, active, term, value, active_property, options,
  )
}

///|
fn StandardExpander::expand_term_values(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  active_property : String?,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  match value {
    JsonValue::Object(_) =>
      match
        StandardExpander::expand_object(
          self,
          active,
          value,
          Some(term),
          options,
        ) {
        Ok(Some(v)) => Ok([v])
        Ok(None) => Ok([])
        Err(e) => Err(e)
      }
    JsonValue::Array(items) => {
      let out : Array[ExpandedValue] = []
      for item in items {
        match
          StandardExpander::expand_term_values(
            self, active, term, item, active_property, options,
          ) {
          Ok(vs) =>
            for v in vs {
              out.push(v)
            }
          Err(e) => return Err(e)
        }
      }
      Ok(out)
    }
    JsonValue::String(sv) => Ok([literal_of(sv, None)])
    JsonValue::Number(nv) =>
      Ok([literal_of("\{nv}", Some(JsonValue::Number(nv)))])
    // 属性位布尔/null 丢弃（1.1）
    JsonValue::Bool(_) => Ok([])
    JsonValue::Null => Ok([])
  }
}

///|
impl Expander for StandardExpander with fn postprocess_value(
  _self,
  _active : ActiveContext,
  value : ExpandedValue,
) -> Result[ExpandedValue, JsonLdError] {
  // 值对象归一：空语言/空方向清除（语义为无标注）；xsd 派生挂 toRDF 役
  match value {
    ExpandedValue::Value(literal) => {
      match literal.language {
        Some(lang) if lang is "" => literal.language = None
        _ => ()
      }
      match literal.direction {
        Some(dir) if dir is "" => literal.direction = None
        _ => ()
      }
      Ok(ExpandedValue::Value(literal))
    }
    other => Ok(other)
  }
}

///|
impl Expander for StandardExpander with fn set_language(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("set_language pending"))
}

///|
impl Expander for StandardExpander with fn set_direction(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("set_direction pending"))
}

///|
impl Expander for StandardExpander with fn expand_list(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_list pending"))
}

///|
impl Expander for StandardExpander with fn expand_set(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_set pending"))
}

///|
impl Expander for StandardExpander with fn expand_graph(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_graph pending"))
}

///|
impl Expander for StandardExpander with fn expand_reverse(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_reverse pending"))
}

///|
impl Expander for StandardExpander with fn expand_nest(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_nest pending"))
}

///|
impl Expander for StandardExpander with fn expand_included(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
  _active_property : String?,
  _options : JsonLdOptions,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("expand_included pending"))
}

///|
impl Expander for StandardExpander with fn set_index(
  _self,
  _active : ActiveContext,
  _value : JsonValue,
) -> Result[ExpandedValue, JsonLdError] {
  Err(JsonLdError::Unsupported("set_index pending"))
}

///|
/// ContextProcessor 落码（③批）：@context 声明 → ActiveContext 构建/继承（简单形态）。
/// 继承：terms/vocab/base 父副本（ADR-JL-4 不可变语义 = 副本）；数组 context = 逐项合并。
/// 落码范围：term→IRI 字符串定义、@vocab（相对先经 base）、@base、term=null（移除）。
/// 未落（红而非错）：term 定义对象形态（@type/@container——⑤批）、@language/@direction
/// 默认、@version/@propagate/@import、远程 context。
impl ContextProcessor for StandardExpander with fn process_context(
  _self,
  active : ActiveContext,
  local_context : JsonValue,
  _options : JsonLdOptions,
) -> Result[ActiveContext, JsonLdError] {
  // 继承：父 terms 复制
  let new_terms : Map[String, TermDefinition] = Map([])
  for k, td in active.terms {
    new_terms[k] = td
  }
  let mut vocab = active.vocab
  let mut base = active.base
  match local_context {
    JsonValue::String(_) =>
      return Err(JsonLdError::Unsupported("remote context pending later batch"))
    JsonValue::Array(items) => {
      // 数组 context：逐项合并（前项产出为后项输入）
      let mut current = active
      for item in items {
        match
          ContextProcessor::process_context(_self, current, item, _options) {
          Ok(next) => current = next
          Err(e) => return Err(e)
        }
      }
      Ok(current)
    }
    JsonValue::Object(pairs) => {
      let keyword_owner : Map[String, String] = Map([])
      for pair in pairs {
        match pair.0 {
          "@vocab" =>
            match pair.1 {
              JsonValue::String(v) => {
                // 套件 oracle（#t0092[1.1] vs #t0115/#t0116[1.0]）：
                // 1.0 模式 = @vocab 非绝对（含相对/空串）即 invalid——对原始值判，
                // base 不补救；1.1 模式 = 对 base raw 拼接（#t0092：空串 → base
                // 本身、`../` 原样不消点段）
                if _options.processing_mode is JsonLd10 &&
                  !is_valid_absolute_iri(v) {
                  return Err(
                    JsonLdError::InvalidContext("invalid vocab mapping"),
                  )
                }
                let resolved = if is_valid_absolute_iri(v) {
                  v
                } else {
                  match base {
                    Some(b) => "\{b}\{v}"
                    None => v
                  }
                }
                vocab = Some(resolved)
              }
              JsonValue::Null => vocab = None
              _ =>
                return Err(
                  JsonLdError::InvalidContext("@vocab must be string or null"),
                )
            }
          "@base" =>
            match pair.1 {
              // 相对 @base：合并 + ".." 弹段（resolve_base_value）；绝对 → 原样
              JsonValue::String(b) =>
                base = Some(resolve_base_value(b, active.base))
              JsonValue::Null => base = None
              _ =>
                return Err(
                  JsonLdError::InvalidContext("@base must be string or null"),
                )
            }
          "@version" =>
            // 1.1 API：@version 仅接受 json-ld-1.1（本引擎默认即 1.1 语义 = no-op）；
            // 其他值 → invalid @version value。1.0 模式切换（ActiveContext 载入
            // processing_mode）挂后续批
            match pair.1 {
              JsonValue::String("json-ld-1.1") => ()
              JsonValue::String(v) =>
                return Err(
                  JsonLdError::InvalidContext("invalid @version value (\{v})"),
                )
              _ =>
                return Err(
                  JsonLdError::InvalidContext("@version must be a string"),
                )
            }
          "@language" | "@direction" | "@propagate" | "@import" =>
            return Err(
              JsonLdError::Unsupported(
                "context keyword pending later batches (\{pair.0})",
              ),
            )
          other => {
            // 关键字别名冲突（#ter26 oracle）：同关键字第二别名 → colliding keywords
            if other is "id" || other is "ID" {
              match keyword_owner.get("@id") {
                Some(prev_owner) =>
                  if prev_owner != other {
                    return Err(
                      JsonLdError::InvalidContext("colliding keywords"),
                    )
                  }
                None => keyword_owner["@id"] = other
              }
            }
            // term 名不得为相对 IRI 路径（#ter48 oracle："./something" →
            // invalid IRI mapping）——"." 开头的键是相对路径形态，不能作 term
            if other.get_char(0) is Some('.') {
              return Err(JsonLdError::InvalidIri("invalid IRI mapping"))
            }
            // term 定义（简单形态：term → IRI 字符串；null = 移除）。
            // 值 IRI 展开：vocab 位、对 in-progress terms 查表
            // （#t0072 oracle：重定义为自身时用 @vocab，非旧 term 定义）
            match pair.1 {
              JsonValue::String(iri) => {
                // #t0072 oracle：值 = term 自身 + @vocab 已声明 → @vocab 拼接
                // （重定义为自身时 @vocab 生效，非旧 term 定义查表）
                let expanded = if iri == other && vocab is Some(v) {
                  "\{v}\{other}"
                } else {
                  let building = ActiveContext::{
                    base,
                    vocab,
                    terms: new_terms,
                  }
                  match
                    IriExpander::expand_iri(_self, building, iri, false, true) {
                    Ok(k) => k
                    Err(e) => return Err(e)
                  }
                }
                new_terms[other] = TermDefinition::{
                  iri: Some(expanded),
                  datatype: None,
                  container: None,
                }
              }
              JsonValue::Null => new_terms.remove(other)
              _ =>
                return Err(
                  JsonLdError::Unsupported(
                    "expanded term definition pending term batch (\{other})",
                  ),
                )
            }
          }
        }
      }
      Ok(ActiveContext::{ base, vocab, terms: new_terms, })
    }
    _ =>
      Err(JsonLdError::InvalidContext("local context must be object or array"))
  }
}
