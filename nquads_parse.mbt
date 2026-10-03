///|
/// fromRDF 解析面（役57——spec §8.130 钉一裁 a：判定器迷你解析器派生生产
/// 件，单包自足+同源互证）。结构化 term 输出（判定器为串形比对面）；
/// 行式解析（套件 54 文件一行一句实证；跨行语句超面挂账）。

///|
/// N-Quads 结构化 term：IRI（不含尖括号）/ bnode（不含 _: 前缀）/
/// literal（值 + datatype IRI + langtag）
priv enum NqTerm {
  NqIriTerm(String)
  NqBnodeTerm(String)
  NqLitTerm(String, String?, String?)
}

///|
priv struct NqQuad {
  subject : NqTerm
  predicate : NqTerm
  object : NqTerm
  graph : NqTerm?
}

///|
/// 词面状态机模式（判定器同谱——NqMode 派生）
priv enum Nq2Mode {
  Nq2Between
  Nq2Iri
  Nq2IriEscape
  Nq2IriHex
  Nq2BnodeHead
  Nq2Bnode
  Nq2Literal
  Nq2LitEscape
  Nq2LitHex
  Nq2LitSuffix
  Nq2Lang
  Nq2Caret1
  Nq2DtIri
  Nq2DtIriEscape
  Nq2DtIriHex
  Nq2AfterLit
  Nq2Done
}

///|
fn nq2_hex_digit(ch : Char) -> Int? {
  let code = ch.to_int()
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 97 && code <= 102 {
    Some(code - 87)
  } else if code >= 65 && code <= 70 {
    Some(code - 55)
  } else {
    None
  }
}

///|
/// 行级空白/注释判定（空行、纯空白、`#` 注释行）
fn nq2_line_blank(line : String) -> Bool {
  for ch in line {
    if !(ch == ' ' || ch == '\t' || ch == '\r') {
      return ch == '#'
    }
  }
  true
}

///|
fn nq2_literal_term(value : String, suffix : String) -> NqTerm {
  if suffix != "" {
    if suffix[0] == 64 {
      // '@' 开头 = langtag（@ 符为词面标记不进值——t0001 "English"@en）
      NqLitTerm(value, None, Some(suffix[1:].to_owned()))
    } else if suffix.length() > 2 &&
      suffix[0] == 94 &&
      suffix[1] == 94 &&
      suffix[2] == 60 {
      // ^^<iri> → 剥 ^^< > 存 IRI
      NqLitTerm(value, Some(suffix[3:suffix.length() - 1].to_owned()), None)
    } else {
      NqLitTerm(value, Some(suffix), None)
    }
  } else {
    NqLitTerm(value, None, None)
  }
}

///|
/// 单句解析（行式；3-4 term；'.' 终止符）。错误面 = Err 文本（与判定器
/// 同谱字面族）
fn nq2_parse_statement(line : String) -> Result[NqQuad?, String] {
  if nq2_line_blank(line) {
    return Ok(None)
  }
  let terms : Array[NqTerm] = []
  let mut mode : Nq2Mode = Nq2Between
  let buf = StringBuilder()
  let lit = StringBuilder()
  let suffix = StringBuilder()
  let mut hex_left = 0
  let mut hex_acc = 0
  for ch in line {
    match mode {
      Nq2Between =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          ()
        } else if ch == '.' {
          mode = Nq2Done
          break
        } else if ch == '<' {
          buf.reset()
          mode = Nq2Iri
        } else if ch == '_' {
          buf.reset()
          mode = Nq2BnodeHead
        } else if ch == '"' {
          lit.reset()
          suffix.reset()
          mode = Nq2Literal
        } else {
          return Err("unexpected char at term start: \{ch}")
        }
      Nq2Iri =>
        if ch == '>' {
          terms.push(NqIriTerm(buf.to_string()))
          mode = Nq2Between
        } else if ch == '\\' {
          mode = Nq2IriEscape
        } else {
          buf.write_char(ch)
        }
      Nq2IriEscape =>
        // IRIREF 只容 UCHAR（u4/U8；短转义属字面量文法，IRI 内报错）
        match ch {
          'u' => {
            hex_left = 4
            hex_acc = 0
            mode = Nq2IriHex
          }
          'U' => {
            hex_left = 8
            hex_acc = 0
            mode = Nq2IriHex
          }
          _ => return Err("invalid IRI escape: \{ch}")
        }
      Nq2IriHex =>
        // 十六进制收满写 buf（IRI 词面），与字面量 Nq2LitHex 同谱
        match nq2_hex_digit(ch) {
          Some(d) => {
            hex_acc = hex_acc * 16 + d
            hex_left -= 1
            if hex_left == 0 {
              match hex_acc.to_char() {
                Some(c) => buf.write_char(c)
                None => return Err("invalid IRI \\u codepoint")
              }
              mode = Nq2Iri
            }
          }
          None => return Err("bad hex digit in IRI \\u escape")
        }
      Nq2BnodeHead =>
        // '_:' 的 ':' 剥离（标签裸存——渲染位统一 "_:" 前缀）
        if ch == ':' {
          mode = Nq2Bnode
        } else {
          return Err("expected ':' after '_'")
        }
      Nq2Bnode =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(NqBnodeTerm(buf.to_string()))
          mode = Nq2Between
        } else if ch == '.' {
          terms.push(NqBnodeTerm(buf.to_string()))
          mode = Nq2Done
          break
        } else {
          buf.write_char(ch)
        }
      Nq2Literal =>
        if ch == '\\' {
          mode = Nq2LitEscape
        } else if ch == '"' {
          mode = Nq2LitSuffix
        } else {
          lit.write_char(ch)
        }
      Nq2LitEscape =>
        match ch {
          'u' => {
            hex_left = 4
            hex_acc = 0
            mode = Nq2LitHex
          }
          'U' => {
            hex_left = 8
            hex_acc = 0
            mode = Nq2LitHex
          }
          't' => {
            lit.write_char('\t')
            mode = Nq2Literal
          }
          'b' => {
            lit.write_char('\u{8}')
            mode = Nq2Literal
          }
          'n' => {
            lit.write_char('\n')
            mode = Nq2Literal
          }
          'r' => {
            lit.write_char('\r')
            mode = Nq2Literal
          }
          'f' => {
            lit.write_char('\u{c}')
            mode = Nq2Literal
          }
          '"' => {
            lit.write_char('"')
            mode = Nq2Literal
          }
          '\'' => {
            lit.write_char('\'')
            mode = Nq2Literal
          }
          '\\' => {
            lit.write_char('\\')
            mode = Nq2Literal
          }
          _ => return Err("unknown literal escape: \{ch}")
        }
      Nq2LitHex =>
        match nq2_hex_digit(ch) {
          Some(d) => {
            hex_acc = hex_acc * 16 + d
            hex_left -= 1
            if hex_left == 0 {
              match hex_acc.to_char() {
                Some(c) => lit.write_char(c)
                None => return Err("invalid \\u codepoint")
              }
              mode = Nq2Literal
            }
          }
          None => return Err("bad hex digit in \\u escape")
        }
      Nq2LitSuffix =>
        if ch == '@' {
          suffix.write_char('@')
          mode = Nq2Lang
        } else if ch == '^' {
          mode = Nq2Caret1
        } else if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(nq2_literal_term(lit.to_string(), suffix.to_string()))
          mode = Nq2Between
        } else if ch == '.' {
          terms.push(nq2_literal_term(lit.to_string(), suffix.to_string()))
          mode = Nq2Done
          break
        } else {
          return Err("unexpected char after literal: \{ch}")
        }
      Nq2Lang =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          terms.push(nq2_literal_term(lit.to_string(), suffix.to_string()))
          mode = Nq2Between
        } else if ch == '.' {
          terms.push(nq2_literal_term(lit.to_string(), suffix.to_string()))
          mode = Nq2Done
          break
        } else {
          suffix.write_char(ch)
        }
      Nq2Caret1 =>
        if ch == '^' {
          suffix.write_string("^^")
          mode = Nq2DtIri
        } else {
          return Err("expected second '^' of datatype")
        }
      Nq2DtIri =>
        if ch == '>' {
          suffix.write_string(">")
          terms.push(nq2_literal_term(lit.to_string(), suffix.to_string()))
          mode = Nq2AfterLit
        } else if ch == '\\' {
          mode = Nq2DtIriEscape
        } else {
          suffix.write_char(ch)
        }
      Nq2DtIriEscape =>
        // datatype IRI 同 IRIREF 文法：只容 UCHAR
        match ch {
          'u' => {
            hex_left = 4
            hex_acc = 0
            mode = Nq2DtIriHex
          }
          'U' => {
            hex_left = 8
            hex_acc = 0
            mode = Nq2DtIriHex
          }
          _ => return Err("invalid datatype IRI escape: \{ch}")
        }
      Nq2DtIriHex =>
        // 十六进制收满写 suffix；终结 '>' 恒为末写字符，位剥离不受扰
        match nq2_hex_digit(ch) {
          Some(d) => {
            hex_acc = hex_acc * 16 + d
            hex_left -= 1
            if hex_left == 0 {
              match hex_acc.to_char() {
                Some(c) => suffix.write_char(c)
                None => return Err("invalid datatype IRI \\u codepoint")
              }
              mode = Nq2DtIri
            }
          }
          None => return Err("bad hex digit in datatype IRI \\u escape")
        }
      Nq2AfterLit =>
        if ch == ' ' || ch == '\t' || ch == '\r' {
          mode = Nq2Between
        } else if ch == '.' {
          mode = Nq2Done
          break
        } else {
          return Err("unexpected char after literal term")
        }
      Nq2Done => ()
    }
  }
  if mode is Nq2Done {
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
/// N-Quads 文本 → 结构化四元组集（行式；末行无换行兼容）
fn nq2_parse(text : String) -> Result[Array[NqQuad], String] {
  let quads : Array[NqQuad] = []
  let lines = nq2_split_lines(text)
  for line in lines {
    match nq2_parse_statement(line) {
      Ok(Some(quad)) => quads.push(quad)
      Ok(None) => ()
      Err(m) => return Err(m)
    }
  }
  Ok(quads)
}

///|
/// 行切分（\n；\r 归语句内空白判定面；末行无换行兼容）
fn nq2_split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let total = text.length()
  let mut start = 0
  let mut i = 0
  while i < total {
    if text[i] == 10 {
      lines.push(text[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  if start < total {
    lines.push(text[start:].to_owned())
  }
  lines
}
