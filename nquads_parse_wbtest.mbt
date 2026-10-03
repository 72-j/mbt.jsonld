// 役65 覆盖率热点批——nq2 解析器负例臂 + '.' 终结族白盒钉（此前仅套件
// 正路径覆盖；nq2_parse 是 from_rdf/to_rdf 判定器派生源，负例臂从未直钉）。

///|
/// wbtest 本地渲染（NqTerm 无 derive(Eq)——pattern 渲染为文本比对）
fn nq2wb_term_text(term : NqTerm) -> String {
  match term {
    NqIriTerm(iri) => "<" + iri + ">"
    NqBnodeTerm(label) => "_:" + label
    NqLitTerm(value, datatype, lang) => {
      let base = "\"" + value + "\""
      let dt = match datatype {
        Some(d) => "^^<" + d + ">"
        None => ""
      }
      let lg = match lang {
        Some(l) => "@" + l
        None => ""
      }
      base + dt + lg
    }
  }
}

///|
fn nq2wb_quad_text(line : String) -> String {
  match nq2_parse_statement(line) {
    Ok(Some(quad)) => {
      let body = nq2wb_term_text(quad.subject) +
        " " +
        nq2wb_term_text(quad.predicate) +
        " " +
        nq2wb_term_text(quad.object)
      match quad.graph {
        Some(g) => body + " " + nq2wb_term_text(g)
        None => body
      }
    }
    Ok(None) => "blank"
    Err(msg) => "ERR: " + msg
  }
}

///|
fn nq2wb_err(line : String) -> String {
  match nq2_parse_statement(line) {
    Err(msg) => msg
    _ => "no-error"
  }
}

///|
test "nq2wb: dot terminators across term families" {
  // bnode/字面量/langtag/datatype + AfterLit 空格后 '.' ——终结族逐形
  assert_eq(nq2wb_quad_text("_:a <http://e/p> _:b."), "_:a <http://e/p> _:b")
  assert_eq(
    nq2wb_quad_text("_:a <http://e/p> \"v\"."),
    "_:a <http://e/p> \"v\"",
  )
  assert_eq(
    nq2wb_quad_text("_:a <http://e/p> \"v\"@en."),
    "_:a <http://e/p> \"v\"@en",
  )
  assert_eq(
    nq2wb_quad_text("_:a <http://e/p> \"v\"^^<http://e/t>."),
    "_:a <http://e/p> \"v\"^^<http://e/t>",
  )
  assert_eq(
    nq2wb_quad_text("<http://e/s> <http://e/p> \"v\"^^<http://e/t> ."),
    "<http://e/s> <http://e/p> \"v\"^^<http://e/t>",
  )
}

///|
test "nq2wb: U8 datatype escape and named literal escapes" {
  assert_eq(
    nq2wb_quad_text("_:a <http://e/p> \"v\"^^<http://e/\\U0001F600t>."),
    "_:a <http://e/p> \"v\"^^<http://e/\u{1F600}t>",
  )
  assert_eq(
    nq2wb_quad_text("_:a <http://e/p> \"a\\tb\\nc\\\"d\\\\e\"."),
    "_:a <http://e/p> \"a\tb\nc\"d\\e\"",
  )
}

///|
test "nq2wb: negative arms each pinned" {
  // 起始字符 / IRI 转义 / ':' 缺失 / 字面量转义 / ^ 形 / AfterLit 杂字符
  assert_true(
    nq2wb_err("x <http://e/p> \"o\".").contains("unexpected char at term start"),
  )
  assert_true(
    nq2wb_err("<http://e/\\x7> <http://e/p> \"o\".").contains(
      "invalid IRI escape",
    ),
  )
  assert_true(
    nq2wb_err("_a <http://e/p> \"o\".").contains("expected ':' after '_'"),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\\q\".").contains("unknown literal escape"),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\"^x.").contains("expected second '^'"),
  )
  assert_true(
    // 空白先回 Between（报 term-start）——本臂需非空白紧贴 datatype IRI
    nq2wb_err("_:a <http://e/p> \"v\"^^<http://e/t>x.").contains(
      "unexpected char after literal term",
    ),
  )
  // \u 码点越界 / 坏 hex（IRI 位、字面量位、datatype 位三处对称）
  assert_true(
    nq2wb_err("<http://e/\\UFFFFFFFF> <http://e/p> \"o\".").contains(
      "invalid IRI \\u codepoint",
    ),
  )
  assert_true(
    nq2wb_err("<http://e/\\uZZZZ> <http://e/p> \"o\".").contains(
      "bad hex digit in IRI",
    ),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\\UFFFFFFFF\".").contains(
      "invalid \\u codepoint",
    ),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\\uZZZZ\".").contains(
      "bad hex digit in \\u escape",
    ),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\"^^<http://e/\\UFFFFFFFF>.").contains(
      "invalid datatype IRI \\u codepoint",
    ),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\"^^<http://e/\\uZZZZ>.").contains(
      "bad hex digit in datatype IRI",
    ),
  )
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\"^^<http://e/\\x7>.").contains(
      "invalid datatype IRI escape",
    ),
  )
  // 字面量后杂字符 / 项数越界 / 未终结
  assert_true(
    nq2wb_err("_:a <http://e/p> \"v\"x.").contains(
      "unexpected char after literal",
    ),
  )
  assert_true(nq2wb_err("<http://e/s> <http://e/p>.").contains("term count"))
  assert_true(
    nq2wb_err("<http://e/s> <http://e/p> <http://e/o>").contains("unterminated"),
  )
}

///|
test "nq2wb: nq2_parse propagates statement errors" {
  match nq2_parse("<http://e/s> <http://e/p> <http://e/o>.\nx junk.") {
    Err(msg) => assert_true(msg.contains("unexpected char at term start"))
    Ok(_) => {
      println("bad line accepted")
      assert_true(false)
    }
  }
}
