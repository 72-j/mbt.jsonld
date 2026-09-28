///|
/// toRDF 判定器（J3.0——spec §8.3/§8.4）：expected `.nq` 迷你解析 + 数据集
/// 同构（bnode 双射）。受限子集（spec §8.3 勘定实测）：行式语句、终结符 ` .`、
/// 词面 <IRI> / `_:label`（标签无点）/ `"literal"[@lang][^^<dt>]`；转义面
/// `\" \\ \' \t \b \n \r \f \uXXXX`（\UXXXXXXXX 同径）；IRI 内转义不受理
/// （套件无此面，J3.1 发射侧同口径）。禁对子仓 gen_nquads 建依赖
/// （独立布局红线——spec §8.3）。

///|
/// N-Quads 十六进制位解码（0..15；越面 → None）
fn nq_hex_digit(ch : Char) -> Int? {
  match ch {
    '0'..='9' => Some(ch.to_int() - '0'.to_int())
    'a'..='f' => Some(ch.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(ch.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// 十六进制串 → 码点（4/8 位；含非法位 → None）
fn nq_hex_to_codepoint(hex : String) -> Int? {
  let mut value = 0
  for ch in hex {
    match nq_hex_digit(ch) {
      Some(d) => value = value * 16 + d
      None => return None
    }
  }
  Some(value)
}

///|
/// 码点 → 小写十六进制位（canonical \u 转义用）
fn nq_hex_char(d : Int) -> Char {
  // 入参受控 0..15（调用面保证）——None 不可达
  (if d < 10 { '0'.to_int() + d } else { 'a'.to_int() + d - 10 })
  .to_char()
  .unwrap()
}

///|
/// N-Quads 转义解码（词面原文 → 值）。宽容兜底（未知转义原样透传）——套件
/// expected 为参考实现产物、词面良构，兜底不触发；判定器对套件输入恒一致。
fn nq_unescape(raw : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  let n = raw.length()
  while i < n {
    match raw.get_char(i) {
      Some('\\') =>
        match raw.get_char(i + 1) {
          Some('u') =>
            match nq_hex_to_codepoint(raw[i + 2:i + 6].to_owned()) {
              Some(cp) =>
                match cp.to_char() {
                  Some(c) => {
                    out.write_char(c)
                    i = i + 6
                  }
                  None => {
                    out.write_char('\\')
                    i = i + 1
                  }
                }
              None => {
                out.write_char('\\')
                i = i + 1
              }
            }
          Some('U') =>
            match nq_hex_to_codepoint(raw[i + 2:i + 10].to_owned()) {
              Some(cp) =>
                match cp.to_char() {
                  Some(c) => {
                    out.write_char(c)
                    i = i + 10
                  }
                  None => {
                    out.write_char('\\')
                    i = i + 1
                  }
                }
              None => {
                out.write_char('\\')
                i = i + 1
              }
            }
          Some('t') => {
            out.write_char('\t')
            i = i + 2
          }
          Some('b') => {
            out.write_char('\u{8}')
            i = i + 2
          }
          Some('n') => {
            out.write_char('\n')
            i = i + 2
          }
          Some('r') => {
            out.write_char('\r')
            i = i + 2
          }
          Some('f') => {
            out.write_char('\u{c}')
            i = i + 2
          }
          Some('"') => {
            out.write_char('"')
            i = i + 2
          }
          Some('\'') => {
            out.write_char('\'')
            i = i + 2
          }
          Some('\\') => {
            out.write_char('\\')
            i = i + 2
          }
          _ => {
            out.write_char('\\')
            i = i + 1
          }
        }
      Some(ch) => {
        out.write_char(ch)
        i = i + 1
      }
      // 代理对中位：该字符已在起始位整写（UTF-16 codeunit 索引空间——探针实证）
      None => i = i + 1
    }
  }
  out.to_string()
}

///|
/// canonical 转义（值 → 判定器规范词面）：`\\ \" \n \r \t` + <0x20 用
/// `\u00XX` 小写十六进制。解析侧（expected）与发射侧（J3.1 toRdf 输出）同用
/// 此函数 ⇒ 词形选择（转义风格）不影响判定。
fn nq_escape(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '\\' => out.write_string("\\\\")
      '"' => out.write_string("\\\"")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
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
/// 字面量词面组装（判定器规范形：`"值"` + 后缀；值经 canonical 转义）
fn nq_literal_term(value : String, suffix : String) -> String {
  "\"" + nq_escape(value) + "\"" + suffix
}

///|
/// 词面是否 bnode（规范形下 bnode 恒以 `_:` 起；get_char 双位判定天然容忍
/// 多字节首字符）
fn nq_is_bnode(term : String) -> Bool {
  term.get_char(0) == Some('_') && term.get_char(1) == Some(':')
}

///|
/// N-Quads 词面模式（parse_nquads_statement 状态机）
enum NqMode {
  NqBetween
  NqIri
  NqBnode
  NqLiteral
  NqLitEscape
  NqLitHex
  NqLitSuffix
  NqLang
  NqCaret1
  NqDtIri
  NqAfterLit
  NqDone
}

///|
/// 行级空白/注释判定（空行、纯空白、`#` 注释行 → true）
fn nq_line_blank(line : String) -> Bool {
  for ch in line {
    if !(ch == ' ' || ch == '\t' || ch == '\r') {
      return ch == '#'
    }
  }
  true
}

///|
/// 单行语句解析：空行/注释 → Ok(None)；语句 → Ok(Some(quad))；词形越面 →
/// Err。词面数须恰 3（默认图）或 4（具名图）。
fn parse_nquads_statement(line : String) -> Result[@jsonld.JsonLdQuad?, String] {
  if nq_line_blank(line) {
    return Ok(None)
  }
  let terms : Array[String] = []
  let mut mode : NqMode = NqBetween
  let buf = StringBuilder()
  let lit = StringBuilder()
  let suffix = StringBuilder()
  let mut hex_left = 0
  let mut hex_acc = 0
  for ch in line {
    match mode {
      NqBetween =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          ()
        } else if ch == '.' {
          mode = NqDone
          break
        } else if ch == '<' {
          buf.reset()
          mode = NqIri
        } else if ch == '_' {
          buf.reset()
          buf.write_char('_')
          mode = NqBnode
        } else if ch == '"' {
          lit.reset()
          suffix.reset()
          mode = NqLiteral
        } else {
          return Err("unexpected char at term start: \{ch}")
        }
      NqIri =>
        if ch == '>' {
          terms.push("<" + buf.to_string() + ">")
          mode = NqBetween
        } else {
          buf.write_char(ch)
        }
      NqBnode =>
        // '_' 已入 buf（前缀位）；标签字符含 ':' 直通（套件标签无点——spec §8.3）
        if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(buf.to_string())
          mode = NqBetween
        } else if ch == '.' {
          terms.push(buf.to_string())
          mode = NqDone
          break
        } else {
          buf.write_char(ch)
        }
      NqLiteral =>
        if ch == '\\' {
          mode = NqLitEscape
        } else if ch == '"' {
          mode = NqLitSuffix
        } else {
          lit.write_char(ch)
        }
      NqLitEscape =>
        match ch {
          'u' => {
            hex_left = 4
            hex_acc = 0
            mode = NqLitHex
          }
          'U' => {
            hex_left = 8
            hex_acc = 0
            mode = NqLitHex
          }
          't' => {
            lit.write_char('\t')
            mode = NqLiteral
          }
          'b' => {
            lit.write_char('\u{8}')
            mode = NqLiteral
          }
          'n' => {
            lit.write_char('\n')
            mode = NqLiteral
          }
          'r' => {
            lit.write_char('\r')
            mode = NqLiteral
          }
          'f' => {
            lit.write_char('\u{c}')
            mode = NqLiteral
          }
          '"' => {
            lit.write_char('"')
            mode = NqLiteral
          }
          '\'' => {
            lit.write_char('\'')
            mode = NqLiteral
          }
          '\\' => {
            lit.write_char('\\')
            mode = NqLiteral
          }
          _ => return Err("unknown literal escape: \{ch}")
        }
      NqLitHex =>
        match nq_hex_digit(ch) {
          Some(d) => {
            hex_acc = hex_acc * 16 + d
            hex_left -= 1
            if hex_left == 0 {
              // \uXXXX 码点越面（>0x10FFFF）→ Err（套件词面良构，不触发）
              match hex_acc.to_char() {
                Some(c) => lit.write_char(c)
                None => return Err("invalid \\u codepoint")
              }
              mode = NqLiteral
            }
          }
          None => return Err("bad hex digit in \\u escape")
        }
      NqLitSuffix =>
        if ch == '@' {
          suffix.write_char('@')
          mode = NqLang
        } else if ch == '^' {
          mode = NqCaret1
        } else if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(nq_literal_term(lit.to_string(), ""))
          mode = NqBetween
        } else if ch == '.' {
          terms.push(nq_literal_term(lit.to_string(), ""))
          mode = NqDone
          break
        } else {
          return Err("unexpected char after literal: \{ch}")
        }
      NqLang =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(nq_literal_term(lit.to_string(), suffix.to_string()))
          mode = NqBetween
        } else if ch == '.' {
          terms.push(nq_literal_term(lit.to_string(), suffix.to_string()))
          mode = NqDone
          break
        } else {
          suffix.write_char(ch)
        }
      NqCaret1 =>
        if ch == '^' {
          suffix.write_string("^^")
          mode = NqDtIri
        } else {
          return Err("expected second '^' of datatype")
        }
      NqDtIri =>
        if ch == '>' {
          suffix.write_string(">")
          terms.push(nq_literal_term(lit.to_string(), suffix.to_string()))
          mode = NqAfterLit
        } else {
          suffix.write_char(ch)
        }
      NqAfterLit =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          mode = NqBetween
        } else if ch == '.' {
          mode = NqDone
          break
        } else {
          return Err("unexpected char after literal term")
        }
      NqDone => ()
    }
  }
  if mode is NqDone {
    if terms.length() == 3 {
      return Ok(
        Some({
          subject: terms[0],
          predicate: terms[1],
          object: terms[2],
          graph: None,
        }),
      )
    }
    if terms.length() == 4 {
      return Ok(
        Some({
          subject: terms[0],
          predicate: terms[1],
          object: terms[2],
          graph: Some(terms[3]),
        }),
      )
    }
    return Err("statement term count \{terms.length()} not in 3..4")
  }
  Err("unterminated statement (missing '.')")
}

///|
/// N-Quads 文本 → 四元组集（行式；末行无换行兼容——套件 13 文件实证）
fn parse_nquads(text : String) -> Result[Array[@jsonld.JsonLdQuad], String] {
  let quads : Array[@jsonld.JsonLdQuad] = []
  let mut cur = StringBuilder()
  for ch in text {
    if ch == '\n' {
      match parse_nquads_statement(cur.to_string()) {
        Ok(Some(quad)) => quads.push(quad)
        Ok(None) => ()
        Err(msg) => return Err(msg)
      }
      cur = StringBuilder()
    } else {
      cur.write_char(ch)
    }
  }
  match parse_nquads_statement(cur.to_string()) {
    Ok(Some(quad)) => quads.push(quad)
    Ok(None) => ()
    Err(msg) => return Err(msg)
  }
  Ok(quads)
}

///|
/// 四元组是否含 bnode 位（subject/predicate/object/graph——谓词位为
/// produceGeneralizedRdf 面预留，#t0118 实证 bnode 谓词）
fn nq_quad_has_bnode(q : @jsonld.JsonLdQuad) -> Bool {
  let graph_bnode = match q.graph {
    Some(g) => nq_is_bnode(g)
    None => false
  }
  nq_is_bnode(q.subject) ||
  nq_is_bnode(q.predicate) ||
  nq_is_bnode(q.object) ||
  graph_bnode
}

///|
/// 地面四元组渲染（多集相等比较用）
fn nq_quad_render(q : @jsonld.JsonLdQuad) -> String {
  match q.graph {
    Some(g) => "\{q.subject} \{q.predicate} \{q.object} \{g}"
    None => "\{q.subject} \{q.predicate} \{q.object}"
  }
}

///|
/// 收集四元组中的 bnode 标签（subject/object/graph 位）
fn nq_collect_labels(q : @jsonld.JsonLdQuad, into : Map[String, Bool]) -> Unit {
  if nq_is_bnode(q.subject) {
    into[q.subject] = true
  }
  if nq_is_bnode(q.predicate) {
    into[q.predicate] = true
  }
  if nq_is_bnode(q.object) {
    into[q.object] = true
  }
  match q.graph {
    Some(g) => if nq_is_bnode(g) { into[g] = true }
    None => ()
  }
}

///|
/// 单四元组标签绑定尝试（their vs our）：地面位严格相等；bnode 位查 map/
/// used 一致性。可绑定 ⇒ 返回新增绑定对（调用方以副本续搜）；冲突 ⇒ None。
fn nq_bind_quad(
  theirs : @jsonld.JsonLdQuad,
  ours : @jsonld.JsonLdQuad,
  map : Map[String, String],
  used : Map[String, Bool],
) -> Array[(String, String)]? {
  let bindings : Array[(String, String)] = []
  let mut ok = true
  let position_pairs : Array[(String, String)] = [
    (theirs.subject, ours.subject),
    (theirs.predicate, ours.predicate),
    (theirs.object, ours.object),
  ]
  match (theirs.graph, ours.graph) {
    (Some(gt), Some(go_graph)) => position_pairs.push((gt, go_graph))
    (None, None) => ()
    _ => ok = false
  }
  for pair in position_pairs {
    if ok {
      let t = pair.0
      let o = pair.1
      let t_bnode = nq_is_bnode(t)
      let o_bnode = nq_is_bnode(o)
      if t_bnode && o_bnode {
        match map.get(t) {
          Some(prev) => if prev != o { ok = false }
          None => {
            // 本四元组内**同源同靶**（自指 `_:b0 _:b0 _:b0`——#t0118/#te038
            // 实证）＝一致，不新增绑定；同靶异源＝冲突
            let mut bound_same = false
            let mut target_taken = used.contains(o)
            for b in bindings {
              if b.0 == t {
                if b.1 == o {
                  bound_same = true
                } else {
                  ok = false
                }
              }
              if b.1 == o {
                target_taken = true
              }
            }
            if ok && !bound_same && !target_taken {
              bindings.push((t, o))
            }
          }
        }
      } else if !t_bnode && !o_bnode {
        if t != o {
          ok = false
        }
      } else {
        ok = false
      }
    }
  }
  if ok {
    Some(bindings)
  } else {
    None
  }
}

///|
/// bnode 四元组集回溯匹配（theirs 逐条消费 × ours 候选扫描；map/used 以副本
/// 传递——数据集小额，副本代价可忽略）
fn nq_bnode_quads_match(
  theirs : Array[@jsonld.JsonLdQuad],
  ours : Array[@jsonld.JsonLdQuad],
  start : Int,
  map : Map[String, String],
  used : Map[String, Bool],
) -> Bool {
  if start == theirs.length() {
    return true
  }
  let t = theirs[start]
  for oi in 0..<ours.length() {
    match nq_bind_quad(t, ours[oi], map, used) {
      Some(bindings) => {
        let map2 : Map[String, String] = Map([])
        for k, v in map {
          map2[k] = v
        }
        let used2 : Map[String, Bool] = Map([])
        for k, v in used {
          used2[k] = v
        }
        for pair in bindings {
          map2[pair.0] = pair.1
          used2[pair.1] = true
        }
        if nq_bnode_quads_match(theirs, ours, start + 1, map2, used2) {
          return true
        }
      }
      None => ()
    }
  }
  false
}

///|
/// 数据集同构判定（README「RDF Dataset Isomorphism」移植——判定器规范形下
/// 只剩 bnode 标签自由度）：地面四元组多集严格相等 + bnode 四元组集存在
/// 标签双射。
fn datasets_isomorphic(
  a : Array[@jsonld.JsonLdQuad],
  b : Array[@jsonld.JsonLdQuad],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let ground_a : Array[String] = []
  let ground_b : Array[String] = []
  let bnode_a : Array[@jsonld.JsonLdQuad] = []
  let bnode_b : Array[@jsonld.JsonLdQuad] = []
  for q in a {
    if nq_quad_has_bnode(q) {
      bnode_a.push(q)
    } else {
      ground_a.push(nq_quad_render(q))
    }
  }
  for q in b {
    if nq_quad_has_bnode(q) {
      bnode_b.push(q)
    } else {
      ground_b.push(nq_quad_render(q))
    }
  }
  ground_a.sort_by(fn(x, y) { x.compare(y) })
  ground_b.sort_by(fn(x, y) { x.compare(y) })
  for i in 0..<ground_a.length() {
    if ground_a[i] != ground_b[i] {
      return false
    }
  }
  let labels_a : Map[String, Bool] = Map([])
  let labels_b : Map[String, Bool] = Map([])
  for q in bnode_a {
    nq_collect_labels(q, labels_a)
  }
  for q in bnode_b {
    nq_collect_labels(q, labels_b)
  }
  if labels_a.length() != labels_b.length() {
    return false
  }
  nq_bnode_quads_match(bnode_a, bnode_b, 0, Map([]), Map([]))
}

///|
test "nquads judge: escape round trip (canonical wordform)" {
  assert_eq(nq_unescape("a\\nb\"c\\\\d"), "a\nb\"c\\d")
  assert_eq(nq_escape("a\nb\"c\\d"), "a\\nb\\\"c\\\\d")
  assert_eq(nq_unescape("A\\u000fB"), "A\u{f}B")
  assert_eq(nq_escape("x\u{1}y"), "x\\u0001y")
  // 转义风格不影响判定（expected \uXXXX 形 vs 原始字符形——同一值同词面）
  assert_eq(
    nq_literal_term(nq_unescape("\\u20ac"), ""),
    nq_literal_term("€", ""),
  )
}

///|
async test "nquads judge: ground quad parse (0001)" {
  let text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf/0001-out.nq").binary(),
  )
  let quads = match parse_nquads(text) {
    Ok(qs) => qs
    Err(m) => fail(m)
  }
  assert_eq(quads.length(), 1)
  assert_eq(quads[0].subject, "<http://greggkellogg.net/foaf#me>")
  assert_eq(quads[0].predicate, "<http://xmlns.com/foaf/0.1/name>")
  assert_eq(quads[0].object, "\"Gregg Kellogg\"")
  assert_true(quads[0].graph is None)
}

///|
async test "nquads judge: named graph parse (0027)" {
  let text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf/0027-out.nq").binary(),
  )
  let quads = match parse_nquads(text) {
    Ok(qs) => qs
    Err(m) => fail(m)
  }
  let mut with_graph = 0
  let mut ground_only = 0
  for q in quads {
    match q.graph {
      Some(g) => {
        with_graph += 1
        // 该文件图名 ∈ {ParisFact1, ParisFact2}（ facts 分图实证）
        assert_true(
          g == "<http://example.org/ParisFact1>" ||
          g == "<http://example.org/ParisFact2>",
        )
      }
      None => ground_only += 1
    }
  }
  assert_true(with_graph > 0)
  assert_true(ground_only > 0)
}

///|
async test "nquads judge: bnode parse + JSON literal (0008/js01)" {
  let text0008 = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf/0008-out.nq").binary(),
  )
  let quads0008 = match parse_nquads(text0008) {
    Ok(qs) => qs
    Err(m) => fail(m)
  }
  assert_eq(quads0008.length(), 1)
  assert_eq(quads0008[0].subject, "_:b0")
  let textjs01 = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf/js01-out.nq").binary(),
  )
  let quadsjs01 = match parse_nquads(textjs01) {
    Ok(qs) => qs
    Err(m) => fail(m)
  }
  assert_eq(
    quadsjs01[0].object,
    "\"true\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON>",
  )
}

///|
/// 同构核心：换标不变 / 缺条目红 / 星形错配红（合成数据集——判定面受控）
test "nquads judge: isomorphism bijection semantics" {
  let mk = fn(
    s : String,
    p : String,
    o : String,
    g : String?,
  ) -> @jsonld.JsonLdQuad {
    { subject: s, predicate: p, object: o, graph: g, }
  }
  // 星形：两个 bnode 互指 + 各挂地面值
  let side_a : Array[@jsonld.JsonLdQuad] = [
    mk("_:a", "<p1>", "_:b", None),
    mk("_:b", "<p1>", "_:a", None),
    mk("_:a", "<p2>", "\"v1\"", None),
  ]
  // 换标（a→x, b→y）后同构
  let side_b : Array[@jsonld.JsonLdQuad] = [
    mk("_:x", "<p1>", "_:y", None),
    mk("_:y", "<p1>", "_:x", None),
    mk("_:x", "<p2>", "\"v1\"", None),
  ]
  assert_true(datasets_isomorphic(side_a, side_b))
  // 换标反置（a→y, b→x）仍同构（双射不挑方向）
  let side_c : Array[@jsonld.JsonLdQuad] = [
    mk("_:y", "<p1>", "_:x", None),
    mk("_:x", "<p1>", "_:y", None),
    mk("_:y", "<p2>", "\"v1\"", None),
  ]
  assert_true(datasets_isomorphic(side_a, side_c))
  // 结构错配（星形臂互换——1↔2 连边改写）⇒ 无双射
  let side_d : Array[@jsonld.JsonLdQuad] = [
    mk("_:x", "<p1>", "_:y", None),
    mk("_:y", "<p2>", "_:x", None),
    mk("_:x", "<p2>", "\"v1\"", None),
  ]
  assert_false(datasets_isomorphic(side_a, side_d))
  // 数目不等
  assert_false(
    datasets_isomorphic(side_a, [
      mk("_:x", "<p1>", "_:y", None),
      mk("_:y", "<p1>", "_:x", None),
    ]),
  )
}

///|
async test "nquads judge: suite files self-isomorphic" {
  let names = ["0008-out.nq", "0027-out.nq", "js13-out.nq", "0113-out.nq"]
  for name in names {
    let text = @utf8.decode(
      @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf/" + name).binary(),
    )
    let quads = match parse_nquads(text) {
      Ok(qs) => qs
      Err(m) => fail("\{name}: \{m}")
    }
    assert_true(datasets_isomorphic(quads, quads))
  }
}

///|
/// 产物四元组 → N-Quads 文本（判定器 parse_nquads 归一前的回读面——发射侧
/// 词形经同一次归一，词形选择与判定解耦）
fn render_nq(quads : Array[@jsonld.JsonLdQuad]) -> String {
  let out = StringBuilder()
  for q in quads {
    out.write_string(q.subject)
    out.write_string(" ")
    out.write_string(q.predicate)
    out.write_string(" ")
    out.write_string(q.object)
    match q.graph {
      Some(g) => {
        out.write_string(" ")
        out.write_string(g)
      }
      None => ()
    }
    out.write_string(" .\n")
  }
  out.to_string()
}
