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
/// toRDF 落码状态（J3.1——REC §6 对应物）：bnode 序号 / emit-once 账 / 产物
priv struct ToRdfState {
  mut counter : Int
  emitted : Map[String, Bool]
  quads : Array[JsonLdQuad]
  mut reserved : Map[String, Bool]
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
    ExpandedValue::List(items) =>
      for item in items {
        nq_reserve_labels(item, into)
      }
    ExpandedValue::Value(_) => ()
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
fn nq_literal_term_of(l : ExpandedLiteral) -> String? {
  let esc = nq_emit_escape(l.value)
  match l.datatype {
    Some("@json") => None // J3.3（JCS→rdf:JSON）——本批不产出
    Some(dt) =>
      if dt == XSD_STRING && l.language is None {
        Some("\"" + esc + "\"")
      } else if is_valid_absolute_iri(dt) && nq_iri_chars_legal(dt) {
        Some("\"" + esc + "\"^^<" + dt + ">")
      } else {
        None
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
              // 数判形（J3.2 典范化前——词形直出；小数/指数形 → double）
              let v = l.value
              let is_double = v.contains(".") ||
                v.contains("e") ||
                v.contains("E")
              if is_double {
                Some("\"" + v + "\"^^<" + XSD_DOUBLE + ">")
              } else {
                Some("\"" + v + "\"^^<" + XSD_INTEGER + ">")
              }
            }
            _ => Some("\"" + esc + "\"")
          }
      }
  }
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
    ExpandedValue::Value(l) => nq_literal_term_of(l)
    ExpandedValue::List(items) => Some(nq_list_to_rdf(state, items, graph))
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
      None => continue
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
      None => continue
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
  _options : JsonLdOptions,
) -> Result[Array[JsonLdQuad], JsonLdError] {
  let reserved : Map[String, Bool] = Map([])
  let state : ToRdfState = {
    counter: 0,
    emitted: Map([]),
    quads: [],
    reserved,
  }
  // bnode 标签预扫保留（#t0119 oracle：输入明写 "_:b0" 与新生 "_:b0" 撞号
  // ⇒ 同体合并假自指；新生序号跳过全部在册标签）
  let reserved : Map[String, Bool] = Map([])
  for value in expanded {
    nq_reserve_labels(value, reserved)
  }
  state.reserved = reserved
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
