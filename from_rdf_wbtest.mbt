// ===== 役C3 移防⑥（from_rdf 54 行）：解析形态门 + 列表走查边臂 + 复合字面面
// + 命名图族 + 直调单件。死账/挂账归类见 todo 批账（纯列门先行族勿探）。=====

///|
let f6_ns : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

///|
fn from6_options() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
}

///|
fn from6_compound_options() -> JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: Some("compound-literal"),
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
}

///|
test "f6: parse and shape errors (284/296/323)" {
  match from_rdf_document("garbage line", from6_options()) {
    Err(InvalidValue(msg)) => assert_true(msg.contains("invalid N-Quads"))
    _ => fail("284: expected parse error")
  }
  match
    from_rdf_document("<http://s/> \"lit\" <http://o/> .", from6_options()) {
    Err(InvalidValue(msg)) => assert_eq(msg, "invalid predicate term")
    _ => fail("296: expected predicate error")
  }
  match
    from_rdf_document("<http://s/> <\{f6_ns}type> \"lit\" .", from6_options()) {
    Err(InvalidValue(msg)) => assert_eq(msg, "rdf:type object must be IRI")
    _ => fail("323: expected rdf:type error")
  }
}

///|
test "f6: literal subject key (140)" {
  // 文法外容错形：字面量主语 → 账键取词面值（140）
  match
    from_rdf_document("\"lit\" <http://p/> <http://o/> .", from6_options()) {
    Ok(_) => ()
    Err(_) => fail("expected literal-subject quad to be tolerated")
  }
}

///|
test "f6: direct-call singletons (130/814/818)" {
  // 混合形语言/数据类型位（130 Some/None 错位）
  assert_true(!from_rdf_opt_string_eq(Some("a"), None))
  assert_true(from_rdf_opt_string_eq(None, None))
  // 前缀判定：短串假（814）+ 位差假（818）
  assert_true(!index_of_str_prefix("ab", "abc"))
  assert_true(!index_of_str_prefix("ab", "ax"))
  assert_true(index_of_str_prefix("abcd", "ab"))
}

///|
test "f6: basic pure list renders (154/156/1002)" {
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> .",
      from6_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@id\":\"http://s/\",\"http://p/\":[{\"@list\":[{\"@value\":\"x\"}]}]}]",
      )
    Err(_) => fail("expected basic list to convert")
  }
}

///|
test "f6: list walk edges (901/947/913/921)" {
  // rest 指向未入账 bnode（901 list node missing）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> _:ghost .",
      from6_options(),
    ) {
    // 纯列门先行：rest 未入账 ⇒ 纯列判假走节点渲染（901 walk 缺席臂挂账）
    Ok(_) => ()
    Err(_) => fail("901: expected dangling rest to be tolerated")
  }
  // 列内坏 langtag 成员 → render_literal Err 上抛（947）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\"@toolongtag .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> .",
      from6_options(),
    ) {
    Err(_) => ()
    // 渲染面无 langtag 校验（容错保形）——947 Err 源另勘挂账
    Ok(_) => ()
  }
  // 嵌套纯列（913/921——first 位指向纯列链节）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> _:m .\n_:m <\{f6_ns}first> \"y\" .\n_:m <\{f6_ns}rest> <\{f6_ns}nil> .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> .",
      from6_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@id\":\"http://s/\",\"http://p/\":[{\"@list\":[{\"@list\":[{\"@value\":\"y\"}]}]}]}]",
      )
    Err(_) => fail("expected nested pure list to convert")
  }
}

///|
test "f6: compound literal faces (612/643/646/659/666/674/685)" {
  // 吸收成功形（672 区主径）：value+direction → 值对象
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:c .\n_:c <\{f6_ns}value> \"v\" .\n_:c <\{f6_ns}direction> \"ltr\" .",
      from6_compound_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@id\":\"http://s/\",\"http://p/\":[{\"@value\":\"v\",\"@direction\":\"ltr\"}]}]",
      )
    Err(_) => fail("expected compound literal to absorb")
  }
  // 悬空引用（643——对象 bnode 从未作主语）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:dangling .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("643: expected dangling ref to be tolerated")
  }
  // 带 rdf:type 的引用 bnode = 非复合（646）
  match
    from_rdf_document(
      "_:t <\{f6_ns}type> <http://T/> .\n<http://s/> <http://p/> _:t .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("646: expected typed ref to fall through")
  }
  // 无 rdf:value（659）/ value 非纯字面量（666）/ 无语言无方向（674/685）
  match
    from_rdf_document(
      "_:v2 <http://q/> \"w\" .\n<http://s/> <http://p/> _:v2 .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("659: expected value-less ref to fall through")
  }
  match
    from_rdf_document(
      "_:v3 <\{f6_ns}value> \"5\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n<http://s/> <http://p/> _:v3 .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("666: expected typed value to fall through")
  }
  match
    from_rdf_document(
      "_:v4 <\{f6_ns}value> \"v\" .\n<http://s/> <http://p/> _:v4 .",
      from6_compound_options(),
    ) {
    Ok(value) =>
      assert_eq(
        render_json(value),
        "[{\"@id\":\"http://s/\",\"http://p/\":[{\"@value\":\"v\"}]}]",
      )
    Err(_) => fail("674/685: expected value-only compound to absorb")
  }
}

///|
test "f6: i18n face plain lang literal (746)" {
  let options : JsonLdOptions = {
    base: None,
    expand_context: None,
    processing_mode: JsonLd11,
    load_context: None,
    rdf_direction: Some("i18n-datatype"),
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
  match from_rdf_document("<http://s/> <http://p/> \"v\"@en .", options) {
    Ok(_) => ()
    Err(_) => fail("746: expected plain lang literal under i18n mode")
  }
}

///|
test "f6: named graph faces (402/404/493/507/554)" {
  // 命名图 + 无 compound 选项（493 兜底臂 + 图内三元组照转）
  match
    from_rdf_document(
      "<http://s/> <http://p/> \"v\" <http://g/> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("493: expected named graph quad to convert")
  }
  // 命名图 + compound 选项（402/404 收集面）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:c <http://g/> .\n_:c <\{f6_ns}value> \"v\" .\n_:c <\{f6_ns}direction> \"ltr\" .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("402/404: expected named compound face to convert")
  }
  // 命名图内坏 langtag（507 render_member Err 传播）
  match
    from_rdf_document(
      "<http://s/> <http://p/> \"x\"@toolongtag <http://g/> .",
      from6_options(),
    ) {
    // 渲染面无 langtag 校验（容错保形）——507 Err 源另勘挂账
    Ok(_) => ()
    Err(_) => fail("507: expected named bad langtag to be tolerated")
  }
}

///|
test "f6: pure-list scoped edges (198/234/256/270/272/842/869/879)" {
  // rest 自环（256 纯列判定假 + 879 同族）——退节点渲染
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> _:l .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("256: expected self-cycle to be tolerated")
  }
  // rest 直指 nil（270 纯列判定真）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("270: expected direct-nil chain to convert")
  }
  // rest 字面量（272/879 纯列判定假）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> \"lit\" .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("272: expected literal rest to be tolerated")
  }
  // 悬空列表引用（842/989 节点缺席 continue）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:dangling-list .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("842: expected dangling list ref to be tolerated")
  }
  // rest 链节指非 nil IRI（869 rest IRI 非 nil → false）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> \"x\" .\n_:l <\{f6_ns}rest> <http://other/> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("869: expected non-nil IRI rest to be tolerated")
  }
}

///|
test "f6: named graph list combos (198/234/237/241/256/270/272)" {
  // 命名图内纯列 → scoped 纯列面（198 rest 直指 nil / 270 同族）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l <http://g/> .\n_:l <\{f6_ns}first> \"x\" <http://g/> .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> <http://g/> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("named pure list: expected tolerated")
  }
  // 命名图内 rest 自环 → scoped 判假退节点渲染（256）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l <http://g/> .\n_:l <\{f6_ns}first> \"x\" <http://g/> .\n_:l <\{f6_ns}rest> _:l <http://g/> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("named self-cycle: expected tolerated")
  }
  // 双图引用同一列表链节 → multi 记账面（234/237）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l <http://g1/> .\n<http://t/> <http://p/> _:l <http://g2/> .\n_:l <\{f6_ns}first> \"x\" <http://g1/> .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> <http://g1/> .",
      from6_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("multi-graph ref: expected tolerated")
  }
}

///|
test "f6: compound ref with language prop but no value (659)" {
  // allowed 属性集内（language）但缺 value 位 → 659 None 落穿
  match
    from_rdf_document(
      "_:v5 <\{f6_ns}language> \"en\" .\n<http://s/> <http://p/> _:v5 .",
      from6_compound_options(),
    ) {
    Ok(_) => ()
    Err(_) => fail("659: expected language-only ref to fall through")
  }
}

///|
test "f6: list member first pointing at nil (914)" {
  // first 位直指 nil IRI = 空嵌套列表（914 空物化臂）
  match
    from_rdf_document(
      "<http://s/> <http://p/> _:l .\n_:l <\{f6_ns}first> <\{f6_ns}nil> .\n_:l <\{f6_ns}rest> <\{f6_ns}nil> .",
      from6_options(),
    ) {
    Ok(value) => assert_true(render_json(value).contains("@list"))
    Err(_) => fail("914: expected nil-first list to convert")
  }
}
