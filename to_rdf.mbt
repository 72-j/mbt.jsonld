///|
/// toRDF 处理接口 —— 手写实现（J3 落码；J1 定契约）
/// 契约面与 jsonld_gen.toml 的 handler_hook 对应（接口一致门钉住）。
pub(open) trait ToRdfProcessor {
  /// 展开后的节点对象图 → 四元组（@graph 图名与数据集处理在此）
  fn node_to_quads(
    Self,
    expanded : Array[ExpandedValue],
    options : JsonLdOptions,
  ) -> Result[Array[JsonLdQuad], JsonLdError]
}

///|
/// RDF 关键字词表（REC §6 发射位）
const RDF_TYPE_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>"

///|
const RDF_FIRST_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#first>"

///|
const RDF_REST_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#rest>"

///|
const RDF_NIL_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#nil>"

///|
const XSD_BOOLEAN : String = "http://www.w3.org/2001/XMLSchema#boolean"

///|
const XSD_INTEGER : String = "http://www.w3.org/2001/XMLSchema#integer"

///|
const XSD_DOUBLE : String = "http://www.w3.org/2001/XMLSchema#double"

///|
const XSD_STRING : String = "http://www.w3.org/2001/XMLSchema#string"

///|
const RDF_JSON_IRI : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"

///|
const I18N_PREFIX : String = "https://www.w3.org/ns/i18n#"

///|
const RDF_VALUE_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#value>"

///|
const RDF_LANGUAGE_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#language>"

///|
const RDF_DIRECTION_IRI : String = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#direction>"

///|
/// toRDF 落码状态（J3.1——REC §6 对应物）：bnode 序号 / emit-once 账 / 产物
priv struct ToRdfState {
  mut counter : Int
  emitted : Map[String, Bool]
  quads : Array[JsonLdQuad]
  mut reserved : Map[String, Bool]
  /// J3.4：rdfDirection 模式（None/"i18n-datatype"/"compound-literal"）
  direction_mode : String?
  /// J3.4：广义三元组放行（谓词位 bnode）
  generalized : Bool
}

///|
/// 词面转义（N-Quads 行结构保持所需最小集：\\ \" \n \r \t）。判定器
/// （parse_nquads）双端同用 canonical 归一 ⇒ 其余控制符词形与判定解耦。
fn nq_emit_escape(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '\\' => out.write_string("\\\\")
      '"' => out.write_string("\\\"")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// IRI 词面合法性（发射面；expand 面不受扰——分层归因，nq 发射层专用）：
/// ① 平面门（B组②——RFC 3986/3987 文法外字符弃——#tli12 oracle：
/// "http://invalid/<>/test" 含 `<`/`>` ⇒ 三元组不产出）；
/// ② 成分门（C组——spec 附录 IRI 正则：fragment 内不容第二 `#`——
/// #te111/#te112 oracle：vocab `…/rel2##fragment-works` 弃发，
/// `…/rel2#?query=works` 与 `…/rel2#../parent` 保留）
fn nq_iri_chars_legal(iri : String) -> Bool {
  let mut in_fragment = false
  for ch in iri {
    if ch == '#' {
      // 成分门：首个 "#" 开 fragment，fragment 内第二 "#" 非法（REC IRI 正则）
      if in_fragment {
        return false
      }
      in_fragment = true
    } else {
      let ok = (ch >= 'a' && ch <= 'z') ||
        (ch >= 'A' && ch <= 'Z') ||
        (ch >= '0' && ch <= '9') ||
        ch == '-' ||
        ch == '.' ||
        ch == '_' ||
        ch == '~' ||
        ch == ':' ||
        ch == '/' ||
        ch == '?' ||
        ch == '[' ||
        ch == ']' ||
        ch == '@' ||
        ch == '!' ||
        ch == '$' ||
        ch == '&' ||
        ch == '\'' ||
        ch == '(' ||
        ch == ')' ||
        ch == '*' ||
        ch == '+' ||
        ch == ',' ||
        ch == ';' ||
        ch == '=' ||
        ch == '%'
      if !ok {
        return false
      }
    }
  }
  true
}

///|
/// IRI 词面（绝对且字符合法 ⇒ `<iri>`；相对/空/文法外字符 ⇒ None——REC §6.3
/// 非绝对主体/谓词不产出）
fn nq_iri_term(iri : String) -> String? {
  if is_valid_absolute_iri(iri) && nq_iri_chars_legal(iri) {
    Some("<" + iri + ">")
  } else {
    None
  }
}

///|
/// 新生 bnode（序号跳过在册标签——预扫保留集 + 已发射键）
fn nq_fresh_bnode(state : ToRdfState) -> String {
  let mut term = "_:b\{state.counter}"
  state.counter += 1
  while state.reserved.contains(term) {
    term = "_:b\{state.counter}"
    state.counter += 1
  }
  term
}

///|
/// 预扫走树：收集全部显式 bnode id（防新生撞号——#t0119 oracle）
fn nq_reserve_labels(value : ExpandedValue, into : Map[String, Bool]) -> Unit {
  match value {
    ExpandedValue::Node(node) => {
      match node.id {
        Some(id) => if nq_term_is_bnode(id) { into[id] = true }
        None => ()
      }
      for pair in node.properties {
        for v in pair.1 {
          nq_reserve_labels(v, into)
        }
      }
      for pair in node.reverse_props {
        for v in pair.1 {
          nq_reserve_labels(v, into)
        }
      }
      match node.graph {
        Some(items) =>
          for item in items {
            nq_reserve_labels(item, into)
          }
        None => ()
      }
      match node.included {
        Some(incs) =>
          for inc in incs {
            nq_reserve_labels(ExpandedValue::Node(inc), into)
          }
        None => ()
      }
    }
    ExpandedValue::List(items, ..) =>
      for item in items {
        nq_reserve_labels(item, into)
      }
    ExpandedValue::Value(_) => ()
  }
}

///|
/// 同 id 节点预合并（REC §6.3 同 id 节点属性并集——#tin06/#te014/#te108
/// oracle）：**图作用域键**（graph_key|id）——默认图/各具名图分别合并（跨图
/// 不并，#t0027 oracle：Paris#this 两图各发其属性）。首见对象**原地并集**
/// （types/properties/reverse 拼接、graph/included 拼接）；重复对象留树中由
/// emit-once 跳过（其贡献已并入首见）。匿名图节点（无 id 的图载体）按出现
/// 序唯一化，互不合并。
priv struct MergeCtx {
  mut anon : Int
  seen : Map[String, ExpandedNode]
}

///|
fn nq_merge_same_id(
  value : ExpandedValue,
  ctx : MergeCtx,
  graph_key : String,
) -> Result[Unit, JsonLdError] {
  match value {
    ExpandedValue::Node(node) => {
      let self_key : String? = match node.id {
        Some(id) =>
          if id == EXPLICIT_NULL_ID {
            None
          } else if nq_term_is_bnode(id) || is_valid_absolute_iri(id) {
            Some(graph_key + "|" + id)
          } else {
            None
          }
        None => None
      }
      match self_key {
        Some(key) =>
          match ctx.seen.get(key) {
            Some(first) => {
              // @index 冲突（REC Generate Node Map 合并面——#te001 oracle：
              // 同 id 双 @index 不等 = colliding indexes 错；缺席侧采纳）
              match (first.index, node.index) {
                (Some(a), Some(b)) =>
                  if a != b {
                    return Err(JsonLdError::InvalidValue("colliding indexes"))
                  }
                (None, Some(b)) => first.index = Some(b)
                _ => ()
              }
              // 原地并集进首见对象
              for t in node.types {
                first.types.push(t)
              }
              for p in node.properties {
                first.properties.push(p)
              }
              for p in node.reverse_props {
                first.reverse_props.push(p)
              }
              match node.graph {
                Some(items) =>
                  match first.graph {
                    Some(first_items) =>
                      for it in items {
                        first_items.push(it)
                      }
                    None => first.graph = Some(items)
                  }
                None => ()
              }
              match node.included {
                Some(incs) =>
                  match first.included {
                    Some(first_incs) =>
                      for inc in incs {
                        first_incs.push(inc)
                      }
                    None => first.included = Some(incs)
                  }
                None => ()
              }
            }
            None => ctx.seen[key] = node
          }
        None => ()
      }
      // 子树续走：图内容子树键 = 本节点词面（具名图作用域）；其余继承
      for pair in node.properties {
        for v in pair.1 {
          match nq_merge_same_id(v, ctx, graph_key) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
        }
      }
      for pair in node.reverse_props {
        for v in pair.1 {
          match nq_merge_same_id(v, ctx, graph_key) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
        }
      }
      match node.graph {
        Some(items) => {
          let inner_key = match self_key {
            Some(k) => k
            None => graph_key + "|anon\{ctx.anon}"
          }
          if self_key is None {
            ctx.anon += 1
          }
          for it in items {
            match nq_merge_same_id(it, ctx, inner_key) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
        }
        None => ()
      }
      match node.included {
        Some(incs) =>
          for inc in incs {
            match nq_merge_same_id(ExpandedValue::Node(inc), ctx, graph_key) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
        None => ()
      }
      Ok(())
    }
    ExpandedValue::List(items, ..) => {
      for it in items {
        match nq_merge_same_id(it, ctx, graph_key) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
      Ok(())
    }
    ExpandedValue::Value(_) => Ok(())
  }
}

///|
/// 节点主体词面（REC §6.3）：无 id / @id 被忽略哨兵（EXPLICIT_NULL_ID）⇒
/// 新生 bnode 并**回写 node.id**（emit-once 键 = 主体词面）；`_:` bnode 保留；
/// 相对 id ⇒ None（该节点整体不产出）。
fn nq_node_subject(state : ToRdfState, node : ExpandedNode) -> String? {
  match node.id {
    None => {
      let term = nq_fresh_bnode(state)
      node.id = Some(term)
      Some(term)
    }
    Some(id) =>
      if id == EXPLICIT_NULL_ID {
        // @id 被忽略（keyword 形非关键字——REC §5.2 返回 null）⇒ toRdf 面
        // 节点整体不产出（#te122 oracle：ignoreme 引用三元组亦不发射）
        None
      } else if id.get_char(0) == Some('_') && id.get_char(1) == Some(':') {
        Some(id)
      } else if is_valid_absolute_iri(id) && nq_iri_chars_legal(id) {
        Some("<" + id + ">")
      } else {
        None
      }
  }
}

///|
/// 字面量词面（REC §6.4）：显式 datatype ⇒ `^^<IRI>`（相对 datatype ⇒ None
/// 三元组弃；xsd:string 无语言 ⇒ 简单字面量——RDF 1.1 同一性）；数值/布尔 ⇒
/// 由 raw 判形（boolean/integer/double——**典范词形 J3.2**，本批词形直出）；
/// 语言 ⇒ `@lang`（小写归一）；direction 无选项面 ⇒ 弃（J3.4 rdfDirection）。
fn nq_literal_term_of(state : ToRdfState, l : ExpandedLiteral) -> String? {
  let esc = nq_emit_escape(l.value)
  // J3.4 i18n 面（REC §6.4——spec §8.36）：值对象带方向 + rdfDirection=
  // i18n-datatype ⇒ datatype = i18n#{lang}_{dir}（语言小写化；无语言 = "_"
  // 空段——tdi09/tdi10 oracle）；值原样、无 langtag
  if l.direction is Some(_) && state.direction_mode is Some("i18n-datatype") {
    let lang_part = match l.language {
      Some(lang) => nq_lowercase(lang)
      None => ""
    }
    let dir_part = match l.direction {
      Some(d) => d
      None => ""
    }
    return Some(
      "\"" + esc + "\"^^<" + I18N_PREFIX + lang_part + "_" + dir_part + ">",
    )
  }
  match l.datatype {
    Some("@json") =>
      // J3.3（JCS——RFC 8785）：raw JSON → 规范词形 → rdf:JSON 字面量
      //（#tjs01~23 oracle；expand 侧 datatype 哨兵 "@json" 在此展开成真 IRI）
      match l.raw {
        Some(jv) =>
          Some("\"" + nq_emit_escape(nq_jcs(jv)) + "\"^^<" + RDF_JSON_IRI + ">")
        None => None
      }
    Some(dt) => {
      // raw-Number 子例（J3.2）：coercion 位数值亦典范化——xsd:double 强制
      // double 形（#t0035 oracle：1 → 1.0E0）；自定义 datatype 跟值形态
      //（#te061 oracle：1→"1"、5.1→5.1E0）
      let value_form = match l.raw {
        Some(JsonValue::Number(_)) =>
          nq_canonical_number(l.value, dt == XSD_DOUBLE).0
        _ => esc
      }
      if dt == XSD_STRING && l.language is None {
        Some("\"" + value_form + "\"")
      } else if is_valid_absolute_iri(dt) && nq_iri_chars_legal(dt) {
        Some("\"" + value_form + "\"^^<" + dt + ">")
      } else {
        None
      }
    }
    None =>
      match l.language {
        Some(lang) =>
          if nq_valid_langtag(lang) {
            Some("\"" + esc + "\"@" + nq_lowercase(lang))
          } else {
            None
          }
        None =>
          match l.raw {
            Some(JsonValue::Bool(b)) =>
              Some("\"" + "\{b}" + "\"^^<" + XSD_BOOLEAN + ">")
            Some(JsonValue::Number(_)) => {
              // 数词典范形（J3.2——REC §6.4）：值整 + |v|<1e21 ⇒ integer，
              // 否则 double；词形十进制串算术典范化（词形直出退役——
              // #t0022/#trt01 oracle：5.3→5.3E0、-0e0→0、1e21→1.0E21）
              let (form, is_double) = nq_canonical_number(l.value, false)
              let dt = if is_double { XSD_DOUBLE } else { XSD_INTEGER }
              Some("\"" + form + "\"^^<" + dt + ">")
            }
            _ => Some("\"" + esc + "\"")
          }
      }
  }
}

///|
/// JSON 数词典范形（J3.2——REC §6.4；十进制串算术，不涉浮点打印）：值整 +
/// |v| < 1e21 ⇒ integer 典范形，否则 double 典范形。forced = xsd:double
/// datatype 强制 double 形。返回（词形，double 形?）。（#t0022/#t0035/
/// #te031/#te061/#trt01 oracle：5.3→5.3E0、1→1.0E0〔forced〕、123.45→
/// 1.2345E2、-0e0→0、1e21→1.0E21、8→8）
fn nq_canonical_number(lexeme : String, forced_double : Bool) -> (String, Bool) {
  let len = lexeme.length()
  let mut i = 0
  let mut neg = false
  if i < len && lexeme.get_char(i) == Some('-') {
    neg = true
    i += 1
  }
  let digits = StringBuilder()
  let mut frac_len = 0
  let mut seen_point = false
  while i < len {
    let ch = lexeme.get_char(i)
    if ch == Some('.') {
      seen_point = true
      i += 1
    } else if ch is Some(c) && c >= '0' && c <= '9' {
      digits.write_char(c)
      if seen_point {
        frac_len += 1
      }
      i += 1
    } else {
      break
    }
  }
  let mut exp = 0
  if i < len &&
    (lexeme.get_char(i) == Some('e') || lexeme.get_char(i) == Some('E')) {
    i += 1
    let mut eneg = false
    if i < len &&
      (lexeme.get_char(i) == Some('+') || lexeme.get_char(i) == Some('-')) {
      eneg = lexeme.get_char(i) == Some('-')
      i += 1
    }
    let mut ev = 0
    while i < len {
      match lexeme.get_char(i) {
        Some(c) =>
          if c >= '0' && c <= '9' {
            ev = ev * 10 + (c.to_int() - '0'.to_int())
            i += 1
          } else {
            break
          }
        None => break
      }
    }
    exp = if eneg { -ev } else { ev }
  }
  // 有效位（去前导零；全零 ⇒ 零值）
  let mut sig = digits.to_string()
  if sig is "" {
    sig = "0"
  }
  let mut head = 0
  while head < sig.length() - 1 && sig.get_char(head) == Some('0') {
    head += 1
  }
  let sig = sig[head:].to_owned()
  let all_zero = sig.get_char(0) == Some('0') && sig.length() == 1
  let shift = exp - frac_len // 值 = sig × 10^shift
  // 整形臂：值整（shift ≥ 0 或 sig 尾零足够）且 |v| < 1e21（典范整数 ≤ 21 位）
  if !forced_double && !all_zero {
    let mut int_digits = ""
    let integral = if shift >= 21 {
      false // sig.length() ≥ 1 ⇒ |v| ≥ 1e21
    } else if shift >= 0 {
      let buf = StringBuilder()
      buf.write_string(sig)
      for _ in 0..<shift {
        buf.write_char('0')
      }
      int_digits = buf.to_string()
      true
    } else if sig.length() > -shift {
      let mut tail_zero = true
      for j in (sig.length() + shift)..<sig.length() {
        if sig.get_char(j) != Some('0') {
          tail_zero = false
          break
        }
      }
      if tail_zero {
        int_digits = sig[:sig.length() + shift].to_owned()
      }
      tail_zero
    } else {
      false
    }
    if integral {
      let mut h = 0
      while h < int_digits.length() - 1 && int_digits.get_char(h) == Some('0') {
        h += 1
      }
      let canonical = int_digits[h:].to_owned()
      if canonical.length() <= 21 {
        let signed = if neg && !(canonical is "0") {
          "-" + canonical
        } else {
          canonical
        }
        return (signed, false)
      }
    }
  }
  // 零值：forced ⇒ 0.0E0（double 形），否则 ⇒ "0"（integer 形——trt01 -0e0
  // oracle 同路）
  if all_zero {
    let form = if forced_double { "0.0E0" } else { "0" }
    return (form, forced_double)
  }
  let mut mant = sig
  while mant.length() > 1 && mant.get_char(mant.length() - 1) == Some('0') {
    mant = mant[:mant.length() - 1].to_owned()
  }
  let k = shift + sig.length() - 1
  let mant_head = mant[0:1].to_owned()
  let mant_tail = if mant.length() > 1 { mant[1:].to_owned() } else { "0" }
  let sign_str = if neg { "-" } else { "" }
  ("\{sign_str}\{mant_head}.\{mant_tail}E\{k}", true)
}

///|
/// 语言标签良构校验（RFC 3066 形——REC §6.4）：段 '-' 分隔、首段全 ALPHA
/// （1..8）、余段字母数字（1..8）；非法 ⇒ 三元组弃（#twf05 oracle："a b" →
/// 空 dataset）
fn nq_valid_langtag(tag : String) -> Bool {
  let mut seg_len = 0
  let mut seg_index = 0
  for ch in tag {
    if ch == '-' {
      if seg_len == 0 || seg_len > 8 {
        return false
      }
      seg_index += 1
      seg_len = 0
    } else {
      let is_alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      let is_digit = ch >= '0' && ch <= '9'
      let ok = if seg_index == 0 { is_alpha } else { is_alpha || is_digit }
      if !ok {
        return false
      }
      seg_len += 1
      if seg_len > 8 {
        return false
      }
    }
  }
  seg_len > 0 && seg_len <= 8
}

///|
/// 词面是否 bnode（"_:" 前缀——主包侧判定件，判定器同形）
fn nq_term_is_bnode(term : String) -> Bool {
  term.get_char(0) == Some('_') && term.get_char(1) == Some(':')
}

///|
/// 语言标签小写归一（RDF 语言标签大小写不敏感——README 判定注记；判定器
/// parse_nquads 同步归一，双端一致）
fn nq_lowercase(tag : String) -> String {
  let out = StringBuilder()
  for ch in tag {
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 32).to_char().unwrap())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// 十六进制位（JCS 转义 <0x20 用——入参受控 0..15）
fn nq_hex_char(d : Int) -> Char {
  (if d < 10 { '0'.to_int() + d } else { 'a'.to_int() + d - 10 })
  .to_char()
  .unwrap()
}

///|
/// JCS 字符串转义（RFC 8785 §3.2.2.2）：短转义 \" \\ \b \t \n \f \r +
/// 其余 <0x20 用 \u00xx 小写十六进制；余字面 UTF-8 直通。
fn nq_jcs_escape(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\u{8}' => out.write_string("\\b")
      '\t' => out.write_string("\\t")
      '\n' => out.write_string("\\n")
      '\u{c}' => out.write_string("\\f")
      '\r' => out.write_string("\\r")
      _ =>
        if ch.to_int() < 0x20 {
          let v = ch.to_int()
          out.write_string("\\u00")
          out.write_char(nq_hex_char(v / 16))
          out.write_char(nq_hex_char(v % 16))
        } else {
          out.write_char(ch)
        }
    }
  }
  out.to_string()
}

///|
/// JCS 数组（逗号连接，无空格）
fn nq_jcs_array(items : Array[JsonValue]) -> String {
  let parts = StringBuilder()
  parts.write_string("[")
  for i, item in items {
    if i > 0 {
      parts.write_string(",")
    }
    parts.write_string(nq_jcs(item))
  }
  parts.write_string("]")
  parts.to_string()
}

///|
/// JCS 键序比较器（Unicode 码点序——#tjs13 oracle：U+F8DF < U+1F602；
/// String::compare 为长度优先假序，不可用——tjs09 实证 sin/peach 逆序）
fn nq_key_compare(a : String, b : String) -> Int {
  let ca : Array[Char] = []
  for ch in a {
    ca.push(ch)
  }
  let cb : Array[Char] = []
  for ch in b {
    cb.push(ch)
  }
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  for i in 0..<n {
    let va = ca[i].to_int()
    let vb = cb[i].to_int()
    if va != vb {
      return va - vb
    }
  }
  ca.length() - cb.length()
}

///|
/// JCS 对象（键序 = nq_key_compare——码点序）
fn nq_jcs_object(pairs : Array[(String, JsonValue)]) -> String {
  let sorted = pairs.map(fn(pair) { (pair.0, pair.1) })
  sorted.sort_by(fn(a, b) { nq_key_compare(a.0, b.0) })
  let parts = StringBuilder()
  parts.write_string("{")
  for i, pair in sorted {
    if i > 0 {
      parts.write_string(",")
    }
    parts.write_string("\"")
    parts.write_string(nq_jcs_escape(pair.0))
    parts.write_string("\":")
    parts.write_string(nq_jcs(pair.1))
  }
  parts.write_string("}")
  parts.to_string()
}

///|
/// JCS 规范序列化（RFC 8785；J3.3——#tjs01~23 oracle）：数值词形 =
/// ECMAScript Number::toString——MoonBit Double 显示即该形（探针实证：
/// "1e+30"/"0.002"/"1e-7"/负零 → "0"）。
fn nq_jcs(value : JsonValue) -> String {
  match value {
    JsonValue::Null => "null"
    JsonValue::Bool(b) => if b { "true" } else { "false" }
    JsonValue::Number(nv) => "\{nv}"
    JsonValue::String(sv) => "\"" + nq_jcs_escape(sv) + "\""
    JsonValue::Array(items) => nq_jcs_array(items)
    JsonValue::Object(pairs) => nq_jcs_object(pairs)
  }
}

///|
/// 带方向值对象的 compound-literal 面（REC §6.4——spec §8.36）：对象换新
/// bnode + rdf:value（**恒简单字面量**，语言不进 value——tdi12 oracle）+
/// rdf:language（小写）/ rdf:direction；无方向或非 compound 模式 ⇒ 常规
/// 字面量词面。
fn nq_directional_literal_term(
  state : ToRdfState,
  l : ExpandedLiteral,
  graph : String?,
) -> String? {
  if l.direction is Some(_) && state.direction_mode is Some("compound-literal") {
    let b = nq_fresh_bnode(state)
    nq_emit(
      state,
      b,
      RDF_VALUE_IRI,
      "\"" + nq_emit_escape(l.value) + "\"",
      graph,
    )
    match l.language {
      Some(lang) =>
        nq_emit(
          state,
          b,
          RDF_LANGUAGE_IRI,
          "\"" + nq_lowercase(lang) + "\"",
          graph,
        )
      None => ()
    }
    match l.direction {
      Some(d) =>
        nq_emit(
          state,
          b,
          RDF_DIRECTION_IRI,
          "\"" + nq_emit_escape(d) + "\"",
          graph,
        )
      None => ()
    }
    Some(b)
  } else {
    nq_literal_term_of(state, l)
  }
}

///|
/// 值 → 对象词面（节点 = 主体词面 + 递归；字面量；@list = 链头）
fn nq_value_term(
  state : ToRdfState,
  value : ExpandedValue,
  graph : String?,
) -> String? {
  match value {
    ExpandedValue::Node(child) =>
      match nq_node_subject(state, child) {
        Some(term) => {
          nq_node_to_rdf(state, child, graph)
          Some(term)
        }
        None => None
      }
    ExpandedValue::Value(l) => nq_directional_literal_term(state, l, graph)
    ExpandedValue::List(items, ..) => Some(nq_list_to_rdf(state, items, graph))
  }
}

///|
/// @list → rdf:first/rdf:rest 链（空 ⇒ rdf:nil；嵌套 list 递归成子链）
fn nq_list_to_rdf(
  state : ToRdfState,
  items : Array[ExpandedValue],
  graph : String?,
) -> String {
  if items.length() == 0 {
    return RDF_NIL_IRI
  }
  let nodes : Array[String] = []
  for _item in items {
    let b = "_:b\{state.counter}"
    state.counter += 1
    nodes.push(b)
  }
  for i, item in items {
    let next = if i + 1 < items.length() { nodes[i + 1] } else { RDF_NIL_IRI }
    match nq_value_term(state, item, graph) {
      Some(obj) => nq_emit(state, nodes[i], RDF_FIRST_IRI, obj, graph)
      None => ()
    }
    nq_emit(state, nodes[i], RDF_REST_IRI, next, graph)
  }
  nodes[0]
}

///|
/// 三元组发射（图位可空 = 默认图）
fn nq_emit(
  state : ToRdfState,
  subject : String,
  predicate : String,
  object : String,
  graph : String?,
) -> Unit {
  state.quads.push({ subject, predicate, object, graph, })
}

///|
/// 节点对象 → 四元组（REC §6.3）：emit-once（主体词面为键——bnode 回写后
/// 引用共享即去重）；types ⇒ rdf:type；属性值三分（节点/值对象/list）；
/// reverse ⇒ 反向三元组；节点位 @graph ⇒ 具名图（图名 = 本节点主体）；
/// included ⇒ 同图续展开。
fn nq_node_to_rdf(
  state : ToRdfState,
  node : ExpandedNode,
  graph : String?,
) -> Unit {
  let subject = match nq_node_subject(state, node) {
    Some(s) => s
    None => return
  }
  // emit-once 键含图位（#t0027/#te108 oracle：同节点对象在两图各发一次属性）
  let emit_key = match graph {
    Some(g) => "\{g}|\{subject}"
    None => subject
  }
  if state.emitted.contains(emit_key) {
    return
  }
  state.emitted[emit_key] = true
  for t in node.types {
    // bnode 标签型 @type（@type map 的 "_:bar" 条目——#tm003/#tm004 oracle）
    // 保留词面作 bnode 主体；其余须绝对 IRI
    if nq_term_is_bnode(t) {
      nq_emit(state, subject, RDF_TYPE_IRI, t, graph)
    } else {
      match nq_iri_term(t) {
        Some(ti) => nq_emit(state, subject, RDF_TYPE_IRI, ti, graph)
        None => ()
      }
    }
  }
  for pair in node.properties {
    let p = match nq_iri_term(pair.0) {
      Some(p) => p
      None =>
        // J3.4 generalized 面：谓词位 bnode 放行（#t0118/#te075 oracle）
        if state.generalized && nq_term_is_bnode(pair.0) {
          pair.0
        } else {
          continue
        }
    }
    for v in pair.1 {
      match nq_value_term(state, v, graph) {
        Some(obj) => nq_emit(state, subject, p, obj, graph)
        None => ()
      }
    }
  }
  // reverse ⇒ 反向三元组（值主体作 subject——@reverse 语义）
  for pair in node.reverse_props {
    let p = match nq_iri_term(pair.0) {
      Some(p) => p
      None =>
        // J3.4 generalized 面：谓词位 bnode（reverse 同权）
        if state.generalized && nq_term_is_bnode(pair.0) {
          pair.0
        } else {
          continue
        }
    }
    for v in pair.1 {
      match v {
        ExpandedValue::Node(child) =>
          match nq_node_subject(state, child) {
            Some(ct) => {
              nq_emit(state, ct, p, subject, graph)
              nq_node_to_rdf(state, child, graph)
            }
            None => ()
          }
        _ => ()
      }
    }
  }
  // 节点位 @graph ⇒ 具名图（图名 = 本节点主体；子节点递归入该图）
  match node.graph {
    Some(items) =>
      for item in items {
        match item {
          ExpandedValue::Node(child) =>
            nq_node_to_rdf(state, child, Some(subject))
          _ => ()
        }
      }
    None => ()
  }
  // included ⇒ 同图续展开（#tin03 族——included 是完整节点对象）
  match node.included {
    Some(incs) =>
      for inc in incs {
        nq_node_to_rdf(state, inc, graph)
      }
    None => ()
  }
}

///|
/// toRDF 落码（J3.1——REC §6 对应物；批边界见 spec §8）：展开形 → 四元组。
/// **批内**：串/语言/显式 datatype/bnode（含回写 emit-once）/rdf:type/
/// @list 链/具名图 + 默认图/反向。**后续批**：数值典范形（J3.2——raw 词形
/// 直出）、@json→rdf:JSON+JCS（J3.3）、rdfDirection（J3.4，本批 direction 弃）。
impl ToRdfProcessor for StandardExpander with fn node_to_quads(
  _self,
  expanded : Array[ExpandedValue],
  options : JsonLdOptions,
) -> Result[Array[JsonLdQuad], JsonLdError] {
  let reserved : Map[String, Bool] = Map([])
  let state : ToRdfState = {
    counter: 0,
    emitted: Map([]),
    quads: [],
    reserved,
    direction_mode: options.rdf_direction,
    generalized: options.produce_generalized_rdf,
  }
  // bnode 标签预扫保留（#t0119 oracle：输入明写 "_:b0" 与新生 "_:b0" 撞号
  // ⇒ 同体合并假自指；新生序号跳过全部在册标签）
  let reserved : Map[String, Bool] = Map([])
  for value in expanded {
    nq_reserve_labels(value, reserved)
  }
  state.reserved = reserved
  // 同 id 节点预合并（图作用域——F2；@index 冲突同点检出）
  let merge_ctx : MergeCtx = { anon: 0, seen: Map([]), }
  for value in expanded {
    match nq_merge_same_id(value, merge_ctx, "") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  for value in expanded {
    match value {
      ExpandedValue::Node(node) => nq_node_to_rdf(state, node, None)
      _ => ()
    }
  }
  // RDF 集合语义：重复三元组塌缩（#ttn02 oracle——同型 bool 值对象 ×2 → ×1）
  let seen : Map[String, Bool] = Map([])
  let out : Array[JsonLdQuad] = []
  for q in state.quads {
    let key = match q.graph {
      Some(g) => "\{q.subject} \{q.predicate} \{q.object} \{g}"
      None => "\{q.subject} \{q.predicate} \{q.object}"
    }
    if !seen.contains(key) {
      seen[key] = true
      out.push(q)
    }
  }
  Ok(out)
}
