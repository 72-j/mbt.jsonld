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
/// 真关键字判定（REC 1.7 关键字表——keyword 形态 + 表成员；"@iri" 等
/// keyword 形态但非表成员者**不是**关键字）
fn is_keyword(value : String) -> Bool {
  value
  is ("@base"
  | "@container"
  | "@context"
  | "@direction"
  | "@graph"
  | "@id"
  | "@import"
  | "@included"
  | "@index"
  | "@json"
  | "@language"
  | "@list"
  | "@nest"
  | "@none"
  | "@prefix"
  | "@propagate"
  | "@protected"
  | "@reverse"
  | "@set"
  | "@type"
  | "@value"
  | "@version"
  | "@vocab")
}

///|
/// keyword 形态判定（戊批——REC 3.1："@" 后跟一个或多个纯 ALPHA；REC 关键字
/// 均为此形态。"@" 空尾 / 含 "." 等非 ALPHA = 非 keyword 形态，可作普通 term
/// ——#t0119 oracle：@/@foo.bar 可用、@ignoreMe（纯 ALPHA）被忽略）
fn has_keyword_form(value : String) -> Bool {
  match value.get_char(0) {
    Some('@') => {
      let mut seen_at = false
      let mut alpha_count = 0
      let mut all_alpha = true
      for ch in value {
        if !seen_at {
          seen_at = true
        } else if ch is ('a'..='z' | 'A'..='Z') {
          alpha_count += 1
        } else {
          all_alpha = false
          break
        }
      }
      all_alpha && alpha_count >= 1
    }
    _ => false
  }
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
/// authority 根截取（scheme://authority——绝对路径引用替换 path 时的保留段；
/// 平台中立字符迭代，避免切片抛错面差异）。无 scheme 冒号或 scheme 后非 "//"
/// → None（链式相对 base 无 authority 形态，落回相对合并）
fn authority_root(value : String) -> String? {
  let scheme_end = match colon_index(value) {
    Some(at) => at
    None => return None
  }
  if !(value.get_char(scheme_end + 1) is Some('/') &&
    value.get_char(scheme_end + 2) is Some('/')) {
    return None
  }
  // scheme:// 后逐字符累加至首个 "/"（authority 终点；无 → 至串尾）
  let root = StringBuilder()
  let mut i = 0
  for ch in value {
    if i > scheme_end + 2 && ch is '/' {
      break
    }
    root <+ "\{ch}"
    i += 1
  }
  Some(root.to_string())
}

///|
/// RFC 3986 5.2.3 merge：value 绝对路径引用（"/" 开头）→ authority 保留、
/// path 整体替换（#t0051 oracle：/issue/1 → https://w3c.github.io/issue/1）；
/// value 相对 → base 截最后 "/"（含）+ value；base 无 "/" → 补根 "/"
/// （#t0129/#t0130 oracle：/example + relative-iri → /example/relative-iri）
fn merge_base_reference(base : String, reference : String) -> String {
  if base is "" {
    return reference
  }
  // 空引用（RFC 3986 5.2：R.path 空且无 query/fragment ⇒ T = base 原样——
  // toRdf #t0016 oracle：@id "" 取文档全 URL 含文件名，不得坍缩到目录）
  if reference is "" {
    return base
  }
  // base 自身 fragment 剥除（RFC 3986 5.2：fragment 不参与 base 解析——
  // #t0029 oracle：base "file#with-a-fragment" + "#fragment-works" →
  // "file#fragment-works"）
  let base = match base.find("#") {
    Some(idx) => base[:idx].to_owned()
    None => base
  }
  // scheme 相对引用（"//" 开头 = 引用自带 authority——RFC 3986 5.2.3：
  // 保留 base scheme、authority 整体换新，#t0029 oracle）
  if reference.get_char(0) is Some('/') && reference.get_char(1) is Some('/') {
    match colon_index(base) {
      Some(at) => {
        let scheme = base[:at + 1].to_owned()
        return "\{scheme}\{reference}"
      }
      None => ()
    }
  }
  // 同文档 fragment 引用（#t0029 oracle：#fragment-works 锚定 base 全 URL，
  // 不动 path）；base 自带 fragment 场景套件内不出现
  if reference.get_char(0) is Some('#') {
    return "\{base}\{reference}"
  }
  // 查询引用（"?" 开头）：剥 base 自身 query 后拼接（RFC 3986 5.2.3）
  if reference.get_char(0) is Some('?') {
    match base.find("?") {
      Some(idx) => {
        let head = base[:idx].to_owned()
        return "\{head}\{reference}"
      }
      None => return "\{base}\{reference}"
    }
  }
  if reference.get_char(0) is Some('/') {
    match authority_root(base) {
      Some(root) => return "\{root}\{reference}"
      None => () // 无 authority 形态 → 落相对合并
    }
  }
  // 相对合并（RFC 5.2.3）：idx 落在 scheme 后 "//" 尾内（http://a 的 idx=6）
  // ⇒ base.path 空 ⇒ 补根 "/"；否则 idx = 目录段截位 ⇒ 截最后 "/"（含）+
  // 引用（目录替换——#t0131/#t0132 oracle：tag:example/foo + a →
  // tag:example/a）。authority 感知边界取代 idx>6 魔数（短 scheme 角：
  // a://b/c、ex:/a 曾误走补根臂——套件不可达，wbtest oracle 钉）
  match base.rev_find("/") {
    Some(idx) => {
      let authority_slash_end = match colon_index(base) {
        Some(at) =>
          if base.get_char(at + 1) is Some('/') &&
            base.get_char(at + 2) is Some('/') {
            at + 2
          } else {
            -1
          }
        None => -1
      }
      if idx <= authority_slash_end {
        "\{base}/\{reference}"
      } else {
        let head = base[:idx + 1].to_owned()
        "\{head}\{reference}"
      }
    }
    None =>
      // base 全串无 "/"（B组①——scheme-only 形："tag:example"/"ex:"）：
      // RFC 5.2.3 base.path 无目录段 ⇒ 引用替换整段路径、scheme 保留
      //（#t0130/#tli11 oracle：tag:example+a → tag:a、ex:+test → ex:test）
      match colon_index(base) {
        Some(at) => "\{base[:at + 1].to_owned()}\{reference}"
        None => "\{base}\{reference}"
      }
  }
}

///|
/// authority/path 切分（RFC 3986 5.2.4 点段消除只作用于 path——平台中立
/// 字符迭代拼装）。无 scheme://authority 形态 → ("", 全串)
fn split_authority_path(value : String) -> (String, String) {
  let scheme_end = match colon_index(value) {
    Some(at) => at
    None => return ("", value)
  }
  if !(value.get_char(scheme_end + 1) is Some('/') &&
    value.get_char(scheme_end + 2) is Some('/')) {
    return ("", value)
  }
  let authority = StringBuilder()
  let path = StringBuilder()
  let mut in_path = false
  let mut i = 0
  for ch in value {
    if i > scheme_end + 2 && ch is '/' {
      in_path = true
    }
    if in_path {
      path.write_string("\{ch}")
    } else {
      authority.write_string("\{ch}")
    }
    i += 1
  }
  (authority.to_string(), path.to_string())
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
  // A组①（#t0122 s091 oracle vs #t0127 s296 反例族）：引用拆 = 路径部分
  // （首个 ?/# 之前）+ 尾巴（query/fragment 原样照挂）。**路径部分为空 ⇒
  // merge 原样、不进路径处理**（RFC 5.2：R.path 未定义时 T.path = Base.path
  // 词面——s091 base "/./" 保留）；非空 ⇒ 段算法跑 merge 后整条路径（s296
  // ".?a=b" → base 目录 + "?a=b"）。
  let mut cut = -1
  for i in 0..<value.length() {
    let ch = value.get_char(i)
    if ch == Some('?') || ch == Some('#') {
      cut = i
      break
    }
  }
  let ref_path = if cut >= 0 { value[:cut].to_owned() } else { value }
  let ref_suffix = if cut >= 0 { value[cut:].to_owned() } else { "" }
  if ref_path is "" {
    return merge_base_reference(prev, value)
  }
  let merged = merge_base_reference(prev, ref_path)
  let (authority, full_path) = split_authority_path(merged)
  if authority is "" {
    return merged
  }
  // A组②（RFC 3986 5.2.4——remove_dot_segments 作用于 **merge 后整条
  // path**，base 贡献段一并消除：#t0091 oracle，base "/./" 不保留；路径
  // 为空时才词面保留——上方 A① 早退）。段源 = full_path **去首段**（首段
  // 恒为根标记 ""，由 seeds=[""] 承担）：斜杠开形（"/x" / "//authority/x"）
  // merge 已换根，full_path 即引用自身路径（base 段不入）；相对形 full_path
  // = base 目录 + 引用（merge 只换尾段），点段规则均匀作用两方贡献段。
  // "//g" 合并后 full_path="" ⇒ 段空 ⇒ 渲染裸 authority（s006 oracle）。
  // 段规则："." 丢弃（**段尾 "." ⇒ 尾斜杠**，s117 "./g/." → "g/"）；".."
  // 弹一段（**守卫 >1 护根标记——超根截停**，#t0029 still-root oracle；
  // **段尾 ".." ⇒ 尾斜杠**）；**内部空段保真**（RFC 不折叠 "//"——#t0128
  // base "ab//de" oracle；s303 "../xyz" 弹掉的正是空段 → 单斜杠）；
  // **段尾空段 ⇒ 尾斜杠**。#t0122 s100：/bb/ccc/../../.. → "/"。
  let segs : Array[String] = [""]
  let raw = full_path.split("/").to_array()
  let tokens : Array[String] = []
  for j in 1..<raw.length() {
    tokens.push(raw[j].to_owned())
  }
  let n = tokens.length()
  let mut trailing = false
  for i in 0..<n {
    let seg = tokens[i]
    if seg is ".." {
      // 守卫 >1：segs[0] 是根标记（""），禁弹（钉①——超根截停）
      if segs.length() > 1 {
        let _ = segs.pop()
      }
      if i == n - 1 {
        trailing = true
      }
    } else if seg is "." {
      if i == n - 1 {
        trailing = true
      }
    } else if seg is "" {
      // 空段：内部 = 保真入栈（#t0128）；段尾 = 尾斜杠标记，不入栈
      if i == n - 1 {
        trailing = true
      } else {
        segs.push(seg)
      }
    } else {
      segs.push(seg)
    }
  }
  let out = StringBuilder()
  out.write_string(authority)
  for i, seg in segs {
    // i>0 条件 join：首段（根标记 ""）不产生斜杠——authority 自带 "//"
    if i > 0 {
      out.write_string("/")
    }
    out.write_string(seg)
  }
  if trailing {
    out.write_string("/")
  }
  out.write_string(ref_suffix)
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
    index: None,
    included: None,
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
  document_relative : Bool,
  vocab : Bool,
) -> Result[String, JsonLdError] {
  // 1 keyword：keyword 形态（"@" 后纯 ALPHA ≥1）原样返回——**未知 keyword
  // 亦原样**（节点位由属性门/忽略语义处理，#t0119/#tpr34/#tpr36 oracle）；
  // "@" 空尾或含非 ALPHA（"." 等）= 非 keyword 形态，继续分拣（可命中 term
  // 定义——#t0119 oracle：@/@foo.bar term 可用）
  if has_keyword_form(value) {
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
  // 4 compact：prefix ∈ terms 且未被 @prefix:false 抑制（#tpr29 oracle）→
  // 定义 IRI + suffix；**suffix 以 "//" 开头 = 非 compact**（protocol-like
  // authority——#t0067 oracle：http:// 类键不被 term 前缀误吃）
  match colon_index(value) {
    Some(at) => {
      let (prefix, suffix) = split_first_colon(value, at)
      let double_slash = suffix.get_char(0) is Some('/') &&
        suffix.get_char(1) is Some('/')
      if !double_slash {
        match active.terms.get(prefix) {
          Some(td) =>
            if td.is_prefix is Some(false) {
              ()
            } else {
              match td.iri {
                Some(base_iri) => return Ok("\{base_iri}\{suffix}")
                None => ()
              }
            }
          None => ()
        }
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
  // 7 relative（document_relative 门控——「vocab 位 base 门控批」）：
  // vocab 位键展开（docRel=false）→ 原样返回不落 base merge（#t0003 oracle：
  // 未映射 term 须被属性门丢弃，全局注入默认 base 亦不得改变键行为）；
  // document-relative 位（@id/@type 值、coercion 值——#t0051/#t0050/#t0056/
  // #t0057 oracle）→ 复用 resolve_base_value（raw 合并 + RFC 3986 5.2.4
  // 点段消除——#t0029 oracle：./ 与 ../ 相对解析消点段）；无 base → 原样
  if !document_relative {
    return Ok(value)
  }
  match active.base {
    Some(base) => Ok(resolve_base_value(value, Some(base)))
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
/// term 名是否触发一致性检查（REC 4.2.2 @id 臂）：term 名含冒号（非首位、
/// 非末位）或含斜杠（任意位置）——此形态的 term 名本身是一次 IRI 引用，
/// 它自身的展开必须与 IRI 映射一致
fn term_name_has_colon_or_slash(term_name : String) -> Bool {
  let length = term_name.length()
  match colon_index(term_name) {
    Some(at) => if at > 0 && at < length - 1 { return true }
    None => ()
  }
  term_name.contains("/")
}

///|
/// term 名一致性检查（REC 4.2.2 @id 臂 "must be consistent" 条）：term 名的
/// IRI 展开 == 该 term 的 IRI 映射；不符 → invalid IRI mapping。**1.0 模式不做
/// 检查**（#t0026 oracle：1.0 同输入正例）。两个 oracle：
/// #ter43（负·1.1）——长名 rdf:type 别名 @type：1.1 非法 / 1.0 合法；
/// #ter44（负·1.1）——compact 形 term 名映射到别处（v:term → v:somethingElse）
fn StandardExpander::check_term_name_consistency(
  self : StandardExpander,
  building : ActiveContext,
  term_name : String,
  iri_mapping : String,
  options : JsonLdOptions,
) -> Result[Unit, JsonLdError] {
  if options.processing_mode is JsonLd10 {
    return Ok(())
  }
  if !term_name_has_colon_or_slash(term_name) {
    return Ok(())
  }
  match IriExpander::expand_iri(self, building, term_name, false, true) {
    Ok(self_expanded) =>
      if self_expanded == iri_mapping {
        Ok(())
      } else {
        Err(JsonLdError::InvalidIri("invalid IRI mapping"))
      }
    Err(e) => Err(e)
  }
}

///|
/// propagate=false 时的 previous context 置位（REC 4.1.2 步 3）：result 尚无
/// previous 才置为传入的 active（"已有 previous 不覆盖"——外层非传播 context 的
/// 快照优先保留）；propagate=true = 不置位。快照共享 active.terms 引用（本引擎
/// 的 context 构造一律先复制 terms 再改，输入 map 视为不可变）
fn previous_after(active : ActiveContext, propagate : Bool) -> PreviousContext? {
  match active.previous {
    Some(previous) => Some(previous)
    None =>
      if propagate {
        None
      } else {
        Some(PreviousContext::{
          base: active.base,
          vocab: active.vocab,
          terms: active.terms,
        })
      }
  }
}

///|
/// 回退到 previous context（REC 5.1.2 映射分支："set active context to previous
/// context from active context"）——无 previous = 原样返回（顶层/传播位）
fn StandardExpander::revert_previous(active : ActiveContext) -> ActiveContext {
  match active.previous {
    Some(previous) =>
      ActiveContext::{
        base: previous.base,
        vocab: previous.vocab,
        terms: previous.terms,
        previous: None,
        default_language: None,
        default_direction: None,
        compact_by_iri: None,
        compact_reverse: None,
        compact_prefixes: None,
      }
    None => active
  }
}

///|
/// 取元素级 `@context` 值（REC 5.1.2 "If element contains the entry @context"）。
/// 只认字面 `@context` 键：关键字别名 @context 被规范禁止（invalid keyword alias）
fn element_context_value(pairs : Array[(String, JsonValue)]) -> JsonValue? {
  for pair in pairs {
    if pair.0 is "@context" {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 键是否展开为指定关键字·**快路**（常数因子优化：形状判定/嗅探/type-scoped 扫描
/// 原先对每个键跑一次完整 IRI 展开——热路径上按"每键一次展开"付学费）。
/// 快路 = 字面命中 或 该键的 term 定义 IRI 就是该关键字；**保守回退**：仅当
/// vocab 含 `@`（病态：vocab 拼接理论上能造出 `"@xxx"`，无 oracle）时才走完整展开。
/// compact 形不可能命中关键字（前缀 IRI 是绝对 IRI，拼接结果不以 `@` 起）⇒ 不必展开。
fn StandardExpander::key_expands_to_keyword(
  self : StandardExpander,
  active : ActiveContext,
  key : String,
  keyword : String,
) -> Bool {
  if key == keyword {
    return true
  }
  match active.terms.get(key) {
    Some(term_definition) =>
      match term_definition.iri {
        Some(iri) => if iri == keyword { return true }
        None => ()
      }
    None => ()
  }
  match active.vocab {
    Some(vocab) =>
      if vocab.contains("@") {
        return match IriExpander::expand_iri(self, active, key, false, true) {
          Ok(expanded) => expanded == keyword
          Err(_) => false
        }
      }
    None => ()
  }
  false
}

///|
/// 值对象/单 @id 形判定（REC 5.1.2 回退门）：映射含任一键展开为 @value，或恰为
/// 单条展开为 @id。两者皆以**回退前** context 判定：
/// #tc015 oracle（单 @id 形不回退，type-scoped @base 仍作用）；
/// #tc020 oracle（值对象形不回退，type-scoped 的 `value:@value` 别名生效）
fn StandardExpander::is_value_or_id_shaped(
  self : StandardExpander,
  active : ActiveContext,
  element : JsonValue,
) -> Bool {
  match element {
    JsonValue::Object(pairs) => {
      for pair in pairs {
        if StandardExpander::key_expands_to_keyword(
            self,
            active,
            pair.0,
            "@value",
          ) {
          return true
        }
      }
      if pairs.length() == 1 &&
        StandardExpander::key_expands_to_keyword(
          self,
          active,
          pairs[0].0,
          "@id",
        ) {
        return true
      }
      false
    }
    _ => false
  }
}

///|
/// type-scoped context 应用（REC 5.1.2 "For each key … where key IRI expands to
/// @type"）：快照 = 传入 active（**元素级 @context 之后**）；@type 键按字典序、
/// 值数组项按字典序逐个套用其 td 的 local context（**propagate=false**，置
/// previous context 供新节点回退）；后套者叠加于前者。
/// oracle：#tc011/#tc017/#tc018（@type 数组序 ≠ 应用序，字典序定胜负）、
/// #tc008（@type 别名 term 亦触发）、#tc014（`[null]` 空化）、#tc026（@propagate
/// true 覆盖默认 false）。非串项跳过（REC "if term is a string"）
fn StandardExpander::apply_type_scoped_contexts(
  self : StandardExpander,
  active : ActiveContext,
  pairs : Array[(String, JsonValue)],
  options : JsonLdOptions,
) -> Result[ActiveContext, JsonLdError] {
  let type_keys : Array[String] = []
  for pair in pairs {
    if StandardExpander::key_expands_to_keyword(self, active, pair.0, "@type") {
      type_keys.push(pair.0)
    }
  }
  type_keys.sort_by(fn(a, b) { a.compare(b) })
  let mut current = active
  for key in type_keys {
    let terms : Array[String] = []
    for pair in pairs {
      if pair.0 == key {
        match pair.1 {
          JsonValue::Array(items) =>
            for item in items {
              match item {
                JsonValue::String(term) => terms.push(term)
                _ => ()
              }
            }
          JsonValue::String(term) => terms.push(term)
          _ => ()
        }
      }
    }
    terms.sort_by(fn(a, b) { a.compare(b) })
    for term in terms {
      // td 查询用快照，应用累积到 current（REC 原文；#tc018 oracle）
      match active.terms.get(term) {
        Some(term_definition) =>
          match term_definition.local_context {
            Some(local_context) =>
              match
                ContextProcessor::process_context(
                  self,
                  current,
                  local_context,
                  ContextFlags::type_scoped().with_context_base_url(
                    term_definition.context_base_url,
                  ),
                  options,
                ) {
                Ok(next) => current = next
                Err(e) => return Err(e)
              }
            None => ()
          }
        None => ()
      }
    }
  }
  Ok(current)
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
  // 属性槽位索引（役P1 批4——⑧平铺属性合并索引化）：同 IRI 属性合并
  // （壬子批 #t0034/#t0114 oracle）原为逐键线性扫全量 properties ⇒ O(P²)。
  // 与 J2 nest 合并索引（函数尾 property_index）同纪律：整段建一次、由
  // merge_property_values 维护、顺序语义不变（先见者占位、逐值追加尾部）。
  let property_index : Map[String, Int] = Map([])
  let reverse_props : Array[(String, Array[ExpandedValue])] = []
  let mut node_graph : Array[ExpandedValue]? = None
  // 节点/值对象位 @index（@index mapping 批——#t0036 oracle；值对象位在收尾挂字面量）
  let mut node_index : String? = None
  // 节点位 @nest 条目收集（nest 纯形批 + scoped-context 批——REC 13.4.14：
  // 主键循环中只收集，循环后延后处理；文档序）。条目携带该键的**属性作用域
  // context**（scoped-context 批——#tc037/#tc038 oracle：@nest 别名 term 的
  // local context 在其值展开时套用）
  let nest_entries : Array[(ActiveContext, JsonValue)] = []
  // Included Blocks 收集（@included 纯形批——主键循环中只收集不展开，
  // 循环后延后处理；值对象位同样收集——#tin05 oracle 保形）
  let included_values : Array[JsonValue] = []
  let included_nodes : Array[ExpandedNode] = []
  let mut literal : ExpandedLiteral? = None
  let mut is_value_object = false
  let mut saw_value = false // @value 成员可见（丙批后缀规则：language-only 值对象丢弃）
  let mut has_datatype = false
  // @type 先至挂起位（#tc020——值对象 @type 在 @value 之前出现时 literal
  // 尚未建，直接赋值落空；@value 建立后统一回填）
  let mut pending_dt : String? = None
  let mut has_language = false
  let mut has_direction = false
  // 元素级 @context 先于主键循环处理（REC 5.1.2 次序：previous 回退 → property-scoped
  // → **元素级 @context** → type-scoped → 主键循环）——文档中排在 @context 之前的键
  // 亦须看到它（#t0073 oracle："@context not first property"）
  let mut current = match element_context_value(pairs) {
    Some(JsonValue::Null) => initial_context(options)
    Some(local_context) =>
      match
        ContextProcessor::process_context(
          self,
          active,
          local_context,
          ContextFlags::element(),
          options,
        ) {
        Ok(next) => next
        Err(e) => return Err(e)
      }
    None => active
  }
  // type-scoped context 快照（REC 5.1.2："Initialize type-scoped context to active
  // context. This is used for expanding values that may be relevant to any previous
  // type-scoped context."）——**@type 值自身**用快照展开（#tc014/#tc018 oracle：
  // 空化/无 vocab 的 type-scoped context 不得影响 @type 值展开），其余键用套用后
  // 的 current
  let type_scoped_context = current
  // 套用 type-scoped contexts（快照=上；应用累积到 current，propagate=false）
  current = match
    StandardExpander::apply_type_scoped_contexts(self, current, pairs, options) {
    Ok(next) => next
    Err(e) => return Err(e)
  }
  // frameExpansion 值 pattern 预扫（spec §8.97 值 pattern 批）：对象含
  // @value/@type/@language 任一**非串形**成分（{} 通配 / 数组清单）⇒ 本对象
  // 为值 pattern 模式——三键全走成分保形（String 形亦保形，免撞值对象
  // datatype/language 门；t0036-45 判定面）
  let mut frame_value_pattern = false
  if options.frame_expansion {
    for scan_pair in pairs {
      match scan_pair.0 {
        "@value" | "@type" | "@language" =>
          if !(scan_pair.1 is JsonValue::String(_)) {
            frame_value_pattern = true
          }
        _ => ()
      }
    }
  }
  for pair in pairs {
    // null IRI 映射 term（"term": null / {"@id": null}——scoped-context 批）：
    // IRI 展开返回 null ⇒ 键整体丢弃（REC 5.1.2：expanded property 为 null 即
    // drop key）。#tin06 oracle：scoped context {"data": null} 下的 "data" 键
    // 丢弃——若按"移除定义"处理则会 vocab 拼成属性，是为误判
    let term_iri_is_null = match current.terms.get(pair.0) {
      Some(term_definition) => term_definition.iri is None
      None => false
    }
    if term_iri_is_null {
      continue
    }
    // 键归一（#ter51 oracle + #t0119 扩）：一律经 IRI 链展开一次——真关键字
    // 原样（keyword 形态步 1）、@-term 键命中查表、别名 term 汇流关键字位
    let expanded_key = match
      IriExpander::expand_iri(self, current, pair.0, false, true) {
      Ok(k) => k
      Err(e) => return Err(e)
    }
    // 关键字位判定按归一键：字面关键字与别名 term 汇流
    let routes_to_keyword = expanded_key.get_char(0) is Some('@')
    // 值 pattern 成分保形（值 pattern 模式——三键含 String 形全保形：
    // @type 串须 IRI 展开、@value/@language 串词形；{} 通配 = 空 pattern
    // 标桩；数组 = 清单摊开；null = 无）
    if frame_value_pattern {
      match expanded_key {
        "@value" | "@type" | "@language" => {
          let component_values : Array[ExpandedValue] = []
          match pair.1 {
            JsonValue::Array(items) =>
              for item in items {
                match
                  self.frame_value_pattern_component(
                    current, expanded_key, item,
                  ) {
                  Ok(Some(one)) => component_values.push(one)
                  Ok(None) => ()
                  Err(e) => return Err(e)
                }
              }
            single_value =>
              match
                self.frame_value_pattern_component(
                  current, expanded_key, single_value,
                ) {
                Ok(Some(one)) => component_values.push(one)
                Ok(None) => ()
                Err(e) => return Err(e)
              }
          }
          properties.push((expanded_key, component_values))
          continue
        }
        _ => ()
      }
    }
    // frameExpansion reverse-term pattern 保形（役52——t0029 判定面）：
    // term 定义带 @reverse ⇒ 值位是**反向 pattern**（非反向 map）——{}
    // 通配/@default 保形入 reverse_props（键 = td 的 reverse IRI）。字面
    // "@reverse" 键（t0028 map 形）走原臂不受扰
    if options.frame_expansion && !frame_value_pattern {
      match current.terms.get(pair.0) {
        Some(term_definition) =>
          match term_definition.reverse {
            Some(rev) => {
              let rev_pattern : ExpandedNode = match pair.1 {
                JsonValue::Object(value_pairs) => {
                  let mut has_default_key = false
                  let default_raw : Array[JsonValue] = []
                  let mut has_value_key = false
                  for vp in value_pairs {
                    if vp.0 is "@default" {
                      has_default_key = true
                      match vp.1 {
                        JsonValue::Array(items) =>
                          for item in items {
                            default_raw.push(item)
                          }
                        single => default_raw.push(single)
                      }
                    }
                    if vp.0 is "@value" {
                      has_value_key = true
                    }
                  }
                  if has_default_key && !has_value_key {
                    let default_values : Array[ExpandedValue] = []
                    for raw in default_raw {
                      match self.frame_preserve_default(current, raw, options) {
                        Ok(values) =>
                          for v in values {
                            default_values.push(v)
                          }
                        Err(e) => return Err(e)
                      }
                    }
                    {
                      id: None,
                      types: [],
                      properties: [("@default", default_values)],
                      reverse_props: [],
                      graph: None,
                      included: None,
                      index: None,
                    }
                  } else {
                    match
                      StandardExpander::expand_element(
                        self,
                        current,
                        pair.1,
                        _active_property,
                        options,
                      ) {
                      Ok(ExpandedValue::Node(pattern_node)) => pattern_node
                      // Err 传播（役53 t0054 同款——嵌套校验错不吞）
                      Err(e) => return Err(e)
                      Ok(_) => frame_empty_pattern()
                    }
                  }
                }
                _ => frame_empty_pattern()
              }
              reverse_props.push((rev, [ExpandedValue::Node(rev_pattern)]))
              continue
            }
            None => ()
          }
        None => ()
      }
    }
    if !routes_to_keyword {
      // frameExpansion 保形（帧旗批——spec §8.96）：帧内性质位对象值
      // ①含 @default 键 ⇒ 默认对象 pattern（其余条目忽略——REC Framing
      // Grammar）；②非值对象形 ⇒ pattern 保形（`{}` 通配 = 展开落空回落
      // 空 pattern）。须先于丢弃预扫描（`{}` 通配会撞 drop-lang-only 门）。
      // 值对象形（@value）照常规路径（值 pattern 本就展开为 Value）；
      // @id/@type 位通配/数组形不在本批（t0023+/t0064 批）
      if options.frame_expansion {
        match pair.1 {
          JsonValue::Object(value_pairs) => {
            // 键合法性门（役53 tg010——保形臂与常规臂同规：不可展开键
            // （相对词无 base/无 term）即弃——REC "expanded property 为
            // null 即 drop"；"@graph" map 形帧样 subject 相对键 null 误发
            // 根因）
            if !(is_valid_absolute_iri(expanded_key) ||
              is_bnode_label(expanded_key)) {
              continue
            }
            let mut has_value_key = false
            let mut has_default_key = false
            let default_raw : Array[JsonValue] = []
            for vp in value_pairs {
              if vp.0 is "@value" {
                has_value_key = true
              }
              if vp.0 is "@default" {
                has_default_key = true
                match vp.1 {
                  JsonValue::Array(items) =>
                    for item in items {
                      default_raw.push(item)
                    }
                  single => default_raw.push(single)
                }
              }
            }
            if !has_value_key {
              if has_default_key {
                // 默认对象 pattern = 仅 @default 性质的 Node pattern
                // （值保形见 frame_preserve_default；数组默认值摊开）
                let default_values : Array[ExpandedValue] = []
                for raw in default_raw {
                  match self.frame_preserve_default(current, raw, options) {
                    Ok(values) =>
                      for v in values {
                        default_values.push(v)
                      }
                    Err(e) => return Err(e)
                  }
                }
                properties.push(
                  (
                    expanded_key,
                    [
                      ExpandedValue::Node({
                        id: None,
                        types: [],
                        properties: [("@default", default_values)],
                        reverse_props: [],
                        graph: None,
                        included: None,
                        index: None,
                      }),
                    ],
                  ),
                )
                continue
              }
              // @list 模式保形（t0057/58——REC Framing Grammar list
              // pattern）：帧性质值 = list 对象 ⇒ List pattern（项逐个
              // pattern 展开——值对象形落 Value pattern、节点形落 Node
              // pattern），不能落节点位（@list 键在节点位即弃 = 空
              // pattern = 幽灵全形嵌入）
              let mut list_raw : JsonValue? = None
              for vp in value_pairs {
                if vp.0 is "@list" {
                  list_raw = Some(vp.1)
                }
              }
              match list_raw {
                Some(raw_items) => {
                  let items = match raw_items {
                    JsonValue::Array(items) => items
                    single => [single]
                  }
                  let list_pattern_items : Array[ExpandedValue] = []
                  for item in items {
                    match
                      StandardExpander::expand_element(
                        self, current, item, _active_property, options,
                      ) {
                      Ok(one) => list_pattern_items.push(one)
                      Err(e) => return Err(e)
                    }
                  }
                  properties.push(
                    (
                      expanded_key,
                      [ExpandedValue::List(list_pattern_items, index=None)],
                    ),
                  )
                  continue
                }
                None => ()
              }
              // pattern 保形：正常展开，落空回落空 pattern（`{}` 通配）
              let pattern_value = match
                StandardExpander::expand_element(
                  self,
                  current,
                  pair.1,
                  _active_property,
                  options,
                ) {
                Ok(ExpandedValue::Node(pattern_node)) => pattern_node
                // Err 传播（役53 t0054——嵌套帧文法校验错不得被落空臂吞）
                Err(e) => return Err(e)
                Ok(_) => {
                  let fresh : ExpandedNode = {
                    id: None,
                    types: [],
                    properties: [],
                    reverse_props: [],
                    graph: None,
                    included: None,
                    index: None,
                  }
                  fresh
                }
              }
              properties.push(
                (expanded_key, [ExpandedValue::Node(pattern_value)]),
              )
              continue
            }
          }
          _ => ()
        }
      }
      // 值对象形态的**整体丢弃**预扫描（REC：被丢弃的值对象其属性不产出；
      // 区别于 t0004 空数组字面值保留）：
      // - @value: null（#t0019 oracle）
      // - 仅 @language/@direction 无 @value（#t0008 oracle：drop-lang-only）
      if pair.1 is JsonValue::Object(value_pairs) {
        let mut has_value_member = false
        let mut has_value_null = false
        let mut only_lang_dir = true
        for vp in value_pairs {
          match vp.0 {
            "@value" => {
              has_value_member = true
              if vp.1 is JsonValue::Null {
                has_value_null = true
              }
            }
            "@language" | "@direction" | "@type" => ()
            _ => only_lang_dir = false
          }
        }
        // @json 值对象豁免（#tjs22 oracle：@type @json 的 null 字面量保留）
        let is_json_value = StandardExpander::is_json_value_object(
          self, current, value_pairs,
        )
        if (has_value_null || (only_lang_dir && !has_value_member)) &&
          !is_json_value {
          continue
        }
      }
      // null 值属性整体丢弃（#t0003 oracle；区别于空数组字面值保留——
      // #t0004 oracle：set3: [] 保留）；**@json term 豁免**——null 即
      // JSON null 字面量（#tjs18 oracle）
      if pair.1 is JsonValue::Null {
        let json_null_member = match current.terms.get(pair.0) {
          Some(term_definition) => term_definition.datatype is Some("@json")
          None => false
        }
        if !json_null_member {
          continue
        }
      }
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
      // reverse 项路由（reverse 批——#t0042/#t0049 oracle）：值进主体
      // @reverse 映射；值对象/@list 形态 → invalid reverse property value
      //（#ter36 oracle）
      match current.terms.get(pair.0) {
        Some(term_definition) =>
          match term_definition.reverse {
            Some(rev) => {
              for v in values {
                match v {
                  ExpandedValue::List(_) | ExpandedValue::Value(_) =>
                    return Err(
                      JsonLdError::InvalidValue(
                        "invalid reverse property value",
                      ),
                    )
                  _ => ()
                }
              }
              reverse_props.push((rev, values))
              continue
            }
            None => ()
          }
        None => ()
      }
      // 键合法性：绝对 IRI 或 bnode 标签（规范：expanded property 可为 blank
      // node identifier——scheme-ALPHA 收紧后 bnode 在此显式放行）；
      // 空数组属性无条件保留（#t0004 oracle：set1~set5 无 term 定义亦保留
      // "set1": [] 空数组——键合法性门不受影响）；同 IRI 属性合并（壬子批——
      // #t0034/#t0114 oracle：多键同展一 IRI → 单键累加，按输入文档顺序）
      if is_valid_absolute_iri(expanded_key) || is_bnode_label(expanded_key) {
        // 同 IRI 属性合并（壬子批 #t0034/#t0114 oracle：多键同展一 IRI →
        // 单键累加，按输入文档顺序）——役P1 批4 索引化（原逐键线性扫 ⇒
        // O(P²)；槽位语义与 merge_property_values 全同）
        merge_property_values(
          properties,
          property_index,
          (expanded_key, values),
        )
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
              Ok(expanded) =>
                // keyword 形非关键字（@1*ALPHA）= REC §5.2 IRI 展开**返回
                // null**（"reserved for future use... ignored"）——节点保留、
                // id 位字面 null（t0122 oracle："@ignoreMe" → {"@id": null}；
                // "@"/"@foo.bar" 非 keyword 形 → 正常 base 拼接为绝对 IRI）
                if has_keyword_form(expanded) && !is_keyword(expanded) {
                  node_id = Some(EXPLICIT_NULL_ID)
                } else {
                  // REC @id 步无绝对性校验——@base:null 后相对值**原样保留**
                  //（t0060 oracle："../document-relative"/"#document-relative"
                  // 保相对；此前此处 II 的 ter48 oracle 实际落在 term 名臂）
                  node_id = Some(expanded)
                }
              Err(e) => return Err(e)
            }
          _ =>
            if options.frame_expansion {
              // @id 位 pattern 保形（帧旗批——t0032/33 判定面）：数组 IRI
              // 清单（逐 IRI 当前 context 展开）/ `{}` 通配（空 pattern 标桩）
              let id_patterns : Array[ExpandedValue] = []
              match pair.1 {
                JsonValue::Array(items) =>
                  for item in items {
                    match item {
                      JsonValue::String(iri) =>
                        if is_bnode_label(iri) {
                          // 负例 t0052（REC 帧 @id 值域——valid IRI，
                          // bnode 标识符不在册 ⇒ invalid frame）
                          return Err(
                            JsonLdError::InvalidValue(
                              "invalid frame: @id must not include a blank node identifier",
                            ),
                          )
                        } else {
                          match
                            IriExpander::expand_iri(
                              self, current, iri, true, false,
                            ) {
                            Ok(expanded) =>
                              id_patterns.push(literal_of(expanded, None))
                            Err(e) => return Err(e)
                          }
                        }
                      JsonValue::Object(_) =>
                        id_patterns.push(
                          ExpandedValue::Node(frame_empty_pattern()),
                        )
                      _ => ()
                    }
                  }
                JsonValue::Object(_) =>
                  id_patterns.push(ExpandedValue::Node(frame_empty_pattern()))
                _ => ()
              }
              properties.push(("@id", id_patterns))
            } else {
              return Err(
                JsonLdError::InvalidValue("@id value must be a string"),
              )
            }
        }
      }
      // @type 双侧：值对象内 = datatype（coercion 形态 A）；节点侧 = 类型数组。
      // 值展开一律用 **type-scoped 快照**（REC 5.1.2 @type 步："IRI expanding
      // each of its values using type-scoped context for active context"；
      // #tc014/#tc018 oracle）。值对象性预扫（#tc020——@type 在 @value 之前
      // 出现时 is_value_object 尚未置位，文档序依赖 ⇒ 键形态先判）
      "@type" => {
        // frameExpansion @type 位 pattern 保形（帧旗批——t0031 match-none /
        // {} 通配判定面）：数组（IRI 清单，可混 {} 通配）/ 对象 {} 通配 ⇒
        // properties @ 键（空数组 = match-none 保形）；串形走 types 字段
        // 原路（t0005/t0026 oracle 不扰）
        // 可达性注记（役C1 批1 2026-10-06）：本 pattern 带仅经**别名键**携带
        // 非串值可达——frame_value_pattern 预扫（扫原始键）会把字面 "@type"
        // 的 Array/Object/Null 值劫往值 pattern 成分带（成分带内有 bnode 拒
        // 孪生门）；别名 term（如 "type"→"@type"）预扫看不到原始键，携非串值
        // 直达此处。拆带前须先统一预扫键口径（扩到别名展开后键）——那是语义
        // 变更，非清理，勿单方面动手。
        if options.frame_expansion {
          let pattern_form = match pair.1 {
            JsonValue::Array(_) => true
            JsonValue::Object(_) => true
            _ => false
          }
          if pattern_form {
            let type_patterns : Array[ExpandedValue] = []
            match pair.1 {
              JsonValue::Array(items) =>
                for item in items {
                  match item {
                    JsonValue::String(t) =>
                      if is_bnode_label(t) {
                        // 负例 t0053（REC 帧 @type 值域同 @id——bnode
                        // 标识符不在册 ⇒ invalid frame）
                        return Err(
                          JsonLdError::InvalidValue(
                            "invalid frame: @type must not include a blank node identifier",
                          ),
                        )
                      } else {
                        match
                          IriExpander::expand_iri(
                            self, type_scoped_context, t, true, true,
                          ) {
                          Ok(expanded) =>
                            type_patterns.push(literal_of(expanded, None))
                          Err(e) => return Err(e)
                        }
                      }
                    JsonValue::Object(default_pairs) => {
                      // @type default 对象保形（t0064——REC "@type MAY be a
                      // map with a @default entry…MUST preserve"；余键
                      // MUST be ignored）。@default 串 = type-scoped IRI
                      // 展开；Node pattern 携 @default IRI 字面
                      let expanded_default = self.expand_type_default_object(
                        type_scoped_context, default_pairs,
                      )
                      type_patterns.push(expanded_default)
                    }
                    _ => ()
                  }
                }
              JsonValue::Object(default_pairs) => {
                let expanded_default = self.expand_type_default_object(
                  type_scoped_context, default_pairs,
                )
                type_patterns.push(expanded_default)
              }
              _ => ()
            }
            properties.push(("@type", type_patterns))
            continue
          }
        }
        if StandardExpander::has_value_key_shaped(self, current, pairs) {
          is_value_object = true
        }
        match pair.1 {
          JsonValue::String(t) =>
            if is_value_object {
              // 形态 A：显式 @type → datatype（合法性钉——#t0123）
              match
                IriExpander::expand_iri(
                  self, type_scoped_context, t, true, true,
                ) {
                Ok(dt) =>
                  if dt is "@json" {
                    // @json 值对象直通（丁批——#tjs15/#tjs16 oracle）：datatype
                    // = @json，@value 允许任意 JSON（见 @value 臂 Array/Object）
                    has_datatype = true
                    match literal {
                      Some(l) => l.datatype = Some("@json")
                      None => pending_dt = Some("@json")
                    }
                  } else if !is_valid_absolute_iri(dt) {
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
                      None => pending_dt = Some(dt)
                    }
                  }
                Err(e) => return Err(e)
              }
            } else {
              match
                IriExpander::expand_iri(
                  self, type_scoped_context, t, true, true,
                ) {
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
                      IriExpander::expand_iri(
                        self, type_scoped_context, iri, true, true,
                      ) {
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
      }
      "@value" => {
        // @value：值对象核心（string/number/bool 词形保形；null → 值对象丢弃）
        is_value_object = true
        saw_value = true
        match pair.1 {
          JsonValue::Null =>
            // @json 值对象（#tjs22 oracle）：null = JSON null 字面量保留
            if StandardExpander::is_json_value_object(self, current, pairs) {
              literal = Some(ExpandedLiteral::{
                value: "",
                datatype: Some("@json"),
                language: None,
                direction: None,
                raw: Some(JsonValue::Null),
                index: None,
                included: None,
              })
            } else {
              literal = None
            }
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
                    index: None,
                    included: None,
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
                    index: None,
                    included: None,
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
                    index: None,
                    included: None,
                  }
              },
            )
          JsonValue::Array(_) | JsonValue::Object(_) => {
            // @json 值对象（丁批——#tjs15/#tjs16 oracle）：@type 为 "@json"
            // 时，@value 允许任意 JSON（对象/数组原样入 raw）
            let is_json_value = StandardExpander::is_json_value_object(
              self, current, pairs,
            )
            if is_json_value {
              literal = Some(ExpandedLiteral::{
                value: "",
                datatype: Some("@json"),
                language: None,
                direction: None,
                raw: Some(pair.1),
                index: None,
                included: None,
              })
            } else {
              return Err(
                JsonLdError::InvalidValue(
                  "@value must be string, number, boolean or null",
                ),
              )
            }
          }
        }
      }
      "@language" =>
        // @language：与 datatype 互斥（#ter38）；键序无关（先记后合）；
        // language-only 对象 = 值对象形态（t0008：无 @value 成员 → 丢弃）
        match pair.1 {
          JsonValue::String(lang) => {
            if has_datatype {
              return Err(JsonLdError::InvalidValue("invalid value object"))
            }
            is_value_object = true
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
                  index: None,
                  included: None,
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
        // @direction：与 datatype 互斥（#tdi09）；direction-only 对象同值对象
        // 形态（t0008 同族）
        match pair.1 {
          JsonValue::String(dir) => {
            if has_datatype {
              return Err(JsonLdError::InvalidValue("invalid value object"))
            }
            is_value_object = true
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
                  index: None,
                  included: None,
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
        // 已在主键循环前处理（REC 5.1.2 次序；#t0073 oracle）——此处跳过
        continue
      // 节点/值对象位 @index（REC 13.4.6："If value is not a string, an invalid
      // @index value error"；值对象位由结果挂字面量——#t0036 oracle：节点与字面量
      // 条目均可带 @index，且条目**已有** @index 保留）
      "@index" =>
        match pair.1 {
          JsonValue::String(index_value) => node_index = Some(index_value)
          _ => return Err(JsonLdError::InvalidValue("invalid @index value"))
        }
      "@reverse" =>
        // @reverse 节点位（reverse 批——#t0037/#t0039/#t0064 oracle）：
        // 值须 map（映射 IRI → 节点值，键经 vocab 展开，值经 term 位展开）；
        // 非 map → invalid @reverse value（#ter33 oracle）
        match pair.1 {
          JsonValue::Object(rev_pairs) =>
            for rev_pair in rev_pairs {
              // 反向映射键不得为关键字（#ter25 oracle：invalid reverse
              // property map）
              if rev_pair.0.get_char(0) is Some('@') {
                return Err(
                  JsonLdError::InvalidValue("invalid reverse property map"),
                )
              }
              let rev_key = match
                IriExpander::expand_iri(self, current, rev_pair.0, false, true) {
                Ok(k) => k
                Err(e) => return Err(e)
              }
              // 未映射/相对键丢弃（#t0065 oracle："Drop unmapped keys in
              // reverse map"——非绝对 IRI 的键不产出反向条目）
              if !is_valid_absolute_iri(rev_key) {
                continue
              }
              match
                StandardExpander::expand_term_values_inner(
                  self,
                  current,
                  rev_pair.0,
                  rev_pair.1,
                  Some(rev_pair.0),
                  options,
                ) {
                Ok(vs) => {
                  // frameExpansion：反向映射值展开落空（{} 通配 pattern——
                  // t0029 别名 reverse 判定面）⇒ 空 pattern 保形入
                  // reverse_props（常规路径空值静默丢）
                  if options.frame_expansion && vs.is_empty() {
                    reverse_props.push(
                      (rev_key, [ExpandedValue::Node(frame_empty_pattern())]),
                    )
                    continue
                  }
                  // 反向映射值须为节点对象（#ter34 oracle：字符串值 →
                  // invalid reverse property value；@list 同禁）
                  for v in vs {
                    match v {
                      ExpandedValue::List(_) | ExpandedValue::Value(_) =>
                        return Err(
                          JsonLdError::InvalidValue(
                            "invalid reverse property value",
                          ),
                        )
                      _ => ()
                    }
                  }
                  // 双反转互消（#t0043 oracle）：@reverse 位键自身为 reverse
                  // term 时，@reverse 位与 td @reverse 两次反转相消——值升级为
                  // 当前节点的普通正属性（键 = td 的 reverse IRI，同正属性位
                  // reverse 项路由键取法）
                  let mut double_reversed : String? = None
                  match current.terms.get(rev_pair.0) {
                    Some(term_definition) =>
                      match term_definition.reverse {
                        Some(rev) => double_reversed = Some(rev)
                        None => ()
                      }
                    None => ()
                  }
                  match double_reversed {
                    Some(rev) => properties.push((rev, vs))
                    None => reverse_props.push((rev_key, vs))
                  }
                }
                Err(e) => return Err(e)
              }
            }
          _ => return Err(JsonLdError::InvalidValue("invalid @reverse value"))
        }
      "@graph" =>
        // 节点位 @graph（文档级批——#t0020 oracle：节点下 @graph 保留于节点
        // 对象；#t0009/#t0021/#t0046 顶层表面化由 engine.serialize_top 门承担）
        match pair.1 {
          JsonValue::Array(items) => {
            let collected : Array[ExpandedValue] = []
            for item in items {
              match
                StandardExpander::append_collection_item(
                  self, current, item, options, collected,
                ) {
                Ok(_) => ()
                Err(e) => return Err(e)
              }
            }
            node_graph = Some(collected)
          }
          JsonValue::Object(_) => {
            // 单节点对象形态归一为数组（规范允许 @graph: {...}）
            let collected : Array[ExpandedValue] = []
            match
              StandardExpander::append_collection_item(
                self,
                current,
                pair.1,
                options,
                collected,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
            node_graph = Some(collected)
          }
          JsonValue::Null => () // @graph: null = 无图内容（先验；无 oracle）
          _ => return Err(JsonLdError::InvalidValue("invalid @graph value"))
        }
      // 节点位 @nest（nest 纯形批——REC 13.4.14：主键循环中只收集不展开，
      // 主键循环后延后对...嵌套值展开与并入见循环后段（REC 步骤 14）。
      // 别名 term（IRI 即 @nest）归一汇流（tn002）。值对象位 @nest 无
      // oracle，循 @id 同款门（#ter37 先例）——invalid value object。
      // 臂体多语句须包块（MoonBit 臂体单表达式纪律——微复现实证）
      "@nest" => {
        if is_value_object {
          return Err(JsonLdError::InvalidValue("invalid value object"))
        }
        // 该键的属性作用域 context（scoped-context 批——#tc037/#tc038
        // oracle：@nest 别名 term 的 @context 作用于其值）
        let nest_context = match
          StandardExpander::apply_property_scoped_context(
            self,
            current,
            pair.0,
            options,
          ) {
          Ok(ctx) => ctx
          Err(e) => return Err(e)
        }
        match pair.1 {
          JsonValue::Array(items) =>
            for item in items {
              nest_entries.push((nest_context, item)) // 数组归一（tn007/tn008）
            }
          JsonValue::Null => () // 数组归一：null = 空（先验）
          single => nest_entries.push((nest_context, single))
        }
      }
      // 节点位 @included（Included Blocks 纯形批——REC：主键循环中只收集，
      // 循环后延后展开。值对象位不拒——#tin05 oracle：值对象内 @included
      // 保形且内层照常展开，区别于 @nest 的 invalid value object 门）
      "@included" =>
        match pair.1 {
          JsonValue::Array(items) =>
            for item in items {
              // 数组元素须为对象（#tin07 oracle：串 → invalid @included value）
              if item is JsonValue::Object(_) {
                included_values.push(item)
              } else {
                return Err(JsonLdError::InvalidValue("invalid @included value"))
              }
            }
          JsonValue::Object(_) => included_values.push(pair.1)
          JsonValue::Null => () // null = 空（先验，循 @graph/@nest 同款）
          _ => return Err(JsonLdError::InvalidValue("invalid @included value"))
        }
      _ =>
        // 未知 @ 键忽略（戊批——同前一枚：@ 前缀非关键字键不产出属性）。
        // frameExpansion 旗保形（帧旗批——spec §8.96）：framing 旗词形入
        // properties（keyword 键名），framing 算法读旗位；@embed 他值校验
        // （⇒ invalid @embed value）随 embed 状态机批
        if options.frame_expansion && is_framing_flag_key(expanded_key) {
          match pair.1 {
            JsonValue::String(word) => {
              // 负例 t0054（REC @embed 值域——true/false/@always/@once/
              // @never/@last；词表外 ⇒ invalid @embed value）
              if expanded_key is "@embed" &&
                !(word
                is ("true" | "false" | "@always" | "@once" | "@never" | "@last")) {
                return Err(JsonLdError::InvalidValue("invalid @embed value"))
              }
              properties.push((expanded_key, [literal_of(word, None)]))
            }
            JsonValue::Bool(flag) =>
              properties.push(
                (
                  expanded_key,
                  [literal_of(if flag { "true" } else { "false" }, None)],
                ),
              )
            _ => ()
          }
        }
    }
  }
  // @nest 延后处理（nest 纯形批——REC 步骤 14）：逐嵌套值须为节点对象且
  // 任一键展开为 @value 即拒（invalid @nest value）；递归展开后并入当前
  // 节点——排自身属性之后（tn003），嵌套 @nest 随递归自展（tn005），数组
  // 元素逐一合并（tn006/tn008）。文档序处理（ordered=false 时 nests 按
  // 收集序——tn004 双 nest 官方比对无序，保序结果同为合法置换）。
  // 合并索引（@nest 异键合并索引化）：**整段建一次**（进入合并前按当前槽位），
  // 之后由 merge_property_values 维护 ⇒ 每条 incoming 对 O(1) 查/追加
  // （原实现每条都线性扫目标数组 ⇒ O(P·M) 二次方）
  let property_index : Map[String, Int] = Map([])
  for i in 0..<properties.length() {
    property_index[properties[i].0] = i
  }
  let reverse_index : Map[String, Int] = Map([])
  for i in 0..<reverse_props.length() {
    reverse_index[reverse_props[i].0] = i
  }
  for nest_entry in nest_entries {
    let nest_context = nest_entry.0
    let nested = nest_entry.1
    let nested_pairs = match nested {
      JsonValue::Object(ps) => ps
      _ => return Err(JsonLdError::InvalidContext("invalid @nest value"))
    }
    // @value 键嗅探（REC 步骤 14："any key within nested value expands to @value"）：
    // 走 `key_expands_to_keyword` 快路（原实现每键跑一次完整 IRI 展开——常数因子）
    for nested_pair in nested_pairs {
      let raw_key = nested_pair.0
      if StandardExpander::key_expands_to_keyword(
          self, nest_context, raw_key, "@value",
        ) {
        return Err(JsonLdError::InvalidContext("invalid @nest value"))
      }
    }
    let nested_expanded = StandardExpander::expand_object(
      self, nest_context, nested, _active_property, options,
    )
    match nested_expanded {
      Ok(Some(ExpandedValue::Node(nested_node))) => {
        // 并入（REC 共享 result 语义）：@id 臂为赋值——嵌套覆盖先见者（先验，
        // 无 oracle）；类型/属性/反向逐值追加——同键并数组（tn006）；
        // @graph 并集（先验，无 oracle）
        match nested_node.id {
          Some(nested_id) => node_id = Some(nested_id)
          None => ()
        }
        for t in nested_node.types {
          types.push(t)
        }
        for prop_pair in nested_node.properties {
          merge_property_values(properties, property_index, prop_pair)
        }
        for rev_pair in nested_node.reverse_props {
          merge_property_values(reverse_props, reverse_index, rev_pair)
        }
        match (node_graph, nested_node.graph) {
          (Some(existing), Some(more)) =>
            for item in more {
              existing.push(item)
            }
          (None, Some(more)) => node_graph = Some(more)
          _ => ()
        }
      }
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  // Included Blocks 延后处理（@included 纯形批——REC：循环后逐条目展开。
  // 条目须为节点对象：@value/@list 键嗅探即拒——#tin08/#tin09 oracle
  // （值对象/list 对象 → invalid @included value）；串值在收集臂已拒
  // （#tin07）。值对象位结果挂字面量（#tin05），节点位挂节点）
  for included_entry in included_values {
    let entry_pairs = match included_entry {
      JsonValue::Object(ps) => ps
      _ => return Err(JsonLdError::InvalidValue("invalid @included value"))
    }
    for entry_pair in entry_pairs {
      if entry_pair.0 is ("@value" | "@list") {
        return Err(JsonLdError::InvalidValue("invalid @included value"))
      }
    }
    // @included 递归调用（REC 13.4.6.2：active property = null、from map 未传）
    // ⇒ 回退门照常作用（类型作用域不跨新节点）
    let included_context = if current.previous is Some(_) &&
      !StandardExpander::is_value_or_id_shaped(self, current, included_entry) {
      StandardExpander::revert_previous(current)
    } else {
      current
    }
    match
      StandardExpander::expand_object(
        self,
        included_context,
        included_entry,
        None,
        options,
      ) {
      Ok(Some(ExpandedValue::Node(included_node))) =>
        included_nodes.push(included_node)
      Ok(None) => () // 空产物（先验；无 oracle——循 @graph: null 同款丢弃）
      Ok(Some(_)) =>
        return Err(JsonLdError::InvalidValue("invalid @included value"))
      Err(e) => return Err(e)
    }
  }
  // 形态判定：值对象（@value 键已见）优先于 node object——
  // @included 结果按形态挂载：值对象位挂字面量（#tin05 保形），节点位挂节点
  if is_value_object {
    match literal {
      Some(found) => {
        // language-only 值对象（无 @value 成员）→ 丢弃（#t0008 oracle：
        // "drop-lang-only" 不产出属性；placeholder literal 不升格）
        if !saw_value {
          return Ok(None)
        }
        // @type 先至挂起位回填（#tc020——文档序 @type 在 @value 前时
        // datatype 挂起至此回填）
        match pending_dt {
          Some(dt) => found.datatype = Some(dt)
          None => ()
        }
        // @language 只配字符串 @value（#ter39 oracle）：@value 非串（raw 记录
        // Number/Bool 词形）而带 @language → invalid language-tagged value；
        // @value: null 在臂内已置 literal=None，先于本校验丢弃（规范次序）
        if has_language && found.raw is Some(_) {
          return Err(JsonLdError::InvalidValue("invalid language-tagged value"))
        }
        // 值对象位 Included Blocks 挂字面量（#tin05 oracle：保形输出）
        if included_nodes.length() > 0 {
          found.included = Some(included_nodes)
        }
        // 值对象位 @index（#t0036 oracle：字面量条目带 @index）
        match node_index {
          Some(index_value) => found.index = Some(index_value)
          None => ()
        }
        Ok(Some(ExpandedValue::Value(found)))
      }
      None => Ok(None) // @value: null → 整个值对象丢弃
    }
  } else {
    Ok(
      Some(
        ExpandedValue::Node(ExpandedNode::{
          id: node_id,
          types,
          properties,
          reverse_props,
          graph: node_graph,
          included: if included_nodes.length() > 0 {
            Some(included_nodes)
          } else {
            None
          },
          index: node_index,
        }),
      ),
    )
  }
}

///|
/// 同键属性值合并·索引版（@nest 异键合并索引化——原实现每条 incoming 线性扫目标
/// 数组，在"异键数 × 条目数"上 **O(P·M) 二次方**，实测 2× 输入 → 4× 耗时）。
/// 目标数组配 `Map[IRI, 槽位下标]`：命中 ⇒ 逐值追加（tn006 逐元素并值），未命中 ⇒
/// 追加新项并登记槽位。**顺序语义与原实现完全一致**（先见者占位、逐值追加到尾部）；
/// 索引由调用方在进入合并前建一次，此后由本函数维护。
/// 类型数组的追加由调用方直推。
fn merge_property_values(
  target : Array[(String, Array[ExpandedValue])],
  index : Map[String, Int],
  pair : (String, Array[ExpandedValue]),
) -> Unit {
  match index.get(pair.0) {
    Some(slot) =>
      // 既有槽位：逐值追加（无需重建索引）
      for v in pair.1 {
        target[slot].1.push(v)
      }
    None => {
      index[pair.0] = target.length()
      target.push(pair)
    }
  }
}

///|
/// 集合位条目展开（文档级 @graph 批）：图内容逐项收集。自由浮动 @set/@list
/// 纯形节点对象先分派（#t0047 oracle）：@set = 透明（其值逐项并入集合）；
/// @list = 整体丢弃（含带属性节点——list 内容随 list 消亡）。
/// 常规分派 = 对象 → expand_object（值对象/free-floating 丢弃——#t0046 oracle：
/// 标量/值对象/@id-only 全弃）；标量 → 直接弃；嵌套数组 = 忽略（先验；无
/// oracle 不扩面）。顶层数组位的自由浮动 @set/@list 未落（同先验）。
fn StandardExpander::append_collection_item(
  self : StandardExpander,
  active : ActiveContext,
  item : JsonValue,
  options : JsonLdOptions,
  out : Array[ExpandedValue],
) -> Result[Unit, JsonLdError] {
  // 自由浮动 @set/@list 纯形节点对象分派（单键纯形才走；混合形态未钉，
  // 走常规分派由关键字臂 Unsupported 报错——先验，防过宽）
  match item {
    JsonValue::Object(pairs) =>
      if pairs.length() == 1 && pairs[0].0 is ("@set" | "@list") {
        match pairs[0].0 {
          "@set" => {
            // @set 透明：其值逐项并入集合（#t0047 set 臂：set 内标量弃、
            // 带属性节点保留）；非数组 = 单元素递归（C 组单元素包裹对偶）
            match pairs[0].1 {
              JsonValue::Array(set_items) =>
                for sub in set_items {
                  match
                    StandardExpander::append_collection_item(
                      self, active, sub, options, out,
                    ) {
                    Ok(_) => ()
                    Err(e) => return Err(e)
                  }
                }
              JsonValue::Null => () // @set: null 透明丢弃（先验）
              single =>
                match
                  StandardExpander::append_collection_item(
                    self, active, single, options, out,
                  ) {
                  Ok(_) => ()
                  Err(e) => return Err(e)
                }
            }
            return Ok(())
          }
          "@list" => return Ok(()) // 整体丢弃：内容随 list 消亡（#t0047 list 臂）
          _ => ()
        }
      }
    _ => ()
  }
  // 常规分派：对象 → expand_object（graph-bearing 节点保留——is_free_floating
  // 已扩）；值对象/free-floating 弃
  match item {
    JsonValue::Object(_) => {
      // @graph / 集合位的递归调用（REC 13.4.6.1：from map 未传）⇒ 回退门照常作用
      let item_context = if active.previous is Some(_) &&
        !StandardExpander::is_value_or_id_shaped(self, active, item) {
        StandardExpander::revert_previous(active)
      } else {
        active
      }
      let expanded : ExpandedValue? = match
        StandardExpander::expand_object(self, item_context, item, None, options) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      match expanded {
        Some(ExpandedValue::Node(node)) =>
          // 图内容 free-floating 门（#t0001 同族——@id-only/无属性节点弃；
          // graph 字段节点不受此门（is_free_floating 已扩））；frameExpansion
          // 豁免——@id-only 帧根/子 pattern 合法（t0032 判定面）
          if is_free_floating(node) && !options.frame_expansion {
            ()
          } else {
            out.push(ExpandedValue::Node(node))
          }
        Some(ExpandedValue::Value(_)) => () // 值对象即弃（#t0046）
        Some(ExpandedValue::List(_)) => () // 自由浮动 list 产物丢弃（防御；与 @list 整弃一致）
        None => () // @value: null → 丢弃
      }
    }
    JsonValue::Null
    | JsonValue::Number(_)
    | JsonValue::Bool(_)
    | JsonValue::String(_) => ()
    JsonValue::Array(_) => () // 嵌套数组于集合位忽略（先验）
  }
  Ok(())
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
  Ok(ExpandedValue::List(out, index=None))
}

///|
/// 内层 term 位展开（容器应用已由外层壳处理——递归调用方一律走此层）
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
/// 属性作用域 context 应用（scoped-context 批——REC 5.1.2 "property-scoped
/// context"）：active property 的 term 定义带 local context 时，其**值**展开前
/// 先做 Context Processing 并套用；无 local context / 无 term 定义 = 原样返回。
/// 两阶段语义（REC 4.2.2 注记）：定义期只校验（结果丢弃，错误 → invalid
/// scoped context），展开期才真正再处理应用（#tc037/#tc038/#tin06 oracle）
fn StandardExpander::apply_property_scoped_context(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  options : JsonLdOptions,
) -> Result[ActiveContext, JsonLdError] {
  match active.terms.get(term) {
    Some(term_definition) =>
      match term_definition.local_context {
        Some(local_context) =>
          ContextProcessor::process_context(
            self,
            active,
            local_context,
            ContextFlags::property_scoped().with_context_base_url(
              term_definition.context_base_url,
            ),
            options,
          )
        None => Ok(active)
      }
    None => Ok(active)
  }
}

///|
/// 属性值展开的 context 组装（REC 5.1.2 映射分支次序）：
/// ① property-scoped context 取自**传入 active（回退前）**——形判定与 scoped
///    定义都以 pre-revert context 为准（#tc012/#tc020 oracle）；
/// ② 回退：active.previous 存在且值既非值对象形也非单 @id 形 ⇒ 回退到 previous
///    （"term-scoped context 不跨新节点"：#tc009/#tc015/#tc016/#tc017 oracle）；
/// ③ 在（可能已回退的）context 上处理 property-scoped context。
/// 标量值不走本函数（标量分支不回退，只套 property-scoped——#tc007 oracle）
fn StandardExpander::property_value_context(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  options : JsonLdOptions,
) -> Result[ActiveContext, JsonLdError] {
  // ① 捕获 property-scoped context（回退**前** context 的 td——#tc012 oracle：
  //    type-scoped 里定义的 bar 自带 scoped context，回退会丢掉该定义，故先取）
  let property_scoped : TermDefinition? = match active.terms.get(term) {
    Some(term_definition) => Some(term_definition)
    None => None
  }
  // ② 回退门
  let base = match active.previous {
    Some(_) =>
      if StandardExpander::is_value_or_id_shaped(self, active, value) {
        active
      } else {
        StandardExpander::revert_previous(active)
      }
    None => active
  }
  // ③ 在（可能已回退的）context 上**直接应用捕获的** scoped context
  match property_scoped {
    Some(term_definition) =>
      match term_definition.local_context {
        Some(local_context) =>
          ContextProcessor::process_context(
            self,
            base,
            local_context,
            ContextFlags::property_scoped().with_context_base_url(
              term_definition.context_base_url,
            ),
            options,
          )
        None => Ok(base)
      }
    None => Ok(base)
  }
}

///|
/// 容器应用壳（C 组——判据③）：@container @list → 元素展开 + List 包裹后
/// 委托内层（包裹仅此一层——元素递归一律走 expand_term_values_inner，防
/// 容器/标量 coercion 互咬重入）。@container @set = 现有摊平即塌缩
/// （no-op 语义，#t0015 oracle），无需专码
fn StandardExpander::expand_term_values(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  active_property : String?,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  // 容器位查找用**回退前/作用域前**的 context（REC 13.4.3 在主键循环内按节点
  // context 取容器映射）；property-scoped 应用在值展开处（property_value_context）
  let container_kind = match active.terms.get(term) {
    Some(term_definition) => term_definition.container
    None => None
  }
  // graph 容器应用（@graph 容器族——形态表见 todo §J2 开工钉）：次级
  // @id/@index = map 形态（键附挂条目）；裸/@set = 逐值包成 graph 节点
  if container_kind is Some(ContainerType::Graph) {
    let graph_secondary = match active.terms.get(term) {
      Some(term_definition) => term_definition.graph_secondary
      None => None
    }
    return StandardExpander::expand_graph_container(
      self, active, term, value, graph_secondary, options,
    )
  }
  if container_kind is Some(ContainerType::List) {
    // 值本身 = list/set 对象 → 拦截器直出，不二次包裹（#t0004 oracle：
    // {"@list": []} under list 容器 → {"@list": []} 单层）
    match value {
      JsonValue::Object(obj_pairs) =>
        if obj_pairs.length() > 0 &&
          (obj_pairs[0].0 is "@list" || obj_pairs[0].0 is "@set") {
          match
            StandardExpander::expand_list_set_object(
              self, active, term, obj_pairs, options,
            ) {
            Ok(Some(vs)) => return Ok(vs)
            Ok(None) => ()
            Err(e) => return Err(e)
          }
        }
      _ => ()
    }
    let items = match value {
      JsonValue::Array(items) => items
      _ => [value]
    }
    let out : Array[ExpandedValue] = []
    for item in items {
      match
        StandardExpander::expand_list_item(self, active, term, item, options) {
        Ok(Some(v)) => out.push(v)
        Ok(None) => () // null 元素丢弃（1.1）
        Err(e) => return Err(e)
      }
    }
    return Ok([ExpandedValue::List(out, index=None)])
  }
  // @container 映射分支（REC 13.8.3 "container mapping includes @index, @type, or
  // @id and value is a map"）：本批落 @type（type map）+ @index（index map 最小
  // 子集——#tc013 的 fixture 需 index map 侧）；@id 容器随 @id map 批。
  // 值为 map 才走映射分支；其他形态落通用分支（字符串经**隐式 @id type mapping**
  // 成节点引用——#tm017 oracle）
  match container_kind {
    Some(ContainerType::Type) =>
      match value {
        JsonValue::Object(entries) =>
          return StandardExpander::expand_container_map(
            self,
            active,
            term,
            entries,
            ContainerType::Type,
            options,
          )
        _ => ()
      }
    Some(ContainerType::Index) =>
      match value {
        JsonValue::Object(entries) =>
          return StandardExpander::expand_container_map(
            self,
            active,
            term,
            entries,
            ContainerType::Index,
            options,
          )
        _ => ()
      }
    Some(ContainerType::Id) =>
      match value {
        JsonValue::Object(entries) =>
          return StandardExpander::expand_container_map(
            self,
            active,
            term,
            entries,
            ContainerType::Id,
            options,
          )
        _ => ()
      }
    // @container @language（REC 13.8.2 language map）：值为 map 才走语言映射分支
    Some(ContainerType::Language) =>
      match value {
        JsonValue::Object(entries) =>
          return StandardExpander::expand_language_map(
            self, active, term, entries, options,
          )
        _ => ()
      }
    _ => ()
  }
  StandardExpander::expand_term_values_inner(
    self, active, term, value, active_property, options,
  )
}

///|
/// type map 展开（@container @type；REC 13.8.3）：
/// ① **map context** = active 的 previous（存在即用，否则 active）——"type map 用
///    **类型索引项**的 scoped context，不用包含方的"（#tc013 oracle）；
/// ② 索引项（map 键）的 term 定义在 map context 中若有 local context → 套用
///    （#tm008 oracle）；
/// ③ 逐条目：expanded index = 键的 IRI 展开（vocab 位）；条目值为数组则逐项；
///    条目经**属性值展开**（含 coercion——#tm017 字符串经隐式 @id 成节点引用）；
/// ④ 每个展开项：expanded index ≠ @none ⇒ **前插** @type（#tm004 已有 @type 时前插；
///    #tm012 @none 及别名不加）
fn StandardExpander::expand_container_map(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  entries : Array[(String, JsonValue)],
  kind : ContainerType,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  // ① map context：@id/@type ⇒ previous 存在即回退；@index ⇒ 用 active（REC 13.8.3）
  let uses_previous = kind is (ContainerType::Type | ContainerType::Id)
  let mut map_context = if uses_previous {
    match active.previous {
      Some(_) => StandardExpander::revert_previous(active)
      None => active
    }
  } else {
    active
  }
  let expanded : Array[ExpandedValue] = []
  // index key（REC 13.8.3："Initialize index key to the key's index mapping in active
  // context, or @index, if it does not exist"）——None 表示缺省 @index
  let index_mapping = match active.terms.get(term) {
    Some(term_definition) => term_definition.index_mapping
    None => None
  }
  for entry in entries {
    let index_key = entry.0
    let index_value = entry.1
    // ② 仅 @type 容器：索引项的 scoped context（在 map context 中查 td；用元素级
    // 默认旗标——REC 此调用未传 override protected/propagate；#tm008 oracle）
    if kind is ContainerType::Type {
      map_context = match map_context.terms.get(index_key) {
        Some(term_definition) =>
          match term_definition.local_context {
            Some(local_context) =>
              match
                ContextProcessor::process_context(
                  self,
                  map_context,
                  local_context,
                  ContextFlags::element().with_context_base_url(
                    term_definition.context_base_url,
                  ),
                  options,
                ) {
                Ok(next) => next
                Err(e) => return Err(e)
              }
            None => map_context
          }
        None => map_context
      }
    }
    // ③ 索引与索引值（REC："Initialize expanded index to the result of IRI
    // expanding index"）
    let expanded_index = match
      IriExpander::expand_iri(self, map_context, index_key, false, true) {
      Ok(expanded_index) => expanded_index
      Err(e) => return Err(e)
    }
    let items = match index_value {
      JsonValue::Array(items) => items
      _ => [index_value]
    }
    // from map 语境（REC 递归调用传 true for from map）：**不回退 previous**——
    // 以"previous 已清空"的等价 context 表达（本批索引项展开的全部路径都按此）
    let item_context = ActiveContext::{
      base: map_context.base,
      vocab: map_context.vocab,
      terms: map_context.terms,
      previous: None,
      default_language: None,
      default_direction: None,
      compact_by_iri: None,
      compact_reverse: None,
      compact_prefixes: None,
    }
    for item in items {
      let item_values = match
        StandardExpander::expand_map_item_values(
          self, item_context, term, item, options,
        ) {
        Ok(values) => values
        Err(e) => return Err(e)
      }
      for item_value in item_values {
        // ④ 按容器种类写入索引语义（@none 及其别名一律跳过）
        if expanded_index != "@none" {
          match kind {
            ContainerType::Type =>
              // 前插 @type（已有 @type 时前插——#tm004 oracle）
              match item_value {
                ExpandedValue::Node(node) =>
                  node.types.insert(0, expanded_index)
                ExpandedValue::Value(literal) =>
                  // 值对象位：无 datatype 时写为 @type（先验；无 oracle）
                  if literal.datatype is None {
                    literal.datatype = Some(expanded_index)
                  }
                ExpandedValue::List(_) => ()
              }
            ContainerType::Index =>
              // 索引映射（index key ≠ @index）⇒ 索引键写成**一条属性**（REC 13.8.3
              // 子案例 1；#tpi06~#tpi10 oracle）；否则写 @index = 原始索引键（子案例 2）
              match index_mapping {
                Some(index_key_name) =>
                  match item_value {
                    ExpandedValue::Node(node) => {
                      // expanded index key = IRI 展开 index key（REC 13.8.3）
                      let index_property_iri = match
                        IriExpander::expand_iri(
                          self, item_context, index_key_name, false, true,
                        ) {
                        Ok(iri) => iri
                        Err(e) => return Err(e)
                      }
                      // re-expanded index = Value Expansion(active, index key, 索引)
                      let re_expanded = match
                        StandardExpander::expand_term_values_inner(
                          self,
                          item_context,
                          index_key_name,
                          JsonValue::String(index_key),
                          Some(index_key_name),
                          options,
                        ) {
                        Ok(values) =>
                          match values {
                            [first, ..] => first
                            [] => continue // 无值（防御；无 oracle）
                          }
                        Err(e) => return Err(e)
                      }
                      // index property values = [re-expanded] ++ 既有同 IRI 值
                      let mut merged = false
                      for i in 0..<node.properties.length() {
                        if node.properties[i].0 == index_property_iri {
                          let replacement : Array[ExpandedValue] = [re_expanded]
                          for v in node.properties[i].1 {
                            replacement.push(v)
                          }
                          node.properties[i] = (index_property_iri, replacement)
                          merged = true
                        }
                      }
                      if !merged {
                        node.properties.push(
                          (index_property_iri, [re_expanded]),
                        )
                      }
                    }
                    ExpandedValue::Value(_) =>
                      // "If item is a value object, it MUST NOT contain any extra
                      // properties; an invalid value object error"（#tpi05 oracle）
                      return Err(
                        JsonLdError::InvalidValue("invalid value object"),
                      )
                    ExpandedValue::List(_) => () // 先验：list 位无 oracle
                  }
                None =>
                  // 子案例 2：条目无 @index 时写 @index = 原始索引键
                  match item_value {
                    ExpandedValue::Node(node) =>
                      if node.index is None {
                        node.index = Some(index_key)
                      }
                    ExpandedValue::Value(literal) =>
                      if literal.index is None {
                        literal.index = Some(index_key)
                      }
                    ExpandedValue::List(_) => ()
                  }
              }
            ContainerType::Id =>
              // 条目无 @id 时写 @id = **document-relative、非 vocab 位**展开的索引
              // （REC："expanded index is set to the result of IRI expanding index
              // using true for document relative and false for vocab"；#tm005 oracle）
              match item_value {
                ExpandedValue::Node(node) =>
                  if node.id is None {
                    node.id = Some(
                      match
                        IriExpander::expand_iri(
                          self, item_context, index_key, true, false,
                        ) {
                        Ok(expanded_id) => expanded_id
                        Err(e) => return Err(e)
                      },
                    )
                  }
                _ => ()
              }
            _ => ()
          }
        }
        expanded.push(item_value)
      }
    }
  }
  Ok(expanded)
}

///|
/// language map 展开（@container @language；REC 13.8.2）：
/// 逐条目（语言键 → 值，值非数组则归一数组）：条目值为 **null 跳过**、**非串 →
/// invalid language map value**；产出 `{@value: item}`，语言键**非 @none**（含
/// **展开为 @none 的别名**）时加 `@language: 原始语言键`。
/// 本引擎暂无默认 base direction / td direction mapping ⇒ direction 恒 null（不产出
/// @direction）——#tdi04~#tdi07（term direction 面）挂「@direction 批」。
/// oracle：#tm009/#tm010（@none 与别名）/ #t0030（基本）/ #tl001（null 跳过）
fn StandardExpander::expand_language_map(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  entries : Array[(String, JsonValue)],
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  let _ = options
  // 方向三态解析（丙批——#tdi04~#tdi07 oracle）：term direction 成员
  // Set 覆盖 / Null 压制 / 未声明继承 context 默认方向；"@none" 键条目
  // 不附方向（#tdi07 同族语义：none 条目保持最小形态）
  let term_direction : String? = match active.terms.get(term) {
    Some(term_definition) =>
      match term_definition.direction_mapping {
        Some(LanguageMember::Set(dir)) => Some(dir)
        Some(LanguageMember::Null) => None
        None => active.default_direction
      }
    None => active.default_direction
  }
  let expanded : Array[ExpandedValue] = []
  for entry in entries {
    let language = entry.0
    let items = match entry.1 {
      JsonValue::Array(items) => items
      single => [single]
    }
    // @none 判定：键本身为 @none **或展开为 @none**（别名——#tm010 oracle）
    let is_none = match
      IriExpander::expand_iri(self, active, language, false, true) {
      Ok(expanded_language) => expanded_language is "@none"
      Err(_) => language is "@none"
    }
    for item in items {
      match item {
        JsonValue::Null => () // 条目值 null：跳过（#tl001 oracle）
        JsonValue::String(text) => {
          // @none 条目：语言与方向均不附（最小形态——#tdi07 对照）
          let language_tag = if is_none { None } else { Some(language) }
          let direction_tag : String? = if is_none {
            None
          } else {
            term_direction
          }
          expanded.push(
            ExpandedValue::Value(ExpandedLiteral::{
              value: text,
              datatype: None,
              language: language_tag,
              direction: direction_tag,
              raw: None,
              index: None,
              included: None,
            }),
          )
        }
        _ => return Err(JsonLdError::InvalidValue("invalid language map value"))
      }
    }
  }
  Ok(expanded)
}

///|
/// type map 条目的值展开（from map 语境——REC 13.8.3 递归调用）：属性值语义
/// （含 coercion / property-scoped / 不回退），数组逐项摊平；null 丢弃。
/// 不重入容器壳（容器已由外层键位处理）
fn StandardExpander::expand_map_item_values(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  item : JsonValue,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  match item {
    JsonValue::Array(items) => {
      let out : Array[ExpandedValue] = []
      for sub in items {
        match
          StandardExpander::expand_map_item_values(
            self, active, term, sub, options,
          ) {
          Ok(values) =>
            for v in values {
              out.push(v)
            }
          Err(e) => return Err(e)
        }
      }
      Ok(out)
    }
    _ =>
      StandardExpander::expand_term_values_inner(
        self,
        active,
        term,
        item,
        Some(term),
        options,
      )
  }
}

///|
/// 值对象性预扫（#tc020——任一键展开为 @value 即值对象形态，与键文档序
/// 无关；配套 @type 先至的 coercion 分路）
fn StandardExpander::has_value_key_shaped(
  self : StandardExpander,
  current : ActiveContext,
  pairs : Array[(String, JsonValue)],
) -> Bool {
  for p in pairs {
    let sibling = match
      IriExpander::expand_iri(self, current, p.0, false, true) {
      Ok(k) => k
      Err(_) => p.0
    }
    if sibling is "@value" {
      return true
    }
  }
  false
}

///|
/// @json 值对象识别（丁批——#tjs15/#tjs16/#tjs22 oracle）：同对象存在 vocab
/// 展开为 @type 的键、其值（可别名 term，"json" → @json）展开为 @json
fn StandardExpander::is_json_value_object(
  self : StandardExpander,
  current : ActiveContext,
  pairs : Array[(String, JsonValue)],
) -> Bool {
  let mut is_json_value = false
  for p in pairs {
    let sibling = match
      IriExpander::expand_iri(self, current, p.0, false, true) {
      Ok(k) => k
      Err(_) => p.0
    }
    match (sibling, p.1) {
      ("@type", JsonValue::String(t)) => {
        let expanded_type = match
          IriExpander::expand_iri(self, current, t, false, true) {
          Ok(k) => k
          Err(_) => t
        }
        if expanded_type is "@json" {
          is_json_value = true
        }
      }
      _ => ()
    }
  }
  is_json_value
}

///|
fn StandardExpander::expand_term_values_inner(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  active_property : String?,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  // @json 字面量拦截（丁批——REC 13.8.1 @json 值展开）：值原样（JSON 解析
  // 结果）进 @value，datatype = @json 关键字形态（oracle tjs01：输出
  // `"@type": "@json"`）；对象/数组**不作节点展开**（#tjs06/#tjs08 oracle）。
  // canonical 选项只影响序列化词形（JCS/RFC 8785，挂 J3），展开按解析值对拍
  let scoped_for_json = match
    StandardExpander::apply_property_scoped_context(self, active, term, options) {
    Ok(context) => context
    Err(e) => return Err(e)
  }
  match scoped_for_json.terms.get(term) {
    Some(term_definition) =>
      match term_definition.datatype {
        Some("@json") => {
          let lit = ExpandedLiteral::{
            value: "",
            datatype: Some("@json"),
            language: None,
            direction: None,
            raw: Some(value),
            index: None,
            included: None,
          }
          return Ok([ExpandedValue::Value(lit)])
        }
        _ => ()
      }
    None => ()
  }
  // property-scoped context（REC 5.1.2 不回退；标量/容器臂共用——丙批/丁批/
  // 原生 coercion）
  let scoped = match
    StandardExpander::apply_property_scoped_context(self, active, term, options) {
    Ok(context) => context
    Err(e) => return Err(e)
  }
  match value {
    JsonValue::Object(_) => {
      // list/set 对象拦截（C 组——判据①；#ter41/#tli01 oracle）
      match value {
        JsonValue::Object(obj_pairs) =>
          match
            StandardExpander::expand_list_set_object(
              self, active, term, obj_pairs, options,
            ) {
            Ok(Some(vs)) => return Ok(vs)
            Ok(None) => ()
            Err(e) => return Err(e)
          }
        _ => ()
      }
      // @language 容器的值检查已由语言映射分支（expand_language_map，REC 13.8.2）
      // 承担：条目值 null 跳过、非串 → invalid language map value（#ter35 oracle：
      // {"en": true} → 非串即错）；非 map 值走通用分支（REC 分支条件要求 map）
      match
        StandardExpander::expand_object(
          self,
          match
            StandardExpander::property_value_context(
              self, active, term, value, options,
            ) {
            Ok(context) => context
            Err(e) => return Err(e)
          },
          value,
          Some(term),
          options,
        ) {
        Ok(Some(v)) => Ok([v])
        Ok(None) => Ok([])
        Err(e) => Err(e)
      }
    }
    JsonValue::Array(items) => {
      let out : Array[ExpandedValue] = []
      for item in items {
        // 数组项走**内层**（REC 5.1.2：容器逻辑只作用于键的值一次；数组项按
        // 元素语义逐项展开——重入容器壳会把映射分支误施于项，实测 #t0040
        // `{"@id": …}` 项被当成 index map 处理 ⇒ 值对象而非节点）
        match
          StandardExpander::expand_term_values_inner(
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
    JsonValue::String(sv) => {
      // 标量分支（REC 5.1.2）：**不回退**，只套 property-scoped context
      // （#tc007 oracle：节点自身标量属性仍见 type-scoped 的 coercion）
      // 默认语言/方向解析（丙批——#t0022/#t0018/#tdi01 oracle）：term 成员
      // 三态优先（Set 覆盖 / Null 压制），未声明继承 context 默认（scoped
      // context 链已继承——property-scoped 应用保留默认值）；仅串值注入
      let term_language : String? = match scoped.terms.get(term) {
        Some(term_definition) =>
          match term_definition.language_mapping {
            Some(LanguageMember::Set(lang)) => Some(lang)
            Some(LanguageMember::Null) => None
            None => scoped.default_language
          }
        None => scoped.default_language
      }
      let term_direction : String? = match scoped.terms.get(term) {
        Some(term_definition) =>
          match term_definition.direction_mapping {
            Some(LanguageMember::Set(dir)) => Some(dir)
            Some(LanguageMember::Null) => None
            None => scoped.default_direction
          }
        None => scoped.default_direction
      }
      // coercion 应用（⑤批 A 组——判据②）：type mapping 三形态只转**串值**
      // （number/bool 不转，#t0088 oracle）；形态 B "@id" = document-relative、
      // 形态 C "@vocab" = vocab 位、形态 D = 显式 datatype 值对象
      match scoped.terms.get(term) {
        Some(term_definition) =>
          match term_definition.datatype {
            Some(coercion) =>
              if coercion is "@none" {
                // 显式无 coercion（#ttn01——@none 串值原样，语言/方向仍随 term）
                let lit = ExpandedLiteral::{
                  value: sv,
                  datatype: None,
                  language: term_language,
                  direction: term_direction,
                  raw: None,
                  index: None,
                  included: None,
                }
                Ok([ExpandedValue::Value(lit)])
              } else {
                let coerced : Result[ExpandedValue, JsonLdError] = if coercion
                  is "@id" {
                  match IriExpander::expand_iri(self, scoped, sv, true, false) {
                    Ok(iri) =>
                      Ok(
                        ExpandedValue::Node(ExpandedNode::{
                          id: Some(iri),
                          types: [],
                          properties: [],
                          reverse_props: [],
                          graph: None,
                          included: None,
                          index: None,
                        }),
                      )
                    Err(e) => Err(e)
                  }
                } else if coercion is "@vocab" {
                  // @vocab coercion 构造点（#t0057 oracle：vocab miss 后落
                  // document-relative 位——base 解析）
                  match IriExpander::expand_iri(self, scoped, sv, true, true) {
                    Ok(iri) =>
                      Ok(
                        ExpandedValue::Node(ExpandedNode::{
                          id: Some(iri),
                          types: [],
                          properties: [],
                          reverse_props: [],
                          graph: None,
                          included: None,
                          index: None,
                        }),
                      )
                    Err(e) => Err(e)
                  }
                } else {
                  Ok(
                    ExpandedValue::Value(ExpandedLiteral::{
                      value: sv,
                      datatype: Some(coercion),
                      language: None,
                      direction: None,
                      raw: None,
                      index: None,
                      included: None,
                    }),
                  )
                }
                match coerced {
                  Ok(v) => Ok([v])
                  Err(e) => Err(e)
                }
              }
            None => {
              let lit = ExpandedLiteral::{
                value: sv,
                datatype: None,
                language: term_language,
                direction: term_direction,
                raw: None,
                index: None,
                included: None,
              }
              Ok([ExpandedValue::Value(lit)])
            }
          }
        None => {
          let lit = ExpandedLiteral::{
            value: sv,
            datatype: None,
            language: term_language,
            direction: term_direction,
            raw: None,
            index: None,
            included: None,
          }
          Ok([ExpandedValue::Value(lit)])
        }
      }
    }
    JsonValue::Number(nv) => {
      // 原生值 coercion（#t0031/#t0061 oracle）：datatype 映射（非 @id/@vocab/
      // @json 形态）⇒ {@value, @type: dt}；@id/@vocab coercion 不转原生值
      //（#t0088 同族）
      let dt = match scoped.terms.get(term) {
        Some(term_definition) => term_definition.datatype
        None => None
      }
      let lit = match dt {
        Some(coercion) =>
          // @none 同族不转原生值（#ttn01——数/布尔 raw 保形无 @type）
          if coercion is ("@id" | "@vocab" | "@json" | "@none") {
            ExpandedLiteral::{
              value: "\{nv}",
              datatype: None,
              language: None,
              direction: None,
              raw: Some(JsonValue::Number(nv)),
              index: None,
              included: None,
            }
          } else {
            ExpandedLiteral::{
              value: "\{nv}",
              datatype: Some(coercion),
              language: None,
              direction: None,
              raw: Some(JsonValue::Number(nv)),
              index: None,
              included: None,
            }
          }
        None =>
          ExpandedLiteral::{
            value: "\{nv}",
            datatype: None,
            language: None,
            direction: None,
            raw: Some(JsonValue::Number(nv)),
            index: None,
            included: None,
          }
      }
      Ok([ExpandedValue::Value(lit)])
    }
    // 属性位布尔 = @value 字面量保形（#t0088 oracle：true/false 保留）；
    // null 丢弃（1.1）
    JsonValue::Bool(bv) => {
      let dt = match scoped.terms.get(term) {
        Some(term_definition) => term_definition.datatype
        None => None
      }
      let lit = match dt {
        Some(coercion) =>
          // @none 同族不转原生值（#ttn01 同上）
          if coercion is ("@id" | "@vocab" | "@none") {
            // @id/@vocab coercion 不转原生值（#t0088 同族）
            ExpandedLiteral::{
              value: "\{bv}",
              datatype: None,
              language: None,
              direction: None,
              raw: Some(JsonValue::Bool(bv)),
              index: None,
              included: None,
            }
          } else {
            ExpandedLiteral::{
              value: "\{bv}",
              datatype: Some(coercion),
              language: None,
              direction: None,
              raw: Some(JsonValue::Bool(bv)),
              index: None,
              included: None,
            }
          }
        None =>
          ExpandedLiteral::{
            value: "\{bv}",
            datatype: None,
            language: None,
            direction: None,
            raw: Some(JsonValue::Bool(bv)),
            index: None,
            included: None,
          }
      }
      Ok([ExpandedValue::Value(lit)])
    }
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
/// 定义期 base URL 快照（庚批——#tc031 oracle）：term 所在 context 的装载
/// base URL——flags.base_url（装载链内）优先，缺省回落 documentUrl。
fn definition_base_url(
  flags : ContextFlags,
  options : JsonLdOptions,
) -> String? {
  match flags.base_url {
    Some(url) => Some(url)
    None => options.base
  }
}

///|
/// 应用面 base URL 覆写（庚批——#tc031 oracle）：td 携带的 scoped context 在
/// 应用期以其**定义期 base URL** 作 flags.base_url——远程 context 内定义的
/// scoping 引用锚定源 context 装载位（新建面 base_url=None 会回落 documentUrl，
/// 即 #tc031 的报错路径）。
fn ContextFlags::with_context_base_url(
  self : ContextFlags,
  context_base_url : String?,
) -> ContextFlags {
  { ..self, base_url: context_base_url, }
}

///|
/// context 引用解析共用件（REC 4.1.2 步 5.2.1——远程 String 臂与 @import 预处理
/// 共用）：引用对**context 装载 base URL** 合并。base 取 flags.base_url（装载链
/// 内 = context 自身 URL），缺省回落 options.base（documentUrl）——**不回落
/// active.base**：引用解析是算法输入位，不随 active @base 覆写走（#tc031
/// oracle：数组 context 首项 `@base` 覆写后，次项引用仍锚定文档位置；REC：
/// base URL "is often not the same as base or the base IRI of the active
/// context"）。
fn resolve_context_reference(
  context_ref : String,
  flags : ContextFlags,
  options : JsonLdOptions,
) -> Result[String, JsonLdError] {
  match flags.base_url {
    Some(url) => Ok(merge_base_reference(url, context_ref))
    None =>
      match options.base {
        Some(url) => Ok(merge_base_reference(url, context_ref))
        None =>
          Err(
            JsonLdError::InvalidContext(
              "loading remote context failed: no base URL to resolve \{context_ref}",
            ),
          )
      }
  }
}

///|
/// 远程 context 装载共用件（REC 4.1.2 步 5.2.5 / 步 5.4 共用）：loader 装载 →
/// JSON 解析 → 解包顶层 @context 成员。装载失败 → loading remote context
/// failed；非对象或无该成员 → invalid remote context。返回解包后的内联 context
/// （调用面不再判 None——共用件已保证形态）。
fn load_context_document(
  resolved : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let loader = match options.load_context {
    Some(loader) => loader
    None => return Err(JsonLdError::Unsupported("context loader not provided"))
  }
  let text = match loader(resolved) {
    Ok(text) => text
    Err(msg) =>
      return Err(
        JsonLdError::InvalidContext("loading remote context failed: \{msg}"),
      )
  }
  let loaded = match parse_json(text) {
    Ok(value) => value
    Err(_e) =>
      return Err(
        JsonLdError::InvalidContext(
          "loading remote context failed: invalid JSON at \{resolved}",
        ),
      )
  }
  // 装载结果须含 @context 成员（步 5.2.5）：非对象或无该成员 → invalid remote context
  let inner : JsonValue? = match loaded {
    JsonValue::Object(pairs) => {
      let mut found : JsonValue? = None
      for pair in pairs {
        if pair.0 is "@context" {
          found = if found is None { Some(pair.1) } else { found }
        }
      }
      found
    }
    _ => None
  }
  match inner {
    Some(inner_value) => Ok(inner_value)
    None =>
      Err(JsonLdError::InvalidContext("invalid remote context: \{resolved}"))
  }
}

///|
/// @import 条目合并件（REC 4.1.2 步 5.4；庚批——#tso05/06/08/09/11 oracle）：
/// 装载 imported context 并做形态/链式校验，与本 context 条目**条目级合并**：
/// 「merging context into import context, **replacing common entries**」——
/// imported 条目在前、同名条目以本 context 侧**替换**（不并存；#tso11 oracle：
/// imported 的 term 定义不参与处理，故不受本 context `@protected` 追溯保护）、
/// @import 条目剥离（合并后主循环不再见）。校验：1.0 模式 →
/// invalid context entry；值非串 → invalid @import value；imported 文档须为
/// context 定义 **map**（数组/标量 → invalid remote context）；imported 自身含
/// @import → invalid context entry（链式装载禁——REC 步 5.4）。
fn merge_import_entries(
  import_value : JsonValue,
  local_pairs : Array[(String, JsonValue)],
  flags : ContextFlags,
  options : JsonLdOptions,
) -> Result[Array[(String, JsonValue)], JsonLdError] {
  if options.processing_mode is JsonLd10 {
    return Err(JsonLdError::InvalidContext("invalid context entry"))
  }
  let import_ref = match import_value {
    JsonValue::String(context_ref) => context_ref
    _ => return Err(JsonLdError::InvalidContext("invalid @import value"))
  }
  let resolved = match resolve_context_reference(import_ref, flags, options) {
    Ok(url) => url
    Err(e) => return Err(e)
  }
  let imported = match load_context_document(resolved, options) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let imported_pairs = match imported {
    JsonValue::Object(pairs) => pairs
    _ =>
      return Err(
        JsonLdError::InvalidContext("invalid remote context: \{resolved}"),
      )
  }
  for imported_pair in imported_pairs {
    if imported_pair.0 is "@import" {
      return Err(JsonLdError::InvalidContext("invalid context entry"))
    }
  }
  // 本 context 键集（去 @import 后）——imported 侧同名条目被替换剔除
  let local_keys : Map[String, Bool] = Map([])
  for pair in local_pairs {
    if !(pair.0 is "@import") {
      local_keys[pair.0] = true
    }
  }
  let merged : Array[(String, JsonValue)] = []
  for imported_pair in imported_pairs {
    if !local_keys.contains(imported_pair.0) {
      merged.push(imported_pair)
    }
  }
  for pair in local_pairs {
    if !(pair.0 is "@import") {
      merged.push(pair)
    }
  }
  Ok(merged)
}

///|
/// ContextProcessor 落码（③批）：@context 声明 → ActiveContext 构建/继承（简单形态）。
/// 继承：terms/vocab/base 父副本（ADR-JL-4 不可变语义 = 副本）；数组 context = 逐项合并。
/// 落码范围：term→IRI 字符串定义、@vocab（相对先经 base）、@base、term=null（移除）。
/// 未落（红而非错）：term 定义对象形态（@type/@container——⑤批）、@language/@direction
/// 默认（后由丙批落）。
/// **己批**：远程 context String 臂（REC 4.1.2 步 5.2：resolve → skip → overflow
/// → load → recurse；装载链终止两机制）。
/// **庚批**：@import 预处理（步 5.4：装载 + 条目级合并 + 链式禁）+ 引用解析
/// base 锚定 context 装载位（resolve_context_reference——不随 active @base 覆写）。
/// **type-scoped 批**：`propagate` 参数（调用方默认；local context 的 @propagate
/// 成员优先）——propagate=false 时置 previous context，供新节点对象回退
/// （REC 4.1.2 步 3）。
/// **@protected 批**：上下文级 `@protected` 成员为 td 默认保护位；`override
/// protected` 由调用面旗标传入（property-scoped/定义期校验 = true，type-scoped/
/// 元素级 = false）；`null` 空化遇保护 term 且 override=false → invalid context
/// nullification。
impl ContextProcessor for StandardExpander with fn process_context(
  _self,
  active : ActiveContext,
  local_context : JsonValue,
  flags : ContextFlags,
  options : JsonLdOptions,
) -> Result[ActiveContext, JsonLdError] {
  let mut vocab = active.vocab
  let mut base = active.base
  match local_context {
    // context nullification（REC 4.1.2：数组项为 null = 重置为新初始 context，
    // **base IRI 取原 base URL**）——scoped-context 批勘定件：#tc014（type-scoped
    // `[null]`）/ #tc018（`[null, {...}]`）的 scoped context 形态若不接受，定义期
    // 校验会误判 invalid scoped context。**@protected 批门**：override protected
    // = false 且 active context 含任何保护 term → invalid context nullification
    // （#pr05/#pr17/#pr18/#pr20/#pr21 oracle）
    JsonValue::Null => {
      if !flags.override_protected && has_protected_term(active) {
        return Err(JsonLdError::InvalidContext("invalid context nullification"))
      }
      // nullification 保 base URL；propagate=false 时把 previous 带过新 result
      // （REC 4.1.2 步 5.2.1："if propagate is false, previous context in result
      // to the previous value of result"）
      Ok(ActiveContext::{
        base: initial_context(options).base,
        vocab: None,
        terms: Map([]),
        previous: previous_after(active, flags.propagate),
        default_language: None,
        default_direction: None,
        compact_by_iri: None,
        compact_reverse: None,
        compact_prefixes: None,
      })
    }
    JsonValue::String(context_ref) => {
      // 远程 context 臂（己批——REC 4.1.2 步 5.2：resolve → skip → overflow → load → recurse；
      // resolve/load 与 @import 预处理共用件同源——引用解析 base 口径见
      // resolve_context_reference）
      let resolved = match
        resolve_context_reference(context_ref, flags, options) {
        Ok(url) => url
        Err(e) => return Err(e)
      }
      // 步 5.2.2：validate=false（td 定义期校验）且链上已有 → 跳过非错误（破环主机制）
      if !flags.validate_scoped && flags.remote_contexts.contains(resolved) {
        return Ok(active)
      }
      // 步 5.2.3：链深超 processor-defined limit → context overflow（validate=true 的文档级环靠此截断）
      if flags.remote_contexts.length() >= CONTEXT_CHAIN_LIMIT {
        return Err(
          JsonLdError::ContextOverflow("context overflow: \{resolved}"),
        )
      }
      // 步 5.2.5：装载 + 解包 @context 成员（失败 → loading remote context
      // failed / invalid remote context——文案在共用件内）
      let inner = match load_context_document(resolved, options) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      // 步 5.2.6：递归——local context = 装载内容、base URL = documentUrl（= resolved，loader 无重定向）、链副本（新建数组）、validate 原样
      let chain : Array[String] = []
      for url in flags.remote_contexts {
        chain.push(url)
      }
      chain.push(resolved)
      let inner_flags : ContextFlags = {
        propagate: flags.propagate,
        override_protected: flags.override_protected,
        base_url: Some(resolved),
        remote_contexts: chain,
        validate_scoped: flags.validate_scoped,
      }
      ContextProcessor::process_context(
        _self, active, inner, inner_flags, options,
      )
    }
    JsonValue::Array(items) => {
      // 数组 context：逐项合并（前项产出为后项输入）
      let mut current = active
      for item in items {
        match
          ContextProcessor::process_context(
            _self, current, item, flags, options,
          ) {
          Ok(next) => current = next
          Err(e) => return Err(e)
        }
      }
      Ok(current)
    }
    JsonValue::Object(pairs) => {
      // @import 预处理（REC 4.1.2 步 5.4；庚批）：见 merge_import_entries——
      // 有 @import 条目时以合并对列（imported 在前、本 context 去 @import）作
      // 工作对列；无则原对列直通。合并后主循环不再见 @import 键。
      let mut import_found : JsonValue? = None
      for pair in pairs {
        if pair.0 is "@import" && import_found is None {
          import_found = Some(pair.1)
        }
      }
      let pairs = match import_found {
        None => pairs
        Some(import_value) =>
          match merge_import_entries(import_value, pairs, flags, options) {
            Ok(merged) => merged
            Err(e) => return Err(e)
          }
      }
      let keyword_owner : Map[String, String] = Map([])
      // 对象形态 term 定义缓冲（两遍处理——第二遍见主循环后）
      let deferred_td : Array[(String, Array[(String, JsonValue)])] = []
      // 继承：父 terms 复制——**仅当本 context 有 term 条目时才复制**（只含 context
      // 关键字时 terms 不可能被写，直接共享父 map，省 O(T) 复制；@vocab/@base 等
      // 关键字集合见下）
      let mut has_term_entries = false
      for pair in pairs {
        match pair.0 {
          "@base"
          | "@direction"
          | "@import"
          | "@language"
          | "@propagate"
          | "@protected"
          | "@version"
          | "@vocab" => ()
          _ => has_term_entries = true
        }
      }
      let new_terms : Map[String, TermDefinition] = if has_term_entries {
        let copied : Map[String, TermDefinition] = Map([])
        for k, td in active.terms {
          copied[k] = td
        }
        copied
      } else {
        active.terms
      }
      // @propagate 成员（REC 4.1.2 步 2；校验在步 5.x）：1.0 模式非法
      // （invalid context entry）；非布尔 → invalid @propagate value
      let mut propagate = flags.propagate
      // @protected 成员（REC 4.1.2 步 5 调用句：作为本 context 内 td 的**默认**
      // 保护位）：1.0 模式非法（先验，与 @propagate 同门）；非布尔 → invalid
      // @protected value
      let mut protected_default = false
      // 默认语言/方向（丙批——@language/@direction 臂）
      let mut default_language : String? = None
      let mut default_direction : String? = None
      for pair in pairs {
        if pair.0 is "@propagate" {
          if options.processing_mode is JsonLd10 {
            return Err(JsonLdError::InvalidContext("invalid context entry"))
          }
          match pair.1 {
            JsonValue::Bool(flag) => propagate = flag
            _ =>
              return Err(
                JsonLdError::InvalidContext("invalid @propagate value"),
              )
          }
        }
        if pair.0 is "@protected" {
          if options.processing_mode is JsonLd10 {
            return Err(JsonLdError::InvalidContext("invalid context entry"))
          }
          match pair.1 {
            JsonValue::Bool(flag) => protected_default = flag
            _ =>
              return Err(
                JsonLdError::InvalidContext("invalid @protected value"),
              )
          }
        }
      }
      for pair in pairs {
        match pair.0 {
          "@vocab" =>
            match pair.1 {
              JsonValue::String(v) => {
                // 套件 oracle（#t0092[1.1] vs #t0115/#t0116[1.0]）：
                // 1.0 模式 = @vocab 非绝对（含相对/空串）即 invalid——对原始值判，
                // base 不补救；1.1 模式 = 对 base raw 拼接（#t0092：空串 → base
                // 本身、`../` 原样不消点段）
                // 1.0 校验（#t0115/#t0116 oracle：相对/空串非法）豁免 bnode
                // 标签（#t0075 oracle：@vocab "_:" 合法——处理模式依赖第一实证
                // 的边界细化）；bnode 不落 base 拼接
                if options.processing_mode is JsonLd10 &&
                  !(is_valid_absolute_iri(v) || is_bnode_label(v)) {
                  return Err(
                    JsonLdError::InvalidContext("invalid vocab mapping"),
                  )
                }
                // 动态形态解析（@vocab 动态形态批——#t0124/#t0125 oracle）：
                // ① term 精确命中 ② compact（prefix ∈ in-progress terms，
                // suffix 非 "//"）③ 未命中回落既有 absolute/bnode/base-join
                //（t0092 语义不变：空串 → base 本身）
                let mut resolved_v : String? = None
                match new_terms.get(v) {
                  Some(td) =>
                    match td.iri {
                      Some(iri) => resolved_v = Some(iri)
                      None => ()
                    }
                  None => ()
                }
                if resolved_v is None {
                  match colon_index(v) {
                    Some(at) => {
                      let (prefix, suffix) = split_first_colon(v, at)
                      let double_slash = suffix.get_char(0) is Some('/') &&
                        suffix.get_char(1) is Some('/')
                      if !double_slash {
                        match new_terms.get(prefix) {
                          Some(td) =>
                            match td.iri {
                              Some(base_iri) =>
                                resolved_v = Some("\{base_iri}\{suffix}")
                              None => ()
                            }
                          None => ()
                        }
                      }
                    }
                    None => ()
                  }
                }
                let resolved = match resolved_v {
                  Some(r) => r
                  None =>
                    if is_valid_absolute_iri(v) || is_bnode_label(v) {
                      v
                    } else {
                      match vocab {
                        // 相对 @vocab 值 → 拼接现有 vocab（#t0111/#t0112
                        // oracle："./rel2#" 拼在 ctx1 vocab 之后）
                        Some(prev) => "\{prev}\{v}"
                        // 无现有 vocab 且有 base → RFC merge（"/x" 前导斜杠 =
                        // authority 路径替换——#t0110 oracle）
                        None =>
                          match base {
                            Some(b) => merge_base_reference(b, v)
                            None => v
                          }
                      }
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
          "@version" => {
            // 1.1 API：@version 接受串 "json-ld-1.1" 与数值 1.1（套件实证
            // 159 例全为数值形且期望成功——REC"须为串"被套件输入形态否决；
            // 数值 1.0 → 错，#tep03 负例钉边界）。1.0 模式切换（ActiveContext
            // 载入 processing_mode）挂后续批
            let version_is_11 = match pair.1 {
              JsonValue::String("json-ld-1.1") => true
              JsonValue::Number(v) =>
                if v == 1.1 {
                  true
                } else {
                  return Err(
                    JsonLdError::InvalidContext("invalid @version value"),
                  )
                }
              JsonValue::String(v) =>
                return Err(
                  JsonLdError::InvalidContext("invalid @version value (\{v})"),
                )
              _ =>
                return Err(
                  JsonLdError::InvalidContext("invalid @version value"),
                )
            }
            // #tep02 oracle：processingMode json-ld-1.0 与 @version:1.1 冲突 → 错
            if version_is_11 && options.processing_mode is JsonLd10 {
              return Err(
                JsonLdError::InvalidContext(
                  "processingMode json-ld-1.0 conflicts with @version: 1.1",
                ),
              )
            }
          }
          // 未落码 context 关键字（挂账活账——@protected 原落"term definition
          // must be…"的误分类，勘定批修正为 Unsupported：@protected 族 16 枚
          // 的挂账去向是「@protected 批」，非 term 定义形态错误）
          // @propagate 已在对象臂入口预扫描（REC 4.1.2 步 2）——此处跳过
          "@propagate" => ()
          // @protected 同上（对象臂入口预扫描：默认保护位）
          "@protected" => ()
          "@language" =>
            // 默认语言（丙批——#t0022/#t0041/#ter09 oracle）：串设置/null
            // 重置；非串 → invalid default language
            match pair.1 {
              JsonValue::String(lang) => default_language = Some(lang)
              JsonValue::Null => default_language = None
              _ =>
                return Err(
                  JsonLdError::InvalidContext("invalid default language"),
                )
            }
          "@direction" =>
            // 默认方向（丙批——#tdi01 oracle）：ltr/rtl/null；其他 →
            // invalid base direction（#tdi08 同族）
            match pair.1 {
              JsonValue::Null => default_direction = None
              JsonValue::String(dir) =>
                if dir is ("ltr" | "rtl") {
                  default_direction = Some(dir)
                } else {
                  return Err(
                    JsonLdError::InvalidContext("invalid base direction"),
                  )
                }
              _ =>
                return Err(
                  JsonLdError::InvalidContext("invalid base direction"),
                )
            }
          "@import" => ()
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
            // 空 term 名（#ter52 oracle）→ invalid term definition
            if other is "" {
              return Err(JsonLdError::InvalidContext("invalid term definition"))
            }
            // term 定义（简单形态：term → IRI 字符串；null = 移除）。
            // 值 IRI 展开：vocab 位、对 in-progress terms 查表
            // （#t0072 oracle：重定义为自身时用 @vocab，非旧 term 定义）
            match pair.1 {
              JsonValue::String(iri) => {
                // 循环检测（⑤后半——#ter10 oracle）：值 = compact 形且 prefix =
                // 自身 term → cyclic IRI mapping
                if is_self_prefix_compact(iri, other) {
                  return Err(JsonLdError::InvalidContext("cyclic IRI mapping"))
                }
                // 自映射排除（#t0072/#t0071 oracle）：值 = term 自身时旧定义
                // 不参与查表——有 @vocab → vocab 拼接；有 prefix → compact；
                // 两者皆无 → 原样
                let lookup_terms = if iri == other {
                  terms_without(new_terms, other)
                } else {
                  new_terms
                }
                let building = ActiveContext::{
                  base,
                  vocab,
                  terms: lookup_terms,
                  previous: None,
                  default_language: None,
                  default_direction: None,
                  compact_by_iri: None,
                  compact_reverse: None,
                  compact_prefixes: None,
                }
                let expanded = match
                  IriExpander::expand_iri(_self, building, iri, false, true) {
                  Ok(k) => k
                  Err(e) => return Err(e)
                }
                // keyword 项互斥（#ter01 oracle）：**真关键字** term 映射到
                // 异关键字 → keyword redefinition（"@iri" 等 keyword 形态
                // 非真关键字者忽略不报——#t0005 oracle）
                if is_keyword(other) &&
                  is_keyword(expanded) &&
                  expanded != other {
                  return Err(
                    JsonLdError::InvalidContext("keyword redefinition"),
                  )
                }
                // 值为 keyword 形态非真关键字（#tpr37/#t0120 oracle 同族）：
                // 定义忽略——键回落 vocab 拼接（ignoreMe → vocab/ignoreMe）
                if has_keyword_form(expanded) && !is_keyword(expanded) {
                  continue
                }
                // term 名一致性检查（REC 4.2.2 @id 臂；#ter44 负例 oracle；
                // simple 臂与 td @id 臂同规则同源）
                match
                  StandardExpander::check_term_name_consistency(
                    _self, building, other, expanded, options,
                  ) {
                  Ok(_) => ()
                  Err(e) => return Err(e)
                }
                match
                  StandardExpander::install_term_definition(
                    new_terms,
                    other,
                    TermDefinition::{
                      iri: Some(expanded),
                      datatype: None,
                      container: None,
                      reverse: None,
                      local_context: None,
                      context_base_url: definition_base_url(flags, options),
                      index_mapping: None,
                      graph_secondary: None,
                      is_protected: protected_default,
                      language_mapping: None,
                      direction_mapping: None,
                      is_prefix: None,
                      nest: None,
                      simple_form: true,
                      graph_set: false,
                      container_set: false,
                    },
                    flags.override_protected,
                  ) {
                  Ok(_) => ()
                  Err(e) => return Err(e)
                }
              }
              // term: null → @id null 映射（REC 4.2.2：value 为 null 时视作
              // {"@id": null}）——term **保留**、IRI 映射为 null：展开期该键
              // 整体丢弃（#tin06 oracle：scoped context {"data": null} 下
              // "data" 键丢弃；此前按"移除定义"处理会 vocab 拼成属性，为误判）
              JsonValue::Null =>
                match
                  StandardExpander::install_term_definition(
                    new_terms,
                    other,
                    TermDefinition::{
                      iri: None,
                      datatype: None,
                      container: None,
                      reverse: None,
                      local_context: None,
                      context_base_url: definition_base_url(flags, options),
                      index_mapping: None,
                      graph_secondary: None,
                      is_protected: protected_default,
                      language_mapping: None,
                      direction_mapping: None,
                      is_prefix: None,
                      nest: None,
                      simple_form: false,
                      graph_set: false,
                      container_set: false,
                    },
                    flags.override_protected,
                  ) {
                  Ok(_) => ()
                  Err(e) => return Err(e)
                }
              // 对象形态 term 定义推迟到第二遍（#t0007 oracle：同 context
              // 后置 prefix 定义——简单 term——须对其可用）
              JsonValue::Object(td_pairs) => deferred_td.push((other, td_pairs))
              _ =>
                return Err(
                  JsonLdError::InvalidContext(
                    "term definition must be a string, object or null",
                  ),
                )
            }
          }
        }
      }
      // 第二遍：对象形态 term 定义（#t0007 oracle——简单定义此时全部就绪，
      // 后置 prefix 可用）
      for deferred in deferred_td {
        match
          StandardExpander::process_expanded_term_definition(
            _self,
            new_terms,
            base,
            vocab,
            protected_default,
            flags,
            options,
            deferred.0,
            deferred.1,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      Ok(ActiveContext::{
        base,
        vocab,
        terms: new_terms,
        previous: previous_after(active, propagate),
        default_language,
        default_direction,
        compact_by_iri: None,
        compact_reverse: None,
        compact_prefixes: None,
      })
    }
    _ =>
      Err(JsonLdError::InvalidContext("local context must be object or array"))
  }
}

///|
/// 扩展 term 定义（对象形态，⑤批 A 组——判据①）：@id 位 = vocab 展开（自映射
/// 排除旧定义——#t0071 oracle）；@type 位 = 三形态 type mapping（"@id"/"@vocab"/
/// 绝对 IRI——#t0011/#t0054/#t0007 oracle）；@container/@language/@prefix/@nest
/// 验证（⑤后半——#tem01/#ter21/#tes01/#tes02/#ter22/#ter53/#ten05 oracle）；
/// @context 位 = 属性作用域 context（scoped-context 批：定义期校验 + 存留，
/// #tc032/#tc033 oracle）。关键字 term 必须自映射（#tec02 oracle：
/// keyword redefinition；#t0026 oracle：{"@id":"@type","@type":"@id"} 合法）
fn StandardExpander::process_expanded_term_definition(
  _self : StandardExpander,
  new_terms : Map[String, TermDefinition],
  base : String?,
  vocab : String?,
  protected_default : Bool,
  flags : ContextFlags,
  options : JsonLdOptions,
  term_name : String,
  td_pairs : Array[(String, JsonValue)],
) -> Result[Unit, JsonLdError] {
  let mut td_iri : String? = None
  let mut td_datatype : String? = None
  let mut td_container : ContainerType? = None
  let mut td_reverse : String? = None
  let mut td_graph_secondary : ContainerType? = None
  let mut td_graph_set = false
  let mut td_container_set = false
  let mut td_prefix = false
  let mut td_nest : String? = None
  let mut td_is_prefix : Bool? = None
  // 简单形态位：本函数只接 map 形 td（简单 string 形在调用方单独臂）——
  // REC 4.2.2 缺省 @prefix=false 只挂 map 形（#tp001 oracle 面）
  let td_simple = false
  let mut td_language : LanguageMember? = None
  let mut td_direction : LanguageMember? = None
  let mut td_local_context : JsonValue? = None
  // {"@id": null} 显式空映射（scoped-context 批）：区别于"无 @id 键"——
  // 不落 vocab 兜底，term 保留但 IRI 映射为 null（展开期该键丢弃）
  let mut td_id_null = false
  // td 级 @protected 覆盖上下文级默认（REC 4.2.2 步 10；非布尔 → invalid
  // @protected value、1.0 → invalid term definition）
  let mut td_protected = protected_default
  // 容器含 @type 标记（REC 4.2.2：container mapping includes @type 时——
  // 缺省 type mapping = @id，且只允许 @id/@vocab；#tm017/#tm018/#tm020 oracle）
  let mut td_container_has_type = false
  // 容器含 @index 标记（REC 4.2.2：@index mapping 的适用前提）
  let mut td_container_has_index = false
  // 索引映射（容器含 @index 且 index key ≠ @index 时，索引键写成属性——#tpi06~10）
  let mut td_index_mapping : String? = None
  for td_pair in td_pairs {
    match td_pair.0 {
      "@id" =>
        match td_pair.1 {
          // {"@id": null}：term 保留、无 IRI 映射（REC 4.2.2 @id 臂）
          JsonValue::Null => td_id_null = true
          JsonValue::String(iri) => {
            // 循环检测（⑤后半——#ter10 oracle）：值 = compact 形且 prefix =
            // 自身 term → cyclic IRI mapping
            if is_self_prefix_compact(iri, term_name) {
              return Err(JsonLdError::InvalidContext("cyclic IRI mapping"))
            }
            // 自映射排除（#t0071 oracle：重定义 @id = 自身时旧定义不查表）
            let lookup_terms = if iri == term_name {
              terms_without(new_terms, term_name)
            } else {
              new_terms
            }
            let building = ActiveContext::{
              base,
              vocab,
              terms: lookup_terms,
              previous: None,
              default_language: None,
              default_direction: None,
              compact_by_iri: None,
              compact_reverse: None,
              compact_prefixes: None,
            }
            match IriExpander::expand_iri(_self, building, iri, false, true) {
              Ok(k) => {
                // @context 别名禁（#ter19 oracle：@id 映射 @context →
                // invalid keyword alias）
                if k is "@context" {
                  return Err(
                    JsonLdError::InvalidContext("invalid keyword alias"),
                  )
                }
                // keyword 形态非真关键字 → **整个定义放弃**（REC 4.2.2 @id 臂明文：
                // "If the value associated with the @id entry is not a keyword, but
                // has the form of a keyword, **return**; processors SHOULD generate
                // a warning"——不是"继续走到无 @id 兜底"）。#t0120 oracle：term 无定义
                // ⇒ 键回落 vocab 拼接（属性 = vocab/ignoreMe）
                if has_keyword_form(k) && !is_keyword(k) {
                  return Ok(())
                }
                td_iri = Some(k)
                // term 名一致性检查（REC 4.2.2 @id 臂；#ter43 负例 oracle /
                // #t0026 正例 oracle——1.0 无此检查）
                match
                  StandardExpander::check_term_name_consistency(
                    _self, building, term_name, k, options,
                  ) {
                  Ok(_) => ()
                  Err(e) => return Err(e)
                }
                // td_iri 由前述条件写入（keyword 形态非真关键字 → 保持 None）
              }
              Err(e) => return Err(e)
            }
          }
          _ => return Err(JsonLdError::InvalidContext("@id must be a string"))
        }
      "@type" =>
        match td_pair.1 {
          JsonValue::String(t) =>
            // "@none"（ttn02 批——REC 1.1）：显式**无 coercion**——串/数/布尓
            // 全按无 datatype 值对象走、@id 形照旧节点引用（tn02-out oracle：
            // "string"→{@value}、true→{@value:true}、{"@id"}→节点引用）。1.0
            // 模式无此关键字 → invalid type mapping。下游与 td_datatype=None
            // 同路——datatype 位存 None
            if t is "@none" {
              if options.processing_mode is JsonLd10 {
                return Err(JsonLdError::InvalidContext("invalid type mapping"))
              }
              // keyword 形标记（役33——None 与「无 @type」双义的解；消费位
              // 按形接闸：coercion 短路/object_fit 放行/bare 早退跳过）
              td_datatype = Some("@none")
            } else {
              // 关键字形态原样（"@id"/"@vocab"/"@json"——丁批）；其余 vocab 展开
              let expanded = if t is ("@id" | "@vocab" | "@json") {
                t
              } else {
                let building = ActiveContext::{
                  base,
                  vocab,
                  terms: new_terms,
                  previous: None,
                  default_language: None,
                  default_direction: None,
                  compact_by_iri: None,
                  compact_reverse: None,
                  compact_prefixes: None,
                }
                match IriExpander::expand_iri(_self, building, t, false, true) {
                  Ok(k) => k
                  Err(e) => return Err(e)
                }
              }
              // type mapping 只收关键字形态（@id/@vocab/@json——丁批）或绝对
              // IRI；无 vocab 时 **curie 形**（含冒号）相对形原样收留
              //（#tc024 oracle——"ex:Number" 前缀未定义，与值 datatype 同串
              // 对上）；路径相对形拒（#ter23 oracle——"relative/iri" 无冒号
              // invalid）；空节点标号恒拒（#ter13 oracle——"_:not-an-iri"）
              if !(expanded is ("@id" | "@vocab" | "@json" | "@none") ||
                is_valid_absolute_iri(expanded) ||
                (
                  vocab is None &&
                  expanded == t &&
                  t.contains(":") &&
                  !t.has_prefix("_:")
                )) {
                return Err(JsonLdError::InvalidContext("invalid type mapping"))
              }
              td_datatype = Some(expanded)
            }
          _ => return Err(JsonLdError::InvalidContext("@type must be a string"))
        }
      "@container" =>
        // 容器映射验证（⑤后半——#tem01/#ter21/#tes01/#tes02 oracle）：
        // 串值按模式白名单、数组仅 1.1 图组合
        match validate_container_value(td_pair.1, options) {
          Ok(_) => {
            // 存 List/Set/Language/Type 四态（@type 批——type map 应用依赖 Type）；
            // @id/@graph 容器应用挂账存 None
            match td_pair.1 {
              JsonValue::String("@language") =>
                td_container = Some(ContainerType::Language)
              JsonValue::String("@list") =>
                td_container = Some(ContainerType::List)
              JsonValue::String("@set") =>
                td_container = Some(ContainerType::Set)
              JsonValue::String("@type") =>
                td_container = Some(ContainerType::Type)
              JsonValue::String("@index") =>
                td_container = Some(ContainerType::Index)
              JsonValue::String("@id") => td_container = Some(ContainerType::Id)
              JsonValue::String("@graph") =>
                td_container = Some(ContainerType::Graph)
              JsonValue::Array(combo_items) => {
                // graph 组合（[@graph, @id|@index|@set]——graph 容器族）：
                // container=Graph + 次级存 graph_secondary
                let mut has_graph = false
                let mut secondary : ContainerType? = None
                for combo in combo_items {
                  match combo {
                    JsonValue::String("@graph") => has_graph = true
                    JsonValue::String("@id") =>
                      secondary = Some(ContainerType::Id)
                    JsonValue::String("@index") =>
                      secondary = Some(ContainerType::Index)
                    // @set 不占次级但置保形位（展开形态与裸 @graph 同
                    // ——#t0080；压缩侧出形分叉靠 graph_set——#t0078/#t0109）
                    JsonValue::String("@set") => td_graph_set = true
                    _ => ()
                  }
                }
                let mut combo_key : ContainerType? = None
                for combo in combo_items {
                  match combo {
                    JsonValue::String("@id") =>
                      if combo_key is None {
                        combo_key = Some(ContainerType::Id)
                      }
                    JsonValue::String("@type") =>
                      if combo_key is None {
                        combo_key = Some(ContainerType::Type)
                      }
                    JsonValue::String("@language") =>
                      if combo_key is None {
                        combo_key = Some(ContainerType::Language)
                      }
                    JsonValue::String("@index") =>
                      if combo_key is None {
                        combo_key = Some(ContainerType::Index)
                      }
                    _ => ()
                  }
                }
                if has_graph {
                  td_container = Some(ContainerType::Graph)
                  td_graph_secondary = secondary
                } else if td_graph_set && combo_key is Some(_) {
                  // @set 并容（[#@id|@type|@language|@index, @set]——#ts002）：
                  // container = 主键态 + container_set 保形位（map 发射保数组）
                  td_container = combo_key
                  td_container_set = true
                } else if combo_items.length() == 1 {
                  // 单元素数组容器 = 裸形等价（#ts001 oracle——["@list"]
                  // 等价 "@list"；REC 1.1 数组形逐值处理）
                  match combo_items[0] {
                    JsonValue::String("@list") =>
                      td_container = Some(ContainerType::List)
                    JsonValue::String("@set") =>
                      td_container = Some(ContainerType::Set)
                    JsonValue::String("@language") =>
                      td_container = Some(ContainerType::Language)
                    JsonValue::String("@type") =>
                      td_container = Some(ContainerType::Type)
                    JsonValue::String("@index") =>
                      td_container = Some(ContainerType::Index)
                    JsonValue::String("@id") =>
                      td_container = Some(ContainerType::Id)
                    _ => ()
                  }
                }
              }
              _ => ()
            }
            // 容器含 @type 的原始形态标记（数组形态亦算——REC 4.2.2 隐式 type
            // mapping 规则按"container mapping includes @type"判，非按存储态）
            match td_pair.1 {
              JsonValue::String("@type") => td_container_has_type = true
              JsonValue::String("@index") => td_container_has_index = true
              JsonValue::Array(items) =>
                for item in items {
                  match item {
                    JsonValue::String("@type") => td_container_has_type = true
                    JsonValue::String("@index") => td_container_has_index = true
                    _ => ()
                  }
                }
              _ => ()
            }
          }
          Err(e) => return Err(e)
        }
      "@language" =>
        // 语言映射（丙批应用化——#ter22 验证保留：非串 → invalid language
        // mapping；null = 显式压制默认语言）
        match td_pair.1 {
          JsonValue::String(lang) =>
            td_language = Some(LanguageMember::Set(lang))
          JsonValue::Null => td_language = Some(LanguageMember::Null)
          _ =>
            return Err(JsonLdError::InvalidContext("invalid language mapping"))
        }
      "@direction" =>
        // 方向映射（丙批——#tdi01/#tdi04~#tdi07 oracle）：ltr/rtl 或 null
        // 压制；非法值 → invalid base direction
        match td_pair.1 {
          JsonValue::String(dir) =>
            if dir is ("ltr" | "rtl") {
              td_direction = Some(LanguageMember::Set(dir))
            } else {
              return Err(JsonLdError::InvalidContext("invalid base direction"))
            }
          JsonValue::Null => td_direction = Some(LanguageMember::Null)
          _ => return Err(JsonLdError::InvalidContext("invalid base direction"))
        }
      "@prefix" => {
        // 前缀标记验证（⑤后半——#ter53 oracle）：须布尔；true 记录供
        // keyword 别名组合禁（#tpr33）。1.0 门 + 冒号名禁（#tep07/#tep09
        // oracle——@prefix 系 1.1 特性；带 ":" 的 term 名 + @prefix:true =
        // invalid term definition）
        if options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
        match td_pair.1 {
          JsonValue::Bool(flag) => {
            if flag && term_name.contains(":") {
              return Err(JsonLdError::InvalidContext("invalid term definition"))
            }
            td_prefix = flag
            td_is_prefix = Some(flag)
          }
          _ => return Err(JsonLdError::InvalidContext("invalid @prefix value"))
        }
      }
      "@nest" => {
        // nest 验证（⑤后半——#ten05 oracle）：须串且关键字位仅 "@nest"。
        // 1.0 门（#tep10 oracle——@nest 系 1.1 特性，invalid term definition）；
        // 非关键字值须为已定义 term 且展开 = @nest（#ten01 oracle——"unknown"
        // 未定义 = invalid @nest value）
        if options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
        match td_pair.1 {
          JsonValue::String(nest_term) => {
            let keyword_named = nest_term.get_char(0) is Some('@')
            if keyword_named {
              if nest_term != "@nest" {
                return Err(JsonLdError::InvalidContext("invalid @nest value"))
              }
            } else {
              // 非关键字别名：须为在册 term 且 iri = @nest（本 context 已处理
              // 面——#ten01 负例无此 term 即红；跨 context 别名挂 deferred 细研）
              let mut alias_ok = false
              match new_terms.get(nest_term) {
                Some(alias_td) =>
                  match alias_td.iri {
                    Some("@nest") => alias_ok = true
                    _ => ()
                  }
                None => ()
              }
              if !alias_ok {
                return Err(JsonLdError::InvalidContext("invalid @nest value"))
              }
            }
            td_nest = Some(nest_term)
          }
          _ => return Err(JsonLdError::InvalidContext("invalid @nest value"))
        }
      }
      "@context" => {
        // 属性作用域 context（scoped-context 批——REC 4.2.2 @context 臂）：
        // 1.0 模式禁（invalid term definition）；1.1 模式在**定义期**调用
        // Context Processing 校验——结果丢弃（REC 注记），任何错误 → invalid
        // scoped context（#tc032/#tc033 oracle：未被使用的嵌入 context 仍须
        // 检查）。校验通过则存 local_context，展开期在该 term 的值展开前再
        // 处理套用（apply_property_scoped_context）
        if options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
        let building = ActiveContext::{
          base,
          vocab,
          terms: new_terms,
          previous: None,
          default_language: None,
          default_direction: None,
          compact_by_iri: None,
          compact_reverse: None,
          compact_prefixes: None,
        }
        match
          ContextProcessor::process_context(
            _self,
            building,
            td_pair.1,
            // REC 4.2.2 步 21.3：override protected=true、remote contexts 传
            // **现链**（string 臂递归从不原地改链——新建数组追加，引用共享即
            // 副本语义）、validate_scoped=false（链上已有 → 跳过非错误）
            {
              propagate: true,
              override_protected: true,
              base_url: flags.base_url,
              remote_contexts: flags.remote_contexts,
              validate_scoped: false,
            },
            options,
          ) {
          Ok(_) => td_local_context = Some(td_pair.1)
          // 未落码透传（诊断口径：Unsupported = 落码活账，不当作 scoped 校验失败）
          Err(JsonLdError::Unsupported(m)) =>
            return Err(JsonLdError::Unsupported(m))
          Err(_) =>
            return Err(JsonLdError::InvalidContext("invalid scoped context"))
        }
      }
      "@reverse" =>
        // 反向映射（reverse 批——#ter15 oracle：非串 → invalid IRI mapping；
        // #ter50 oracle：串经 vocab 展开后非绝对 → invalid IRI mapping——
        // documentRelative=false，base 注入不救）
        match td_pair.1 {
          JsonValue::String(rev) => {
            let building = ActiveContext::{
              base,
              vocab,
              terms: new_terms,
              previous: None,
              default_language: None,
              default_direction: None,
              compact_by_iri: None,
              compact_reverse: None,
              compact_prefixes: None,
            }
            match IriExpander::expand_iri(_self, building, rev, false, true) {
              Ok(k) =>
                // keyword 形态非真关键字（"@ignoreMe" 形态）→ **整个定义放弃**
                // （REC 4.2.2 @reverse 臂明文："If the value associated with the
                // @reverse entry is a string having the form of a keyword, **return**;
                // processors SHOULD generate a warning"）。#tpr38/#tpr39 oracle：
                // term 无定义 ⇒ 键回落普通语义（不落反向映射），且**不得**再走到
                // 无 @id 兜底去报 invalid IRI mapping
                if has_keyword_form(k) && !is_keyword(k) {
                  return Ok(())
                } else if is_valid_absolute_iri(k) {
                  td_reverse = Some(k)
                } else {
                  return Err(JsonLdError::InvalidIri("invalid IRI mapping"))
                }
              Err(e) => return Err(e)
            }
          }
          _ => return Err(JsonLdError::InvalidIri("invalid IRI mapping"))
        }
      "@protected" => {
        // td 级保护位（REC 4.2.2 步 10）：非布尔 → invalid @protected value；
        // 1.0 模式 → invalid term definition
        match td_pair.1 {
          JsonValue::Bool(flag) => td_protected = flag
          _ =>
            return Err(JsonLdError::InvalidContext("invalid @protected value"))
        }
        if options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
      }
      "@index" => {
        // 索引映射（REC 4.2.2）：1.0 模式或容器不含 @index → invalid term definition；
        // 值须为串；IRI 展开结果须为 **IRI**（关键字/非绝对 → invalid term definition）
        // oracle：#tpi01（1.0 拒）/ #tpi03（关键字值拒）/ #tpi04（非串拒）
        if options.processing_mode is JsonLd10 || !td_container_has_index {
          return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
        match td_pair.1 {
          JsonValue::String(index_name) => {
            let building = ActiveContext::{
              base,
              vocab,
              terms: new_terms,
              previous: None,
              default_language: None,
              default_direction: None,
              compact_by_iri: None,
              compact_reverse: None,
              compact_prefixes: None,
            }
            match
              IriExpander::expand_iri(_self, building, index_name, false, true) {
              Ok(expanded_index_key) =>
                if is_valid_absolute_iri(expanded_index_key) {
                  // **存原始值**（term 名，如 "prop"）——展开期两用：① Value Expansion
                  // 以它为 active property（取该 term 的 type mapping，#tpi08/#tpi10
                  // oracle：`@index: "prop"` 且 prop 有 @type:@vocab ⇒ 索引成节点引用）
                  // ② **expanded index key** = 用时期再 IRI 展开得属性 IRI
                  td_index_mapping = Some(index_name)
                } else {
                  return Err(
                    JsonLdError::InvalidContext("invalid term definition"),
                  )
                }
              Err(e) => return Err(e)
            }
          }
          _ =>
            return Err(JsonLdError::InvalidContext("invalid term definition"))
        }
      }
      // 其余键按 REC 4.2.2 键白名单报错（"any entry other than @id, @reverse,
      // @container, @context, @direction, @index, @language, @nest, @prefix,
      // @protected, or @type → invalid term definition"）
      other =>
        return Err(
          JsonLdError::InvalidContext("invalid term definition (\{other})"),
        )
    }
  }
  // @id 与 @reverse 同 td 互斥（#ter14 oracle：invalid reverse property）；
  // @container 与 @reverse 同 td 互斥（#ter17 oracle：reverse 项不带容器）
  // reverse 项容器白名单（REC 4.2.2："if its value is neither @set, nor @index, nor
  // null, an invalid reverse property error"）——即 reverse **允许** @set/@index
  // （#t0063/#t0131 oracle：反向属性 + index 容器）；@id/@list/@language/@graph 等 → 错
  if td_reverse is Some(_) {
    if td_iri is Some(_) || td_id_null {
      return Err(JsonLdError::InvalidContext("invalid reverse property"))
    }
    match td_container {
      Some(ContainerType::Set) | Some(ContainerType::Index) | None => ()
      _ => return Err(JsonLdError::InvalidContext("invalid reverse property"))
    }
  }
  // reverse × nest 同 td 互斥（#ten06 oracle：invalid reverse property）
  // keyword 别名 × @prefix 组合禁（#tpr33 oracle）：IRI 映射为真关键字的 term
  // 携带 @prefix → invalid term definition
  let keyword_aliased = match td_iri {
    Some(k) => is_keyword(k)
    None => false
  }
  if td_prefix && keyword_aliased {
    return Err(JsonLdError::InvalidContext("invalid term definition"))
  }
  // reverse × nest 组合禁（#ten06 oracle）：@reverse term 携带 @nest →
  // invalid reverse property
  if td_reverse is Some(_) && td_nest is Some(_) {
    return Err(JsonLdError::InvalidContext("invalid reverse property"))
  }
  // 容器含 @type 的隐式 type mapping（REC 4.2.2）：未声明 @type ⇒ 置 @id；
  // 已声明则须为 @id/@vocab，否则 invalid type mapping（#tm017/#tm018/#tm019/
  // #tm020 oracle）
  if td_container_has_type {
    match td_datatype {
      None => td_datatype = Some("@id")
      Some(existing) =>
        if !(existing is "@id" || existing is "@vocab") {
          return Err(JsonLdError::InvalidContext("invalid type mapping"))
        }
    }
  }
  // 关键字面（REC 4.2.2 开头三步，@protected 批——#pr30/#pr31/#pr32 oracle）：
  // ① keyword term 的 td 值只允许"仅 {@container:@set} 和/或 {@protected}"——
  //    符合则 IRI 映射 = 该关键字本身（关键字可被保护）；② @type + 1.0 → 错；
  // ③ 其余关键字重定义 → keyword redefinition（#tec02 oracle）
  if is_jsonld_keyword(term_name) {
    if options.processing_mode is JsonLd10 && term_name is "@type" {
      return Err(JsonLdError::InvalidContext("keyword redefinition"))
    }
    let mut only_allowed_entries = true
    let mut has_allowed_entry = false
    let mut keyword_container : ContainerType? = None
    for td_pair in td_pairs {
      match td_pair.0 {
        "@container" =>
          match td_pair.1 {
            JsonValue::String("@set") => {
              keyword_container = Some(ContainerType::Set)
              has_allowed_entry = true
            }
            _ => only_allowed_entries = false
          }
        "@protected" => has_allowed_entry = true // 值校验已在 td 键臂完成
        _ => only_allowed_entries = false
      }
    }
    // 空 map 不满足（"only either **or both of** following entries" ⇒ 须至少一条；
    // #tec02 oracle：`{"@type": {}}` → keyword redefinition）
    if !only_allowed_entries || !has_allowed_entry {
      return Err(JsonLdError::InvalidContext("keyword redefinition"))
    }
    match
      StandardExpander::install_term_definition(
        new_terms,
        term_name,
        TermDefinition::{
          iri: Some(term_name),
          datatype: None,
          container: keyword_container,
          reverse: None,
          local_context: None,
          context_base_url: definition_base_url(flags, options),
          index_mapping: None,
          graph_secondary: None,
          is_protected: td_protected,
          language_mapping: None,
          direction_mapping: None,
          is_prefix: None,
          nest: td_nest,
          simple_form: false,
          graph_set: false,
          container_set: false,
        },
        flags.override_protected,
      ) {
      Ok(_) => return Ok(())
      Err(e) => return Err(e)
    }
  }
  // 关键字**形**但非关键字（如 "@ignoreMe"）：REC "return; processors SHOULD
  // generate a warning"（忽略定义）——该忽略面挂 #pr34~#pr39 批；保守报错
  if term_name.get_char(0) is Some('@') {
    return Err(JsonLdError::InvalidContext("keyword redefinition"))
  }
  // 无 @id 位三路：
  // ① {"@id": null} → 显式 null 映射（term 保留，展开期键丢弃）；
  // ② reverse-only term → IRI 映射 = reverse IRI（REC 4.2.2 @reverse 臂：
  //    "set the IRI mapping of definition to the result of IRI expanding"；
  //    作正属性由 reverse 路由拦截，非靠 IRI 缺失）
  // ③ 其余 → term 名自身 vocab 展开（spec §6.1；t0011 路径），且**必须落成
  //    绝对 IRI 或 bnode**——无 @vocab 的相对 term 名 → invalid IRI mapping
  //    （REC 4.2.2 末路；#tc032/#tc033 oracle 的触发点）
  let final_iri = if td_id_null {
    None
  } else {
    match td_iri {
      Some(iri) => Some(iri)
      None =>
        match td_reverse {
          Some(rev) => Some(rev)
          None => {
            let building = ActiveContext::{
              base,
              vocab,
              terms: new_terms,
              previous: None,
              default_language: None,
              default_direction: None,
              compact_by_iri: None,
              compact_reverse: None,
              compact_prefixes: None,
            }
            match
              IriExpander::expand_iri(_self, building, term_name, false, true) {
              Ok(k) =>
                // 无 vocab 可拼的相对 term 名 ⇒ **invalid IRI mapping**（REC 4.2.2
                // 末路："If it does not have a vocabulary mapping, an invalid IRI
                // mapping error has been detected"）。#tc032/#tc033 oracle：**未被
                // 使用**的嵌入 context 亦须在定义期报错（invalid scoped context）。
                // 〔曾经的软化（None 忽略）是为 tpr38 让路，属**修错层**——tpr38 的
                // 正解在 td @reverse 臂的 REC "return"（见该臂注释）〕
                if is_valid_absolute_iri(k) || is_bnode_label(k) {
                  Some(k)
                } else {
                  return Err(JsonLdError::InvalidIri("invalid IRI mapping"))
                }
              Err(e) => return Err(e)
            }
          }
        }
    }
  }
  StandardExpander::install_term_definition(
    new_terms,
    term_name,
    TermDefinition::{
      iri: final_iri,
      datatype: td_datatype,
      container: td_container,
      reverse: td_reverse,
      local_context: td_local_context,
      context_base_url: definition_base_url(flags, options),
      index_mapping: td_index_mapping,
      graph_secondary: td_graph_secondary,
      language_mapping: td_language,
      direction_mapping: td_direction,
      is_protected: td_protected,
      is_prefix: td_is_prefix,
      nest: td_nest,
      simple_form: td_simple,
      graph_set: td_graph_set,
      container_set: td_container_set,
    },
    flags.override_protected,
  )
}

///|
/// JSON-LD 关键字全集判定（含 context 层键——元素层分派表只收 13 个元素层关键字，
/// 而关键字重定义规则要全集）
fn is_jsonld_keyword(name : String) -> Bool {
  name
  is ("@base"
  | "@container"
  | "@context"
  | "@direction"
  | "@graph"
  | "@id"
  | "@import"
  | "@included"
  | "@index"
  | "@json"
  | "@language"
  | "@list"
  | "@nest"
  | "@none"
  | "@prefix"
  | "@propagate"
  | "@protected"
  | "@reverse"
  | "@set"
  | "@type"
  | "@value"
  | "@version"
  | "@vocab")
}

///|
/// 容器映射等价（TermDefinition 等价判定用；避免给 ContainerType 加 derive(Eq)）
fn container_type_matches(a : ContainerType, b : ContainerType) -> Bool {
  match (a, b) {
    (List, List)
    | (Set, Set)
    | (Language, Language)
    | (Index, Index)
    | (Id, Id) => true
    (Type, Type) | (Graph, Graph) => true
    _ => false
  }
}

///|
/// term 定义等价判定（REC 4.2.2 保护面："definition is not the same as previous
/// definition (**other than the value of protected**)"）——**除 protected 位外全等**
/// （iri/datatype/container/reverse/local_context 逐个比；#pr23/#pr24/#pr25/#pr27/
/// #pr41 等价允许 与 #pr26/#pr28/#pr42 不等价即错 的分界）
/// 先验注记：local_context 按 JsonValue 结构比较（键序敏感）——同语义异序的
/// scoped context 会判不等价，本批无 oracle，挂账
fn term_definitions_equivalent(
  previous : TermDefinition,
  next : TermDefinition,
) -> Bool {
  let iri_same = match (previous.iri, next.iri) {
    (None, None) => true
    (Some(a), Some(b)) => a == b
    _ => false
  }
  let datatype_same = match (previous.datatype, next.datatype) {
    (None, None) => true
    (Some(a), Some(b)) => a == b
    _ => false
  }
  let container_same = match (previous.container, next.container) {
    (None, None) => true
    (Some(a), Some(b)) => container_type_matches(a, b)
    _ => false
  }
  let reverse_same = match (previous.reverse, next.reverse) {
    (None, None) => true
    (Some(a), Some(b)) => a == b
    _ => false
  }
  let local_context_same = match (previous.local_context, next.local_context) {
    (None, None) => true
    (Some(a), Some(b)) => a == b
    _ => false
  }
  iri_same &&
  datatype_same &&
  container_same &&
  reverse_same &&
  local_context_same
}

///|
/// 是否含任何受保护 term（空化门用：REC 4.1.2 步 5.2.1 "active context contains
/// any protected term definitions"）
fn has_protected_term(active : ActiveContext) -> Bool {
  for _, term_definition in active.terms {
    if term_definition.is_protected {
      return true
    }
  }
  false
}

///|
/// term 定义安装（REC 4.2.2 末段，@protected 批）：保护面 = `override protected =
/// false` 且已有定义受保护 ⇒ 新定义须与旧定义**等价（除 protected 位）**；
/// 等价 ⇒ **保留旧定义**（"Set definition to previous definition to retain the value
/// of protected"——#pr42 oracle）；不等价 ⇒ **protected term redefinition**。
/// 简单臂/td 对象臂/关键字臂三处同源（一笔一账：保护检查只有这一处）
fn StandardExpander::install_term_definition(
  new_terms : Map[String, TermDefinition],
  term_name : String,
  definition : TermDefinition,
  override_protected : Bool,
) -> Result[Unit, JsonLdError] {
  match new_terms.get(term_name) {
    Some(previous) =>
      if !override_protected && previous.is_protected {
        if term_definitions_equivalent(previous, definition) {
          return Ok(()) // 保留旧定义（含 protected 位）
        }
        return Err(JsonLdError::InvalidContext("protected term redefinition"))
      }
    None => ()
  }
  new_terms[term_name] = definition
  Ok(())
}

///|
/// 容器映射合法性验证（⑤后半——#tem01/#ter21/#tes01/#tes02 oracle）：
/// 串值 = 1.1 白名单 {@list,@set,@index,@language,@id,@type,@graph} /
/// 1.0 窄名单 {@list,@set,@index,@language}；数组仅 1.1 图组合
/// [@graph, @id|@index|@set]；其余类型/值 → invalid container mapping。
/// 仅验证不启用应用（container 字段仅 @language 存值——#ter35 依赖）
fn validate_container_value(
  value : JsonValue,
  options : JsonLdOptions,
) -> Result[Unit, JsonLdError] {
  let is_10 = options.processing_mode is JsonLd10
  match value {
    JsonValue::String(c) => {
      let valid_11 = c
        is ("@list"
        | "@set"
        | "@index"
        | "@language"
        | "@id"
        | "@type"
        | "@graph")
      let valid_10 = c is ("@list" | "@set" | "@index" | "@language")
      if (if is_10 { valid_10 } else { valid_11 }) {
        Ok(())
      } else {
        Err(JsonLdError::InvalidContext("invalid container mapping"))
      }
    }
    JsonValue::Array(items) => {
      // 数组形容器三形（1.1）：①单元素 = 裸形等价（#ts001 oracle——
      // ["@list"] 等价 "@list"）；②@graph 组合（#t0083 oracle：@graph +
      // 至多一个 @id|@index + 可选 @set，禁重复/未知成员）；③@set 并容
      //（#ts002 oracle：@set + 至多一个 @id|@type|@language|@index）。
      // @list 禁组合；空数组/未知成员拒
      if is_10 {
        return Err(JsonLdError::InvalidContext("invalid container mapping"))
      }
      let mut has_graph = false
      let mut has_set = false
      let mut has_list = false
      let mut key_count = 0
      let mut valid = items.length() > 0
      for item in items {
        match item {
          JsonValue::String("@graph") =>
            if has_graph {
              valid = false
            } else {
              has_graph = true
            }
          JsonValue::String("@set") =>
            if has_set {
              valid = false
            } else {
              has_set = true
            }
          JsonValue::String("@list") =>
            if has_list {
              valid = false
            } else {
              has_list = true
            }
          JsonValue::String(s) =>
            if s is ("@id" | "@type" | "@language" | "@index") {
              key_count += 1
            } else {
              valid = false
            }
          _ => valid = false
        }
      }
      let graph_combo = has_graph && key_count <= 1
      let set_combo = has_set && !has_list && !has_graph && key_count <= 1
      if valid && (items.length() == 1 || graph_combo || set_combo) {
        Ok(())
      } else {
        Err(JsonLdError::InvalidContext("invalid container mapping"))
      }
    }
    _ => Err(JsonLdError::InvalidContext("invalid container mapping"))
  }
}

///|
/// compact 自指环检测（⑤后半——#ter10 oracle）：值含冒号且冒号前 prefix =
/// 被定义的 term 名自身 → 展开即环。**豁免**：suffix 以 "//" 开头 =
/// protocol-like IRI（scheme 形态——#t0067 oracle："http://…" 作 term 值非环）
fn is_self_prefix_compact(value : String, term_name : String) -> Bool {
  match colon_index(value) {
    Some(at) =>
      if at > 0 {
        let prefix = split_first_colon(value, at).0
        prefix == term_name &&
        !(split_first_colon(value, at).1.get_char(0) is Some('/') &&
        split_first_colon(value, at).1.get_char(1) is Some('/'))
      } else {
        false
      }
    None => false
  }
}

///|
/// terms 拷贝并剔除单键（自映射排除用——#t0071/#t0072 oracle）
fn terms_without(
  terms : Map[String, TermDefinition],
  exclude : String,
) -> Map[String, TermDefinition] {
  let out : Map[String, TermDefinition] = Map([])
  for key, definition in terms {
    if key != exclude {
      out[key] = definition
    }
  }
  out
}

///|
/// list/set 对象拦截与展开（C 组——判据①）：值对象键纯 {@list} 或纯 {@set}
/// （混入他键/双键 → invalid set or list object——#ter41 oracle）。
/// @list → [List(元素)]（元素经 expand_list_item——1.0 list-of-lists 门控）；
/// @set → 元素摊平为属性多值（不包 wrapper——#t0004 oracle）。
/// Ok(None) = 非 list/set 对象（调用方走既有路由）
fn StandardExpander::expand_list_set_object(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  obj_pairs : Array[(String, JsonValue)],
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue]?, JsonLdError] {
  let mut list_value : JsonValue? = None
  let mut set_value : JsonValue? = None
  let mut index_value : String? = None
  let mut impure = false
  for pair in obj_pairs {
    // 键别名识别（t0014 批——REC 键归一先于对象形态判定）：别名 term（"set" →
    // "@set"）与裸键（#t0004 oracle 不变）同路命中拦截；普通属性键两查皆否
    // → impure 走既有路由
    if StandardExpander::key_expands_to_keyword(self, active, pair.0, "@list") {
      list_value = Some(pair.1)
    } else if StandardExpander::key_expands_to_keyword(
        self,
        active,
        pair.0,
        "@set",
      ) {
      set_value = Some(pair.1)
    } else if StandardExpander::key_expands_to_keyword(
        self,
        active,
        pair.0,
        "@index",
      ) {
      // @index 随 @list 值对象合法（#t0041 oracle——index 挂 list 贯通压缩；
      // 非 impure）
      match pair.1 {
        JsonValue::String(index_word) => index_value = Some(index_word)
        _ => impure = true
      }
    } else {
      impure = true
    }
  }
  if list_value is None && set_value is None {
    let no_values : Array[ExpandedValue]? = None
    return Ok(no_values)
  }
  if impure || (list_value is Some(_) && set_value is Some(_)) {
    return Err(JsonLdError::InvalidList("invalid set or list object"))
  }
  let outcome : Result[Array[ExpandedValue]?, JsonLdError] = match list_value {
    Some(list_items) => {
      // 非数组 @list 值 = 单元素 list（#t0004 oracle："@list": "one item" →
      // {"@list": [{"@value": ...}]}）
      let items = match list_items {
        JsonValue::Array(items) => items
        single => [single]
      }
      let out : Array[ExpandedValue] = []
      for item in items {
        match
          StandardExpander::expand_list_item(self, active, term, item, options) {
          Ok(Some(v)) => out.push(v)
          Ok(None) => () // null 元素丢弃（1.1）
          Err(e) => return Err(e)
        }
      }
      // 1.0 模式：list 内嵌 list = list of lists（#ter32 oracle）
      if options.processing_mode is JsonLd10 {
        for v in out {
          match v {
            ExpandedValue::List(_) =>
              return Err(JsonLdError::InvalidList("list of lists"))
            _ => ()
          }
        }
      }
      let wrapped : Array[ExpandedValue]? = Some([
        ExpandedValue::List(out, index=index_value),
      ])
      Ok(wrapped)
    }
    None =>
      match set_value {
        Some(JsonValue::Array(items)) => {
          let out : Array[ExpandedValue] = []
          for item in items {
            match
              StandardExpander::expand_term_values_inner(
                self,
                active,
                term,
                item,
                None,
                options,
              ) {
              Ok(vs) =>
                for v in vs {
                  out.push(v)
                }
              Err(e) => return Err(e)
            }
          }
          let values : Array[ExpandedValue]? = Some(out)
          Ok(values)
        }
        Some(single) =>
          match
            StandardExpander::expand_term_values_inner(
              self,
              active,
              term,
              single,
              None,
              options,
            ) {
            Ok(vs) => {
              let values : Array[ExpandedValue]? = Some(vs)
              Ok(values)
            }
            Err(e) => Err(e)
          }
        None => {
          let no_values : Array[ExpandedValue]? = None
          Ok(no_values)
        }
      }
  }
  outcome
}

///|
/// list 元素展开（C 组——判据②）：数组 → 嵌套 List（1.1——#tli05/#tli07
/// oracle；1.0 → list of lists——#ter24 oracle）；list/set 对象 → 拦截器
/// 递归（#tli01 oracle：嵌套 @list 保留）；其余 → expand_term_values 单值
/// （coercion 保持 term 上下文——#t0023/#tli03 oracle）。
/// Ok(None) = null 元素丢弃（1.1）；递归一律走 expand_term_values_inner
///（容器包裹仅外层壳一次——防重入）
fn StandardExpander::expand_list_item(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  item : JsonValue,
  options : JsonLdOptions,
) -> Result[ExpandedValue?, JsonLdError] {
  match item {
    JsonValue::Array(inner) => {
      if options.processing_mode is JsonLd10 {
        return Err(JsonLdError::InvalidList("list of lists"))
      }
      let out : Array[ExpandedValue] = []
      for el in inner {
        match
          StandardExpander::expand_list_item(self, active, term, el, options) {
          Ok(Some(v)) => out.push(v)
          Ok(None) => () // null 元素丢弃（1.1）
          Err(e) => return Err(e)
        }
      }
      let nested : ExpandedValue? = Some(ExpandedValue::List(out, index=None))
      Ok(nested)
    }
    JsonValue::Object(obj_pairs) =>
      if obj_pairs.length() > 0 &&
        (obj_pairs[0].0 is "@list" || obj_pairs[0].0 is "@set") {
        match
          StandardExpander::expand_list_set_object(
            self, active, term, obj_pairs, options,
          ) {
          Ok(Some(vs)) => {
            if options.processing_mode is JsonLd10 {
              for v in vs {
                match v {
                  ExpandedValue::List(_) =>
                    return Err(JsonLdError::InvalidList("list of lists"))
                  _ => ()
                }
              }
            }
            if vs.length() == 1 {
              let single : ExpandedValue? = Some(vs[0])
              Ok(single)
            } else {
              let grouped : ExpandedValue? = Some(
                ExpandedValue::List(vs, index=None),
              )
              Ok(grouped)
            }
          }
          Ok(None) =>
            Err(JsonLdError::InvalidList("invalid set or list object"))
          Err(e) => Err(e)
        }
      } else {
        match
          StandardExpander::expand_term_values_inner(
            self,
            active,
            term,
            item,
            None,
            options,
          ) {
          Ok(vs) => {
            let first : ExpandedValue? = if vs.length() > 0 {
              Some(vs[0])
            } else {
              None
            }
            Ok(first)
          }
          Err(e) => Err(e)
        }
      }
    JsonValue::Null => {
      let none_value : ExpandedValue? = None
      Ok(none_value)
    }
    _ =>
      match
        StandardExpander::expand_term_values_inner(
          self,
          active,
          term,
          item,
          None,
          options,
        ) {
        Ok(vs) => {
          let first : ExpandedValue? = if vs.length() > 0 {
            Some(vs[0])
          } else {
            None
          }
          Ok(first)
        }
        Err(e) => Err(e)
      }
  }
}

///|
/// graph 容器展开（@graph 容器族——形态表见 todo §J2 开工钉）：
/// 裸/@set → 逐值包成 graph 节点（{"@graph": [...]}——graph 对象值也再包一层，
/// #t0102/#t0104 oracle）；@id → map 键 vocab 展开写条目 @id（保留既有——
/// id map 语义，#t0085）；@index → 键原样写条目 @index、"@none" 直出（#tm013）；
/// 条目值 = 既有 graph 对象 → 不二次包裹仅附键（#t0084/#t0087 oracle）；
/// 数组条目逐项、@index 附挂每个子项（#t0105 oracle）。值形态递归一律走
/// expand_term_values_inner（防容器壳重入——const §5）
fn StandardExpander::expand_graph_container(
  self : StandardExpander,
  active : ActiveContext,
  term : String,
  value : JsonValue,
  secondary : ContainerType?,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  match secondary {
    Some(ContainerType::Id) | Some(ContainerType::Index) => {
      // map 形态：值须 map（"Do not expand if value is not a map" 族语义）
      let entries = match value {
        JsonValue::Object(entries) => entries
        _ =>
          return Err(JsonLdError::InvalidValue("invalid graph container value"))
      }
      let out : Array[ExpandedValue] = []
      for entry in entries {
        // @none 别名识别（vocab 位展开——term 别名 "none": "@none"，
        // #tm014 oracle；字面 "@none"——#tm015/#tm013 oracle）：识别为 @none
        // 的条目直出不附挂
        let none_key = match
          IriExpander::expand_iri(self, active, entry.0, false, true) {
          Ok(k) => k is "@none"
          Err(_) => false
        }
        // @id 附挂值用 @id 值位旗（vocab=false/docRel=true——@id map 同款，
        // REC 明文，同形异判表「索引键展开旗位」行）
        let attach_id : String? = match secondary {
          Some(ContainerType::Id) =>
            if none_key {
              None
            } else {
              match
                IriExpander::expand_iri(self, active, entry.0, true, false) {
                Ok(k) => Some(k)
                Err(e) => return Err(e)
              }
            }
          _ => None
        }
        // 索引映射属性（@index mapping 语义在 graph 容器内的延伸——#tpi11）：
        // td 存原始名（const §5 两用值），用时 vocab 展开成属性 IRI；
        // 条目键（原串）成其值对象。@none/"@none" 映射不写
        let index_property : (String, ExpandedValue)? = match secondary {
          Some(ContainerType::Index) =>
            if none_key {
              None
            } else {
              match active.terms.get(term) {
                Some(term_definition) =>
                  match term_definition.index_mapping {
                    Some(mapping_name) =>
                      if mapping_name is "@none" {
                        None
                      } else {
                        match
                          IriExpander::expand_iri(
                            self, active, mapping_name, false, true,
                          ) {
                          Ok(prop_iri) => {
                            let index_value : (String, ExpandedValue) = (
                              prop_iri,
                              literal_of(entry.0, None),
                            )
                            Some(index_value)
                          }
                          Err(e) => return Err(e)
                        }
                      }
                    None => None
                  }
                None => None
              }
            }
          _ => None
        }
        // @index 附挂值 = 原始键名（两用值存原始形态——const §5）；**有索引
        // 映射时键走映射属性、不写 @index**（二者互斥——#tpi11 oracle）
        let attach_index : String? = if index_property is Some(_) {
          None
        } else {
          match secondary {
            Some(ContainerType::Index) =>
              if none_key {
                None
              } else {
                Some(entry.0)
              }
            _ => None
          }
        }
        // 条目值：数组逐项（每项独立 graph 对象、共享键附挂——#t0105）；单值单项
        let items = match entry.1 {
          JsonValue::Array(items) => items
          _ => [entry.1]
        }
        for item in items {
          match
            StandardExpander::expand_term_values_inner(
              self,
              active,
              entry.0,
              item,
              Some(entry.0),
              options,
            ) {
            Ok(vs) =>
              for v in vs {
                match v {
                  ExpandedValue::Node(node) =>
                    if node.graph is None {
                      // 普通节点条目 → 包成 graph 对象，键附挂**包裹层**
                      //（内层值节点不落 @index——#t0082 oracle）；
                      // 索引映射属性同层（#tpi11 oracle：与 @graph 同级）
                      let entry_properties : Array[
                        (String, Array[ExpandedValue]),
                      ] = match index_property {
                        Some((prop_iri, index_value)) =>
                          [(prop_iri, [index_value])]
                        None => []
                      }
                      let wrapped = ExpandedNode::{
                        id: attach_id,
                        types: [],
                        properties: entry_properties,
                        reverse_props: [],
                        graph: Some([ExpandedValue::Node(node)]),
                        included: None,
                        index: attach_index,
                      }
                      out.push(ExpandedValue::Node(wrapped))
                    } else {
                      // 既有 graph 对象：不二次包裹，键就地附挂
                      //（#t0084/#t0087 oracle）
                      match attach_id {
                        Some(id_key) =>
                          if node.id is None {
                            node.id = Some(id_key)
                          }
                        None => ()
                      }
                      match attach_index {
                        Some(index_key) => node.index = Some(index_key)
                        None => ()
                      }
                      match index_property {
                        Some((prop_iri, index_value)) =>
                          node.properties.push((prop_iri, [index_value]))
                        None => ()
                      }
                      out.push(ExpandedValue::Node(node))
                    }
                  _ => out.push(v)
                }
              }
            Err(e) => return Err(e)
          }
        }
      }
      Ok(out)
    }
    _ => {
      // 裸/@set：逐值包成 graph 节点（#t0079/#t0080/#t0102/#t0104 oracle——
      // graph 对象值也再包一层）
      let items = match value {
        JsonValue::Array(items) => items
        _ => [value]
      }
      let out : Array[ExpandedValue] = []
      for item in items {
        match
          StandardExpander::expand_term_values_inner(
            self,
            active,
            term,
            item,
            Some(term),
            options,
          ) {
          Ok(vs) =>
            for v in vs {
              let wrapper = ExpandedNode::{
                id: None,
                types: [],
                properties: [],
                reverse_props: [],
                graph: Some([v]),
                included: None,
                index: None,
              }
              out.push(ExpandedValue::Node(wrapper))
            }
          Err(e) => return Err(e)
        }
      }
      Ok(out)
    }
  }
}

///|
/// framing 旗 keyword 判（frameExpansion 保形面——spec §8.96 帧旗矩阵）：
/// 四旗以词形入 pattern properties；@embed 值域校验随 embed 状态机批
fn is_framing_flag_key(key : String) -> Bool {
  key == "@embed" ||
  key == "@explicit" ||
  key == "@requireAll" ||
  key == "@omitDefault"
}

///|
/// @default 值保形（帧旗批——spec §8.96）：`@null` 串/null ⇒ `"@null"`
/// 标桩（framing 算法 compaction 后替换为 null）；其余串词形保形（不作
/// IRI 展开——#t0009 "custom-default" oracle）；number/bool raw 保形；
/// 对象 → 值对象展开（Value）；数组摊开（`["@null"]` 单元素形——t0063）
fn StandardExpander::frame_preserve_default(
  self : StandardExpander,
  active : ActiveContext,
  raw : JsonValue,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  match raw {
    JsonValue::Null => Ok([literal_of("@null", None)])
    JsonValue::String(word) =>
      if word == "@null" {
        Ok([literal_of("@null", None)])
      } else {
        Ok([literal_of(word, None)])
      }
    JsonValue::Number(number_value) =>
      Ok([literal_of("\{number_value}", Some(JsonValue::Number(number_value)))])
    JsonValue::Bool(flag) =>
      Ok([
        literal_of(
          if flag {
            "true"
          } else {
            "false"
          },
          Some(JsonValue::Bool(flag)),
        ),
      ])
    JsonValue::Array(items) => {
      let out : Array[ExpandedValue] = []
      for item in items {
        match self.frame_preserve_default(active, item, options) {
          Ok(values) =>
            for v in values {
              out.push(v)
            }
          Err(e) => return Err(e)
        }
      }
      Ok(out)
    }
    JsonValue::Object(_) =>
      match StandardExpander::expand_element(self, active, raw, None, options) {
        Ok(v) => Ok([v])
        Err(e) => Err(e)
      }
  }
}

///|
/// 值 pattern 成分保形（spec §8.97 值 pattern 批）：`{}` 通配 = 空 pattern
/// 标桩；串 → 值（@type 位 IRI 经 type-scoped 展开，余词形）；null = 无
/// （None）；数组位由调用方摊开后逐项入此
fn StandardExpander::frame_value_pattern_component(
  self : StandardExpander,
  active : ActiveContext,
  key : String,
  raw : JsonValue,
) -> Result[ExpandedValue?, JsonLdError] {
  match raw {
    JsonValue::Object(default_pairs) =>
      if key == "@type" {
        // @type default 对象保形（t0064——值 pattern 预扫路径与关键字臂
        // 同归 expand_type_default_object；坍通配即失 @default）
        Ok(Some(self.expand_type_default_object(active, default_pairs)))
      } else {
        Ok(Some(ExpandedValue::Node(frame_empty_pattern())))
      }
    JsonValue::Null => Ok(None)
    JsonValue::String(word) =>
      if key == "@type" {
        // 负例 t0053（值 pattern 预扫路径的 @type 成分同帧文法值域——
        // bnode 标识符不在册 ⇒ invalid frame）
        if is_bnode_label(word) {
          Err(
            JsonLdError::InvalidValue(
              "invalid frame: @type must not include a blank node identifier",
            ),
          )
        } else {
          match IriExpander::expand_iri(self, active, word, true, true) {
            Ok(expanded) => Ok(Some(literal_of(expanded, None)))
            Err(e) => Err(e)
          }
        }
      } else {
        Ok(Some(literal_of(word, None)))
      }
    _ => Ok(None)
  }
}

///|
/// @type default 对象保形（t0064——REC "@type MAY be a map with a @default
/// entry, whose values are restricted to IRIs. Processors MUST preserve
/// this value when expanding. All other entries of a default object MUST
/// be ignored"）：@default 串 = type-scoped IRI 展开 ⇒ Node pattern 携
/// @default 字面（匹配臂无条件配 + 输出侧缺型注入的载体）；无 @default
/// （{} 通配）= 空 pattern
fn StandardExpander::expand_type_default_object(
  self : StandardExpander,
  active : ActiveContext,
  pairs : Array[(String, JsonValue)],
) -> ExpandedValue {
  let mut default_iri : String? = None
  for pair in pairs {
    if pair.0 is "@default" {
      match pair.1 {
        JsonValue::String(word) =>
          match IriExpander::expand_iri(self, active, word, true, true) {
            Ok(expanded) => default_iri = Some(expanded)
            Err(_) => ()
          }
        _ => ()
      }
    }
  }
  match default_iri {
    Some(iri) =>
      ExpandedValue::Node({
        id: None,
        types: [],
        properties: [("@default", [literal_of(iri, None)])],
        reverse_props: [],
        graph: None,
        included: None,
        index: None,
      })
    None => ExpandedValue::Node(frame_empty_pattern())
  }
}
