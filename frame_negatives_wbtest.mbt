// ===== 役C3：frame.mbt 未覆盖臂探针（91 冷行清剿） =====
// 手段：pub 入口 frame_document（管线族）+ 白盒直调（pattern 内部件族）。
// 纪律：探针先跑、看未行闭合再定性——死账须实证，推理不记账（用户令）。

///|
/// plain 档 options（1.1，无 base——c2_options 同形）
fn f3_options() -> JsonLdOptions {
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
/// Err 消息提取（JsonLdError 无 Show；消息不含时返回哨兵文本）
fn f3_err_msg(result : Result[JsonValue, JsonLdError]) -> String {
  match result {
    Err(Syntax(msg)) => "Syntax:" + msg
    Err(InvalidContext(msg)) => "InvalidContext:" + msg
    Err(InvalidIri(msg)) => "InvalidIri:" + msg
    Err(InvalidValue(msg)) => "InvalidValue:" + msg
    Err(InvalidList(msg)) => "InvalidList:" + msg
    Err(Unsupported(msg)) => "Unsupported:" + msg
    Err(ContextOverflow(msg)) => "ContextOverflow:" + msg
    Err(LoadingDocumentFailed(msg)) => "LoadingDocumentFailed:" + msg
    Err(InvalidScriptElement(msg)) => "InvalidScriptElement:" + msg
    Ok(_) => "OK"
  }
}

///|
/// F3-01（frame.mbt 1747）：输入展开 Err 直穿——@reverse 关键字值字面量
/// 在展开期拒（词面实测：关键字形 = invalid @reverse value；term-declare
/// 形 = invalid reverse property value，B3-29 已钉）
test "f3_01 input expand error propagates" {
  let result = frame_document(
    "{\"@reverse\":\"http:p\",\"http:q\":\"v\"}",
    "{}",
    f3_options(),
  )
  assert_true(
    f3_err_msg(result).has_prefix("InvalidValue:invalid @reverse value"),
  )
}

///|
/// F3-02（1752）：同图同 id 双 @index 不等 = colliding indexes（#te001
/// oracle 形；nq_merge_same_id@to_rdf.mbt239）——merge 在 frame 前执行，
/// Err 从 1752 穿出。输入 = 单 JSON 文档（frame 管线非行分隔）
test "f3_02 colliding indexes merge error" {
  let input = "[{\"@id\":\"http:s\",\"http:p\":{\"@id\":\"http:a\"}}," +
    "{\"@id\":\"http:a\",\"@index\":\"i1\"}," +
    "{\"@id\":\"http:a\",\"@index\":\"i2\"}]"
  let result = frame_document(input, "{}", f3_options())
  assert_true(f3_err_msg(result).has_prefix("InvalidValue:colliding indexes"))
}

///|
/// F3-03（1760）：frame 原文 JSON 解析败——Syntax Err 直穿
test "f3_03 frame parse error" {
  let result = frame_document("{\"@id\":\"http:s\"}", "{oops", f3_options())
  assert_true(f3_err_msg(result).has_prefix("Syntax:"))
}

///|
/// F3-04（1783+1851）：frame 非 map 形——"[]" 顶层：1783 空 match 臂 +
/// 1851 展开空表 get(0)=None 回落空 pattern 全配。产物实测 = 单节点裸形
/// 无 @graph 包（帧无 @graph + 单节点 compaction 不外包）
test "f3_04 frame array top falls back to empty pattern" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:p\":\"v\"}",
    "[]",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s"))
      assert_true(text.contains("http:p"))
    }
    Err(_) => fail("expected OK with empty-pattern framing")
  }
}

///|
/// F3-05（1851）：frame_inner 展开首值非 Node（@value 形）——get(0)
/// 非 Node 臂同落空 pattern 全配
test "f3_05 frame value-shaped expands to empty pattern" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:p\":\"v\"}",
    "{\"@value\":\"x\"}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("http:s"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-06（132/135/140/146/150/153/158/163/166/170/186）：merged 并集
/// 变体簇——同 id 跨 5 图，base=g1(rev+index)，g2(rev 同名 append +
/// rev2 新键 + 嵌套图 + included)，g3(嵌套图→Some/Some)，g4(included→
/// Some/Some)，g5(裸→included Some/None)。F2 预合并按图分键不吞跨图
/// 同 id（to_rdf.mbt 302-313 实证），留给 frame_subject_map 合并
test "f3_06 merged union variants across five graphs" {
  let input = "{\"@graph\":[" +
    "{\"@id\":\"http:g1\",\"@graph\":[{\"@id\":\"http:x\",\"@index\":\"i\",\"http:a\":\"1\"}]}," +
    "{\"@id\":\"http:g2\",\"@graph\":[{\"@id\":\"http:x\",\"http:b\":\"2\",\"@graph\":[{\"@id\":\"http:inner1\"}],\"@included\":[{\"@id\":\"http:n1\"}]}]}," +
    "{\"@id\":\"http:g3\",\"@graph\":[{\"@id\":\"http:x\",\"http:c\":\"3\",\"@graph\":[{\"@id\":\"http:inner2\"}]}]}," +
    "{\"@id\":\"http:g4\",\"@graph\":[{\"@id\":\"http:x\",\"http:d\":\"4\",\"@included\":[{\"@id\":\"http:n2\"}]}]}," +
    "{\"@id\":\"http:g5\",\"@graph\":[{\"@id\":\"http:x\",\"http:e\":\"5\"}]}" +
    "]}"
  let result = frame_document(input, "{}", f3_options())
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      // 判别面：跨 5 图同 id 属性并集全存（reverse/graph/included 在
      // merged 输出构构造侧有专属帧声明路径，{} 帧不出——不在此判）；
      // @index 基座位保留 = 合并体走全
      assert_true(text.contains("http:a"))
      assert_true(text.contains("http:b"))
      assert_true(text.contains("http:c"))
      assert_true(text.contains("http:d"))
      assert_true(text.contains("http:e"))
      assert_true(text.contains("@index"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-07（83）：空输入 + 顶层 @graph 帧——graph_name="@default" 在
/// graph_map 无注册（零 top 值不注册），subject_map None 臂落空图
test "f3_07 empty input with graph frame" {
  let result = frame_document("[]", "{\"@graph\":{}}", f3_options())
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("@graph"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-08（217）：@id 关键字形非关键字哨兵节点——展开期 id 位落
/// EXPLICIT_NULL_ID（t0122 oracle："@ignoreMe"→null），register 位铸新
/// bnode（字面 @id:null 展开期拒 = "@id value must be a string"，实测）
test "f3_08 explicit null id mints bnode" {
  let result = frame_document(
    "{\"@id\":\"@ignoreMe\",\"http:p\":\"v\"}",
    "{}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      // 判别面：关键字形哨兵 id 不入产物（铸号后单引用 bnode 被修剪
      // ——t0056 oracle 同源）；性质保形
      assert_true(text.contains("http:p"))
      assert_false(text.contains("@ignoreMe"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-09（355）：named graph 图递归位同 output 节点多值 push——单图内
/// 两 subject 配同一 @graph pattern，Graph 父位 graph 槽已 Some 再 push
test "f3_09 graph parent accumulates multiple subjects" {
  let input = "{\"@id\":\"http:g\",\"@graph\":[" +
    "{\"@id\":\"http:a\",\"http:p\":\"1\"}," +
    "{\"@id\":\"http:b\",\"http:p\":\"2\"}" +
    "]}"
  let result = frame_document(input, "{\"@graph\":{}}", f3_options())
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:a"))
      assert_true(text.contains("http:b"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-10（153）：嵌套图并集 (Some,Some) 循环体——同 id 双图各带非空
/// 嵌套 @graph，merged 累计体图槽 push 实跑（150 臂已中而 153 未中
/// = 此前 (Some,Some) 对 extra.graph 为空形）。
/// **fixture 纪律（本役实证定谳）**：嵌套图**项**必须带属性——`{"@id":…}`
/// 裸形属**自由浮动弃置**面（仓卷批9 坑③"@id-only 图项集合位亦弃"），
/// 展开期即出 `graph=[]` ⇒ 图字典不建、subject 不到，**非产品缺陷**
/// （前一轮 3 红即此，实测 `reg graph_id=http:x items=0` → 补属性后 items=1）
test "f3_10 nested graph union both sides" {
  let input = "{\"@graph\":[" +
    "{\"@id\":\"http:g1\",\"@graph\":[{\"@id\":\"http:x\",\"@graph\":[{\"@id\":\"http:i1\",\"http:p\":\"1\"}]}]}," +
    "{\"@id\":\"http:g2\",\"@graph\":[{\"@id\":\"http:x\",\"@graph\":[{\"@id\":\"http:i2\",\"http:p\":\"2\"}]}]}" +
    "]}"
  let result = frame_document(input, "{}", f3_options())
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:i1"))
      assert_true(text.contains("http:i2"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

// ===== 役C3 批2：值位过滤族 + 探针设施直调族 + 小件 =====

///|
/// 字面量构造（直调族用）
fn f3_lit(value : String) -> ExpandedLiteral {
  {
    value,
    datatype: None,
    language: None,
    direction: None,
    raw: None,
    index: None,
    included: None,
  }
}

///|
/// 节点构造（直调族用）
fn f3_node(
  id : String?,
  properties : Array[(String, Array[ExpandedValue])],
) -> ExpandedNode {
  {
    id,
    types: [],
    properties,
    reverse_props: [],
    graph: None,
    included: None,
    index: None,
  }
}

///|
/// FrameState 构造（十字段；`probe` 可置以驱动设施臂——`frame_document` 入口恒 None）
fn f3_state(probe : String?) -> FrameState {
  {
    graph_name: "@merged",
    graph_map: Map([]),
    bnode_counter: 0,
    embedded: false,
    embed_stack: [],
    embedded_map: Map([]),
    last_locations: Map([]),
    compaction_terms: Map([]),
    probe,
  }
}

///|
/// F3-11（frame.mbt 874）：值位过滤的非字面项恒收臂——帧侧为值 pattern、
/// 输入侧 `http:p` 是**节点** ⇒ item 非 Value ⇒ 874 `_ => return true`。
/// 匹配位须**陪跑属性**（http:q）先成立——值 pattern 单独在位会把主体滤掉
test "f3_11 value_kept non-value item kept" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:q\":\"y\",\"http:p\":{\"@id\":\"http:o\",\"http:q\":\"v\"}}",
    "{\"http:q\":\"y\",\"http:p\":{\"@value\":\"x\"}}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("http:o"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-12（880 证伪尝试）：帧属性位**空值组** `[]` —— 代码面
/// `frame_property_matches` 634-636 明写「空 pattern 清单 ⇒ 配当且仅当值缺位」，
/// 故「空组 + 值在场」的主体**在匹配位即被硬过滤**，到不了 frame_invoke 的值收位
/// ⇒ 880（`patterns.get(0)=None`）构造性不可达。实测产物 = 空图（非保留值）
test "f3_12 empty frame value group filters subject (880 证伪尝试)" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:q\":\"y\",\"http:p\":\"v\"}",
    "{\"http:q\":\"y\",\"http:p\":[]}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv) == "{\"@graph\":[]}")
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-13（889）：帧属性位值组首项为 **@list 形** ⇒ 889 `Some(_) => true` 恒收
test "f3_13 list-shaped pattern keeps value" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:q\":\"y\",\"http:p\":\"v\"}",
    "{\"http:q\":\"y\",\"http:p\":{\"@list\":[\"x\"]}}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("http:p"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-14（1029）：@type 位的 bnode 标签重铸——relabel 的 types 循环铸号臂
test "f3_14 bnode type relabel mints" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"@type\":\"_:t1\",\"http:p\":\"v\"}",
    "{}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("http:p"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-15（418）：`@never` × 具名图子帧合成——帧含顶层 @graph ⇒
/// graph_name="@default" ≠ "@merged" ⇒ 1180 合成帧走 `Never => "@never"`
test "f3_15 never embed named-graph subframe synthesis" {
  let result = frame_document(
    "{\"@id\":\"http:g\",\"@graph\":[{\"@id\":\"http:a\",\"http:p\":\"v\"}]}",
    "{\"@graph\":{\"@embed\":\"@never\"}}",
    f3_options(),
  )
  match result {
    Ok(_) => ()
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-16（44/53）：探针设施两行（`state.probe = Some` 臂）——白盒直调
/// （`frame_document` 入口恒 probe=None，设施面只能直调驱动）
test "f3_16 probe facility mint and trace" {
  let state = f3_state(Some(""))
  let _ = frame_fresh_bnode(state)
  frame_trace(state, "X")
  match state.probe {
    Some(t) => {
      assert_true(t.contains("MINT _:b0"))
      assert_true(t.contains("X"))
    }
    None => fail("probe not recorded")
  }
}

///|
/// F3-17（986/988）：@last 前嵌位替换的两条跳过臂——值组项为**字面量**（988
/// `_ => ()`）与**无 id 节点**（986 `None => ()`）
test "f3_17 replace embed skip arms" {
  let parent = f3_node(Some("http:p1"), [
    (
      "http:mixed",
      [
        ExpandedValue::Value(f3_lit("v")),
        ExpandedValue::Node(f3_node(None, [])),
      ],
    ),
  ])
  frame_replace_embed_with_ref(parent, "http:mixed", "http:target")
  // 无命中 id ⇒ 无替换；断言值组原样（两跳过臂已执行）
  match parent.properties.get(0) {
    Some(p) => assert_eq(p.1.length(), 2)
    None => fail("properties lost")
  }
}

///|
/// F3-18（466）：frame_matching 的 subject 缺席臂——传入未注册 id ⇒ 跳过
test "f3_18 frame_matching missing subject" {
  let state = f3_state(None)
  let matched = frame_matching(
    state,
    ["http:absent"],
    frame_empty_pattern(),
    false,
  )
  assert_eq(matched.length(), 0)
}

// ===== 役C3 批3：merged_union 反转并集族 + node_matches/flag_word 证伪尝试 =====

///|
/// F3-19（132/135/140/146）：merged 并集的 **reverse_props** 块——同 id 跨图，
/// g1 带 http:r、g2 带 http:r（同键并值）+ http:r2（新键）
test "f3_19 merged union reverse props" {
  let input = "{\"@graph\":[" +
    "{\"@id\":\"http:g1\",\"@graph\":[{\"@id\":\"http:x\",\"@reverse\":{\"http:r\":{\"@id\":\"http:a\",\"http:p\":\"1\"}}}]}," +
    "{\"@id\":\"http:g2\",\"@graph\":[{\"@id\":\"http:x\",\"@reverse\":{\"http:r\":{\"@id\":\"http:b\",\"http:p\":\"2\"},\"http:r2\":{\"@id\":\"http:c\",\"http:p\":\"3\"}}}]}" +
    "]}"
  let result = frame_document(input, "{}", f3_options())
  match result {
    Ok(_) => ()
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-20（178 证伪尝试）：merged 并集 `extra.id` 臂——须 base.id = None 且
/// 同注册键跨图；两枚匿名节点各铸各号 ⇒ 键不同不可并（实测看 178 是否闭）
test "f3_20 merged union extra id arm (178 证伪尝试)" {
  let input = "{\"@graph\":[" +
    "{\"@id\":\"http:g1\",\"@graph\":[{\"http:p\":\"1\"}]}," +
    "{\"@id\":\"http:g2\",\"@graph\":[{\"http:p\":\"2\"}]}" +
    "]}"
  let result = frame_document(input, "{}", f3_options())
  match result {
    Ok(_) => ()
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-21（514/549 证伪尝试）：@id/@type 位值组出现 **List 形** pattern ⇒
/// `_ => ()` 跳过臂。实测：值对象形进 @type 是否被展开期拒
test "f3_21 id/type list-shaped pattern (514/549 证伪尝试)" {
  let result = frame_document(
    "{\"@id\":\"http:s\",\"http:p\":\"v\"}",
    "{\"@type\":{\"@list\":[\"http:T\"]}}",
    f3_options(),
  )
  match result {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
/// F3-22（442 证伪尝试）：frame_flag_word 的 `_ => None`——帧旗位值组首项非
/// Value（节点形 / 空组）。实测各形是否被展开期拒
test "f3_22 flag word non-value pattern (442 证伪尝试)" {
  let forms : Array[String] = [
    "{\"@embed\":{\"@id\":\"http:e\"}}", "{\"@embed\":[]}", "{\"@explicit\":{\"@id\":\"http:e\"}}",
    "{\"@requireAll\":{\"@id\":\"http:e\"}}",
  ]
  for frame_text in forms {
    let result = frame_document(
      "{\"@id\":\"http:s\",\"http:p\":\"v\"}",
      frame_text,
      f3_options(),
    )
    match result {
      Ok(_) => ()
      Err(_) => ()
    }
  }
}

///|
/// F3-23（686）：list pattern vs 非 List 数据项——s2 纯串值在 list
/// pattern 臂被 `_` 跳过（不配），s1 list-vs-list 通配项配
test "f3_23 list pattern skips non-list values" {
  let input = "{\"@graph\":[" +
    "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[\"L1\"]}}," +
    "{\"@id\":\"http:s2\",\"http:l\":\"PLAIN686\"}" +
    "]}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("L1"))
      assert_false(text.contains("PLAIN686"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-24（720 中靶；718 证伪定谳）：node pattern 递归位的值组扫描——纯串值
/// 非 Node → 720 跳；匿名节点**在匹配时已非匿名**：frame_register 对
/// id-less 值铸号并回写引用（id=Some("_:b0")）⇒ 718 的 ref_node.id None
/// 臂在 subject map 值位不可达（构造性死账，注册回写不变式），递归经
/// _:b0 配中 ⇒ s1 合法入产物（正 oracle）
test "f3_24 node pattern recursion matches via minted bnode" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":[\"P720\",{\"http:q\":\"w\"}]}"
  let result = frame_document(
    input,
    "{\"http:p\":{\"http:q\":\"w\"}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("P720"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-25（788）：@type-only 值 pattern（数组形触发保形预扫）——v 位
/// @value 缺席 ⇒ None => false，性质不配；@type 是唯一语义性质 ⇒
/// 整节点出局（s1 不入产物；TVAL 不入）
test "f3_25 type-only value pattern drops node" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":{\"@value\":\"TVAL\",\"@type\":\"http:T\"}}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@type\":[\"http:T\"]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_false(text.contains("http:s1"))
      assert_false(text.contains("TVAL"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-26（800 中靶；802 死账）：@value 位 {} 通配成分——v 位 wildcard
/// 臂开（800），纯串值全收（正 oracle：VWILD 进产物）。802 = 成分非
/// Value/Node 的 `_` 臂——成分构造器（expand_standard 5363 返回面
/// Node/Value/None）永不产 List 形 ⇒ 构造性死账
test "f3_26 value wildcard component keeps any value" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":\"VWILD\"}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@value\":[{}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("VWILD"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-27（823 中靶；825 死账）：@type 位 {} 通配成分（@value 同帧
/// listed 精确配）——t 位 wildcard 臂开（823，经 expand_type_default_object
/// 空 @default = 空 pattern），带 datatype 值收。825 死账同 802（返回面）
test "f3_27 type wildcard component keeps typed value" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":{\"@value\":\"TV27\",\"@type\":\"http:T\"}}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@value\":[\"TV27\"],\"@type\":[{}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("TV27"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-28（851 中靶；853 死账）：@language 位 {} 通配成分（@value 同帧
/// listed）——l 位 wildcard 臂开（851），带语言值收。853 死账同 802
test "f3_28 language wildcard component keeps lang value" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":{\"@value\":\"LV28\",\"@language\":\"en\"}}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@value\":[\"LV28\"],\"@language\":[{}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("LV28"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-29（874）：值 pattern 性质位的 **Node 引用值**——item 非 Value
/// ⇒ 照收（词面判定面："通配/node pattern 位值照收"）；兄弟通配性质
/// 保节点配中（无兄弟时 @value pattern 不配 Node 项、整节点出局）
test "f3_29 node reference value kept under value pattern" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":{\"@id\":\"http:z\"},\"http:r\":\"R29\"}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@value\":[\"X\"]}],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("R29"))
      assert_true(text.contains("http:z"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-30（880 定谳死账 + 预检行为钉）：frame_node_matches 节点级预检
/// （489-495）对空 pattern 清单性质**带值节点整颗出局**（t0023 oracle）
/// ⇒ frame_value_kept 的 Some([]) 形不可达：唯一调用点 1287 走
/// node.properties item 循环——带值节点进不来（预检拒），空值数组不走
/// item（零循环）。行为钉 = s1 整颗不在产物（实测 @graph 空）
test "f3_30 match-none prescan drops node entirely" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":\"EMPTY880\",\"http:r\":\"RVAL\"}"
  let result = frame_document(
    input,
    "{\"http:p\":[],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_false(text.contains("http:s1"))
      assert_false(text.contains("RVAL"))
      assert_false(text.contains("EMPTY880"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-31（889）：性质 pattern 首值 = **List 形**（@list pattern 位）——
/// 值位收值门 Some(_) 臂放行（节点经兄弟通配配中）
test "f3_31 list-shaped pattern first value kept" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":\"LVAL889\",\"http:r\":\"R31\"}"
  let result = frame_document(
    input,
    "{\"http:p\":[{\"@list\":{}}],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("R31"))
      assert_true(text.contains("LVAL889"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-32（910/912）：list pattern 项 = 值 pattern（@value 数组形）vs
/// 数据 list 值项——list_item 值 pattern 臂实跑；整表输出不滤（LX/LY
/// 双在）
test "f3_32 list pattern with value pattern items" {
  let input = "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[\"LX\",\"LY\"]}}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{\"@value\":[\"LX\"]}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("LX"))
      assert_true(text.contains("LY"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-33（916）：list pattern 项 = 通配 {} 节点——wildcard 臂恒真
test "f3_33 wildcard item in list pattern" {
  let input = "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[\"W16\"]}}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{}]}]}",
    f3_options(),
  )
  match result {
    Ok(jv) => assert_true(render_json(jv).contains("W16"))
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-34（923 死账定谳）：list pattern 项 = node pattern，数据项 =
/// 匿名节点——**list 数据项同样经 register 铸号回写**（items[i] = 铸号
/// 引用替入）⇒ 配时 ref id 恒 Some，923 的 None 臂不可达；递归经 _:bN
/// 配中（判别探针：list pattern 作唯一语义性质，s1 入产物 = 配中实证）
test "f3_34 anonymous node in list vs node pattern" {
  let input = "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[{\"http:q\":\"w\"}]},\"http:r\":\"R34\"}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{\"http:q\":\"w\"}]}],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("R34"))
      assert_true(text.contains("http:q"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-35（928）：pattern 本身 = **List 形**（嵌套 @list pattern）——
/// list_item List 臂恒假；节点经兄弟通配配中，嵌套 list 原样出
test "f3_35 nested list pattern arm" {
  let input = "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[{\"@list\":[\"NX\"]}]},\"http:r\":\"R35\"}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{\"@list\":[\"NX\"]}]}],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("R35"))
      assert_true(text.contains("NX"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-36（913）：list 项 = 值 pattern，数据 listitem **Node 形在首**——
/// 非 Value ⇒ false（值 pattern 不配节点项；若值项在先即配即 break
/// 轮不到，故 Node 须居首）；V 值项随后配中
test "f3_36 node listitem under value pattern item" {
  let input = "{\"@id\":\"http:s1\",\"http:l\":{\"@list\":[{\"@id\":\"http:n\"},\"V\"]},\"http:r\":\"R36\"}"
  let result = frame_document(
    input,
    "{\"http:l\":[{\"@list\":[{\"@value\":[\"V\"]}]}],\"http:r\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("R36"))
      assert_true(text.contains("V"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-37（1485）：@type 成分混形——@default 对象（无条件配 + 注入）
/// 与 {} 空 pattern（无 @default 键 ⇒ 注入扫描 None 臂）；纯 {} 形
/// 无型节点被 @type 硬过滤拒（通配须有型，实测）
test "f3_37 type default object without default key" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":\"v\"}"
  let result = frame_document(
    input,
    "{\"@type\":[{\"@default\":\"http:T\"},{}],\"http:p\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("http:T"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-38（1487）：@type 成分混形（@default 对象 + 串 IRI）——注入扫描
/// 对非 Node 项走 `_` 臂（串成分不注入）；@default 对象照注 http:T
test "f3_38 mixed type components skip string item" {
  let input = "{\"@id\":\"http:s1\",\"http:p\":\"v\"}"
  let result = frame_document(
    input,
    "{\"@type\":[{\"@default\":\"http:T\"},\"http:U\"],\"http:p\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("http:T"))
      assert_false(text.contains("http:U"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-39（1580）：@reverse 反扫的值组 `_` 臂——其他主体在 rev IRI 位
/// 持**字面量**（数据侧 rev 为普通 term + 串值），非 Node ⇒ 跳过不计
/// points（字面量不构成反向指）
test "f3_39 literal under reverse iri not counted" {
  let input = "{\"@context\":{\"rev\":\"http:rev\"},\"@graph\":[" +
    "{\"@id\":\"http:s1\",\"http:p\":\"x\"}," +
    "{\"@id\":\"http:s2\",\"rev\":\"LIT\"}" +
    "]}"
  let result = frame_document(
    input,
    "{\"@context\":{\"rev\":{\"@reverse\":\"http:rev\"}},\"rev\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("http:s2"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-40：顶位 @graph 对象帧（frameExpansion 展开成图内容数组 ⇒
/// frame_root 无 graph 字段）+ 命名图节点 → 图递归走合成子帧面
/// （1180；1187 的 Some([]) 形另见 F3-45 数组包裹帧）
test "f3_40 empty graph pattern array" {
  let result = frame_document(
    "{\"@id\":\"http:g\",\"@graph\":[{\"@id\":\"http:s1\",\"http:p\":\"v\"}]}",
    "{\"@graph\":[]}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:g"))
      assert_true(text.contains("http:s1"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-41（1821）：帧 context 显式 null 映射 term（{"p":{"@id":null}}）——
/// term 保留而 iri None（final_iri@4539）⇒ 压缩词表收集 None 臂跳过
test "f3_41 null id term skipped in compaction terms" {
  let result = frame_document(
    "{\"@id\":\"http:s1\",\"http:q\":\"v\"}",
    "{\"@context\":{\"p\":{\"@id\":null}},\"http:q\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-42：缺位性质 @preserve 包装节点发射→摊平→值直达产物
/// （1540 发射 + 1625 摊平 + 压缩值成形）。另性质先配（t0009 形：
/// 纯 @default 帧拒——@default 触发值 pattern 预扫，缺位值位不配）。
/// 1920 计数扫描面：摊平在扫描前原位完成 ⇒ id-None 节点不达扫描（死账）
test "f3_42 preserve wrapper id none in count scan" {
  let result = frame_document(
    "{\"@id\":\"http:s1\",\"http:p\":\"x\"}",
    "{\"http:p\":{},\"http:q\":{\"@default\":\"D\"}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("D"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-43（1972）：压缩面错误传播——scheme 撞名（#te002 家族：键 tag:foo
/// 的 scheme 恰为在册 term 名且重展开异指，@prefix:false 保帧侧键不成
/// curie ⇒ 发射位 check_key_scheme_collision 报 InvalidContext，逐层
/// 上传至 compact_node_jv Err 臂）
test "f3_43 scheme collision error through compaction" {
  let result = frame_document(
    "{\"@id\":\"http:s1\",\"tag:foo\":\"v\"}",
    "{\"@context\":{\"tag\":{\"@id\":\"http://other/\",\"@prefix\":false}},\"tag:foo\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => fail("expected error, got: " + render_json(jv))
    Err(InvalidContext(msg)) => assert_eq(msg, "scheme collides with term name")
    Err(e) => fail("expected InvalidContext, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-44（2009）：帧 **@context null**——frame_inner = Null 字面
/// （1771-1782 提取），context_empty 判定 Null 臂 → 无 @context 回填
test "f3_44 null context value in frame" {
  let result = frame_document(
    "{\"@id\":\"http:s1\",\"http:q\":\"v\"}",
    "{\"@context\":null,\"http:q\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_false(text.contains("@context"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-45（1187）：**数组包裹帧** [{...}]——@graph 空数组经节点位展开
/// 存进 pattern 节点 graph 字段（Some([])，1768 装配面）⇒ 图递归子帧
/// 合成 get(0) None 臂落合成 pattern，图内主体照帧
test "f3_45 array wrapped frame graph empty pattern" {
  let result = frame_document(
    "{\"@id\":\"http:g\",\"@graph\":[{\"@id\":\"http:s1\",\"http:p\":\"v\"}]}",
    "[{\"@graph\":[]}]",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:g"))
      assert_true(text.contains("http:s1"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}

///|
/// F3-46（2010）：帧 @context **数组形**——frame_inner 非 Object/Null
/// ⇒ context_empty `_` 臂 false → @context 原文数组回填
test "f3_46 array context value in frame" {
  let result = frame_document(
    "{\"@id\":\"http:s1\",\"http:q\":\"v\"}",
    "{\"@context\":[],\"http:q\":{}}",
    f3_options(),
  )
  match result {
    Ok(jv) => {
      let text = render_json(jv)
      assert_true(text.contains("http:s1"))
      assert_true(text.contains("@context"))
    }
    Err(e) => fail("expected OK, got: " + f3_err_msg(Err(e)))
  }
}
