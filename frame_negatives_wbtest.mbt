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
