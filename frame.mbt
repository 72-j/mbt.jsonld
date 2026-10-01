///|
/// framing 面落码（J5——spec §8.93 勘定 / §8.94 开工第一笔 / 本役 = 首役
/// #t0001 冒烟）。REC JSON-LD 1.1 Framing：管线五段复用（expand 全链 /
/// F2 同 id 预合并 / graph map / compaction 主体），新算法主体 = Frame
/// Matching + Framing 两递归。首役骨架覆盖 1.0 基础族单链嵌套（#t0001）；
/// wildcard / match-none / value pattern / 帧旗覆写（@embed/@explicit/
/// @requireAll/@omitDefault——frameExpansion 展开批）/ named graph 递归
/// / @reverse / list pattern / @preserve 发射 / prune bnodes / 环检测
/// 逐簇役落码，每批以套件例为钉（禁无判定面落码）。

///|
/// framing 状态（REC framing state——骨架面：旗字段随 frameExpansion 批进）
priv struct FrameState {
  /// "@default"（frame 顶层 @graph ⇒ frameDefault）| "@merged"（缺省）
  graph_name : String
  /// graph map（REC Node Map Generation 产物）：graph 名 → subject id → 节点
  graph_map : Map[String, Map[String, ExpandedNode]]
  /// 无 id 节点铸号器（flatten_fresh_bnode 同款 "_:bN"；输入标签避撞预扫
  /// 随 bnode 簇批补）
  mut bnode_counter : Int
}

///|
fn frame_fresh_bnode(state : FrameState) -> String {
  let term = "_:b\{state.bnode_counter}"
  state.bnode_counter += 1
  term
}

///|
/// subject map：当前 graph 名下的 subject 集合；"@merged" = 全 graph 并集
/// （REC Merge Node Maps——同 id 跨图首见胜）
fn frame_subject_map(state : FrameState) -> Map[String, ExpandedNode] {
  if state.graph_name == "@merged" {
    let merged : Map[String, ExpandedNode] = Map([])
    for _, nodes in state.graph_map {
      for id, node in nodes {
        if !merged.contains(id) {
          merged[id] = node
        }
      }
    }
    merged
  } else {
    match state.graph_map.get(state.graph_name) {
      Some(nodes) => nodes
      None => {
        let empty : Map[String, ExpandedNode] = Map([])
        empty
      }
    }
  }
}

///|
/// graph map 构建（REC Node Map Generation 骨架）：嵌套节点对象抽出注册、
/// 原位留 node reference；值对象原位；@list 逐项抽取（index 槽原位保形）；
/// named graph 内容注册到以其 @id 命名的图。同 id 首见注册（F2 预合并已
/// 保证图内同 id 单点）
fn frame_register(
  state : FrameState,
  graph_name : String,
  value : ExpandedValue,
) -> ExpandedValue {
  match value {
    ExpandedValue::Value(_) => value
    ExpandedValue::List(items, ..) => {
      for i, item in items {
        items[i] = frame_register(state, graph_name, item)
      }
      value
    }
    ExpandedValue::Node(node) => {
      // named graph 内容先注册（内容节点属以其 @id 命名的图）
      match node.graph {
        Some(items) => {
          let graph_id = match node.id {
            Some(id) => id
            None => frame_fresh_bnode(state)
          }
          for item in items {
            let _ = frame_register(state, graph_id, item)
          }
        }
        None => ()
      }
      // 性质位抽取（原位替换为 reference）
      for pair in node.properties {
        for i, item in pair.1 {
          pair.1[i] = frame_register(state, graph_name, item)
        }
      }
      // 自身注册（首见胜）
      let self_id = match node.id {
        Some(id) =>
          if id == EXPLICIT_NULL_ID {
            frame_fresh_bnode(state)
          } else {
            id
          }
        None => frame_fresh_bnode(state)
      }
      let nodes = match state.graph_map.get(graph_name) {
        Some(existing) => existing
        None => {
          let fresh : Map[String, ExpandedNode] = Map([])
          state.graph_map[graph_name] = fresh
          fresh
        }
      }
      if !nodes.contains(self_id) {
        nodes[self_id] = node
      }
      // 原位留 node reference
      ExpandedValue::Node({
        id: Some(self_id),
        types: [],
        properties: [],
        reverse_props: [],
        graph: None,
        included: None,
        index: None,
      })
    }
  }
}

///|
/// 父位（REC parent）：顶层 results 数组 | output 节点性质位
priv enum FrameParent {
  Top(Array[ExpandedValue])
  Prop(ExpandedNode, String)
}

///|
/// output 性质位追加（同性质多值累积——REC output[property] 数组语义）
fn frame_output_add(
  node : ExpandedNode,
  property : String,
  value : ExpandedValue,
) -> Unit {
  for pair in node.properties {
    if pair.0 == property {
      pair.1.push(value)
      return
    }
  }
  node.properties.push((property, [value]))
}

///|
fn frame_parent_add(parent : FrameParent, value : ExpandedValue) -> Unit {
  match parent {
    Top(arr) => arr.push(value)
    Prop(node, property) => frame_output_add(node, property, value)
  }
}

///|
/// 帧性质值查取
fn frame_property_values(
  frame_node : ExpandedNode,
  property : String,
) -> Array[ExpandedValue]? {
  for pair in frame_node.properties {
    if pair.0 == property {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 节点性质值查取（缺性质 = 空数组——REC 匹配语义 "values is empty"）
fn frame_node_values(
  node : ExpandedNode,
  property : String,
) -> Array[ExpandedValue] {
  for pair in node.properties {
    if pair.0 == property {
      return pair.1
    }
  }
  []
}

///|
/// 合成空帧（帧缺性质位 / 帧展开为空时的全配 pattern——explicit=false 下
/// 全性质随嵌递归收编）
fn frame_empty_pattern() -> ExpandedNode {
  {
    id: None,
    types: [],
    properties: [],
    reverse_props: [],
    graph: None,
    included: None,
    index: None,
  }
}

///|
/// 帧旗读取（frameExpansion 保形词形——spec §8.96）：pattern properties 的
/// keyword 键首值词形（"true"/"false"/"@always"…）
fn frame_flag_word(frame_node : ExpandedNode, keyword : String) -> String? {
  match frame_property_values(frame_node, keyword) {
    Some(values) =>
      match values.get(0) {
        Some(ExpandedValue::Value(lit)) => Some(lit.value)
        _ => None
      }
    None => None
  }
}

///|
/// Frame Matching 主入口：subjects 过滤 + 码点序。确定性骨架 = 恒排
/// （REC ordered 旗「code point order if ordered」的骨架化——unordered
/// 语义 oracle 差异面随对拍役校）
fn frame_matching(
  state : FrameState,
  subjects : Array[String],
  frame_node : ExpandedNode,
  require_all : Bool,
) -> Array[String] {
  let subject_map = frame_subject_map(state)
  let matched : Array[String] = []
  for id in subjects {
    match subject_map.get(id) {
      Some(node) =>
        if frame_node_matches(state, node, frame_node, require_all) {
          matched.push(id)
        }
      None => ()
    }
  }
  matched.sort()
  matched
}

///|
/// Frame Matching 单节点（REC 骨架三臂）：@id 位 IRI 直配 / @type 位
/// IRI∈types / node pattern 递归（值位 subjects 下代匹配非空）。
/// @id/@type 失配恒否（硬过滤，处理即断）；余性质 requireAll 分 all/any；
/// framing 旗/@default 键不参与匹配（REC "no other keywords are
/// considered"）。wildcard / match-none / value pattern / @default 缺位配
/// 形随批落码
fn frame_node_matches(
  state : FrameState,
  node : ExpandedNode,
  frame_node : ExpandedNode,
  require_all : Bool,
) -> Bool {
  // 语义性质位 = 非 @ 键性质（framing 旗/@default pattern 键不算——REC
  // "no other keywords are considered"；旗-only pattern = 空帧全配）
  let mut has_semantic_property = false
  for pair in frame_node.properties {
    if !(pair.0.get_char(0) is Some('@')) {
      has_semantic_property = true
      break
    }
  }
  let frame_empty = frame_node.id is None &&
    frame_node.types.is_empty() &&
    !has_semantic_property
  if frame_empty {
    return true
  }
  // @id 位硬过滤（骨架：单 IRI 直配——数组/通配形随 frameExpansion 批）
  match frame_node.id {
    Some(frame_id) => if frame_id != node_id_of(node) { return false }
    None => ()
  }
  // @type 位硬过滤（IRI 清单任配）
  if !frame_node.types.is_empty() {
    let mut type_match = false
    for wanted in frame_node.types {
      if node.types.contains(wanted) {
        type_match = true
        break
      }
    }
    if !type_match {
      return false
    }
  }
  // 性质位记账：@id/@type 到此必已配（计入 any/all）；pattern 递归判余位
  let mut all_match = true
  let mut any_match = frame_node.id is Some(_) || !frame_node.types.is_empty()
  let mut saw_semantic = false
  for pair in frame_node.properties {
    if pair.0.get_char(0) is Some('@') {
      continue
    }
    saw_semantic = true
    if frame_property_matches(state, node, pair.0, pair.1, require_all) {
      any_match = true
    } else {
      all_match = false
    }
  }
  // 仅 @id/@type（旗已剔）——硬过滤已过即配
  if !saw_semantic {
    return true
  }
  if require_all {
    all_match
  } else {
    any_match
  }
}

///|
fn node_id_of(node : ExpandedNode) -> String {
  match node.id {
    Some(id) => id
    None => ""
  }
}

///|
/// 性质位匹配（REC 骨架 = node pattern 臂）：值位 node references 的 id
/// 作 subjects 下代递归，非空即配。value pattern / wildcard / match-none
/// / @default 缺位配随 frameExpansion 批落码
fn frame_property_matches(
  state : FrameState,
  node : ExpandedNode,
  property : String,
  patterns : Array[ExpandedValue],
  require_all : Bool,
) -> Bool {
  let values = frame_node_values(node, property)
  for pattern in patterns {
    match pattern {
      ExpandedValue::Node(pattern_node) => {
        let value_subjects : Array[String] = []
        for item in values {
          match item {
            ExpandedValue::Node(ref_node) =>
              match ref_node.id {
                Some(ref_id) => value_subjects.push(ref_id)
                None => ()
              }
            _ => ()
          }
        }
        let matched = frame_matching(
          state, value_subjects, pattern_node, require_all,
        )
        if !matched.is_empty() {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// Framing Algorithm（REC 骨架）：matched 码点序枚举 → output 节点装配
/// （keyword 位拷贝 + 性质位：值对象直追加 / node reference 子帧递归嵌入）
/// → parent 收账。旗覆写（requireAll/explicit）+ explicit 收编门 + 帧缺位
/// 性质 @preserve 发射本批已落；embed 旗三分支（@never / @once 已嵌 /
/// 环检测）、named graph 递归（graph_map 有 id 条目）、@included、@reverse：
/// 随各簇役落码
fn frame_invoke(
  state : FrameState,
  subjects : Array[String],
  frame_node : ExpandedNode,
  parent : FrameParent,
) -> Unit {
  // 帧旗覆写（REC 步 2——帧内 @requireAll/@explicit 覆写本帧子树；词形
  // "true"/"false" 自 frameExpansion 保形。@embed 旗随 embed 状态机批读取）
  let require_all = match frame_flag_word(frame_node, "@requireAll") {
    Some("true") => true
    _ => false
  }
  let explicit = match frame_flag_word(frame_node, "@explicit") {
    Some("true") => true
    _ => false
  }
  let matched = frame_matching(state, subjects, frame_node, require_all)
  let subject_map = frame_subject_map(state)
  for id in matched {
    match subject_map.get(id) {
      Some(node) => {
        let output : ExpandedNode = {
          id: Some(id),
          types: [],
          properties: [],
          reverse_props: [],
          graph: None,
          included: None,
          index: None,
        }
        // keyword 位拷贝（REC "If property is a keyword, add"——展开 IR
        // 中 @type/@index 居专字段）
        for wanted in node.types {
          output.types.push(wanted)
        }
        if node.index is Some(_) {
          output.index = node.index
        }
        // 性质位走查
        for pair in node.properties {
          let property = pair.0
          // explicit 收编门（REC：性质不在帧 + explicit ⇒ MUST NOT 加值
          // ——#t0005 oracle：contributor 弃、title/contains 帧内保）
          let frame_values = frame_property_values(frame_node, property)
          if explicit && frame_values is None {
            continue
          }
          for item in pair.1 {
            match item {
              ExpandedValue::Node(ref_node) => {
                // node reference → 子帧递归（帧缺位 = 合成空帧全嵌；
                // REC "first value from property in frame as frame"）
                let sub_frame : ExpandedNode = match frame_values {
                  Some(fvs) =>
                    match fvs[0] {
                      ExpandedValue::Node(pattern) => pattern
                      _ => frame_empty_pattern()
                    }
                  None => frame_empty_pattern()
                }
                match ref_node.id {
                  Some(ref_id) =>
                    frame_invoke(
                      state,
                      [ref_id],
                      sub_frame,
                      Prop(output, property),
                    )
                  None => ()
                }
              }
              ExpandedValue::Value(_) =>
                frame_output_add(output, property, item)
              ExpandedValue::List(_, ..) =>
                // list 位骨架：整体拷贝（list 内 pattern 递归——t0055-58 批）
                frame_output_add(output, property, item)
            }
          }
        }
        // 帧缺位性质 @preserve 发射（REC：frame 非 keyword 性质（@type
        // 走 types 字段不在列）不 in output ⇒ 性质帧首值判 @omitDefault，
        // 未跳则发 {@preserve: @default 值拷贝 | "@null"}——#t0009 四臂
        // / #t0005 ex:null oracle）。@reverse 臂随 reverse 簇批
        for frame_pair in frame_node.properties {
          let property = frame_pair.0
          if property.get_char(0) is Some('@') {
            continue
          }
          let already = match frame_property_values(output, property) {
            Some(existing) => !existing.is_empty()
            None => false
          }
          if already {
            continue
          }
          let property_frame : ExpandedNode = match frame_pair.1.get(0) {
            Some(ExpandedValue::Node(pattern)) => pattern
            _ => continue
          }
          let omit = match frame_flag_word(property_frame, "@omitDefault") {
            Some("true") => true
            _ => false
          }
          if omit {
            continue
          }
          let preserved : Array[ExpandedValue] = match
            frame_property_values(property_frame, "@default") {
            Some(default_values) => {
              let copy : Array[ExpandedValue] = []
              for v in default_values {
                copy.push(v)
              }
              copy
            }
            None => [literal_of("@null", None)]
          }
          frame_output_add(
            output,
            property,
            ExpandedValue::Node({
              id: None,
              types: [],
              properties: [("@preserve", preserved)],
              reverse_props: [],
              graph: None,
              included: None,
              index: None,
            }),
          )
        }
        frame_parent_add(parent, ExpandedValue::Node(output))
      }
      None => ()
    }
  }
}

///|
/// @preserve 解包（REC frame() 步——compaction 前递归替换）：仅 @preserve
/// 单性质的 id-less 节点摊开为其值组；其余节点/List 深走原位重写。返回
/// 替换后 0..n 值（摊开位父数组重排，原位位恒单值）
fn frame_unwrap_preserve(value : ExpandedValue) -> Array[ExpandedValue] {
  match value {
    ExpandedValue::Node(node) => {
      let is_preserve_wrapper = node.id is None &&
        node.types.is_empty() &&
        node.index is None &&
        node.graph is None &&
        node.included is None &&
        node.properties.length() == 1 &&
        node.properties[0].0 == "@preserve"
      if is_preserve_wrapper {
        let out : Array[ExpandedValue] = []
        for preserved_value in node.properties[0].1 {
          for replaced in frame_unwrap_preserve(preserved_value) {
            out.push(replaced)
          }
        }
        return out
      }
      for pair in node.properties {
        let replaced : Array[ExpandedValue] = []
        for item in pair.1 {
          for rewritten in frame_unwrap_preserve(item) {
            replaced.push(rewritten)
          }
        }
        pair.1.clear()
        for item in replaced {
          pair.1.push(item)
        }
      }
      [ExpandedValue::Node(node)]
    }
    ExpandedValue::List(items, ..) => {
      let replaced : Array[ExpandedValue] = []
      for item in items {
        for rewritten in frame_unwrap_preserve(item) {
          replaced.push(rewritten)
        }
      }
      items.clear()
      for item in replaced {
        items.push(item)
      }
      [value]
    }
    ExpandedValue::Value(_) => [value]
  }
}

///|
/// `"@null"`→null 递归（REC frame() 末步——**compaction 后**；null-only
/// 数组清空留空数组——#t0009 ex:p7 @set oracle；对象位 null 保留——
/// #t0005 ex:null oracle）
fn frame_null_walk(value : JsonValue) -> JsonValue {
  match value {
    JsonValue::String(word) =>
      if word == "@null" {
        JsonValue::Null
      } else {
        value
      }
    JsonValue::Array(items) => {
      let walked : Array[JsonValue] = []
      let mut only_null = true
      for item in items {
        let rewritten = frame_null_walk(item)
        if !(rewritten is JsonValue::Null) {
          only_null = false
        }
        walked.push(rewritten)
      }
      if only_null {
        JsonValue::Array([])
      } else {
        JsonValue::Array(walked)
      }
    }
    JsonValue::Object(pairs) => {
      let walked_pairs : Array[(String, JsonValue)] = []
      for pair in pairs {
        walked_pairs.push((pair.0, frame_null_walk(pair.1)))
      }
      JsonValue::Object(walked_pairs)
    }
    _ => value
  }
}

///|
/// framing 文档入口（J5——spec §8.93 勘定 / §8.94 立桩 / §8.95 首役落码）：
/// ①expand(input) ②F2 同 id 预合并（flatten 同源）③frame 原文 @context
/// 抽取 + 展开（骨架 = 常规展开；frameExpansion 保形批随帧旗簇）④
/// process_context 建 ActiveContext ⑤graph map（Node Map Generation 骨架
/// + frame 顶层 @graph ⇒ @default 否则 @merged）⑥匹配嵌套递归 ⑦prune
/// bnodes（mode≠1.0——tp 簇批）⑧@preserve 替换（发射批同笔）⑨compaction
/// （frame @context，compact_node_jv 复用）⑩@graph 包裹 + @context 回填
/// +"@null"→null（发射批同笔）
pub fn frame_document(
  input_text : String,
  frame_text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let values = match expand_top_values(input_text, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let merge_ctx : MergeCtx = { anon: 0, seen: Map([]), }
  for value in values {
    match nq_merge_same_id(value, merge_ctx, "") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // frame 原文扫读：@context（compaction context + ActiveContext 双用）
  // + 顶层 @graph（frameDefault 判定）
  let frame_json = match parse_json(frame_text) {
    Ok(doc) => doc
    Err(e) => return Err(e)
  }
  let mut frame_inner : JsonValue = frame_json
  let mut has_top_graph = false
  match frame_json {
    JsonValue::Object(pairs) => {
      let mut found : JsonValue? = None
      for pair in pairs {
        if pair.0 is "@context" {
          found = Some(pair.1)
        }
        if pair.0 is "@graph" {
          has_top_graph = true
        }
      }
      match found {
        Some(v) => frame_inner = v
        None => ()
      }
    }
    _ => ()
  }
  // frame 展开走 frameExpansion=true（REC frame() API——frame 文档保形
  // 展开；输入展开恒走原 options）
  let frame_options : JsonLdOptions = {
    base: options.base,
    expand_context: options.expand_context,
    processing_mode: options.processing_mode,
    load_context: options.load_context,
    rdf_direction: options.rdf_direction,
    produce_generalized_rdf: options.produce_generalized_rdf,
    compact_arrays: options.compact_arrays,
    compact_to_relative: options.compact_to_relative,
    frame_expansion: true,
  }
  let frame_expanded = match expand_top_values(frame_text, frame_options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let active = match
    ContextProcessor::process_context(
      StandardExpander::{ },
      initial_context(options),
      frame_inner,
      ContextFlags::element(),
      options,
    ) {
    Ok(context) => context
    Err(e) => return Err(e)
  }
  let state : FrameState = {
    graph_name: if has_top_graph {
      "@default"
    } else {
      "@merged"
    },
    graph_map: Map([]),
    bnode_counter: 0,
  }
  for value in values {
    let _ = frame_register(state, "@default", value)
  }
  // frame 根 pattern：展开首值取 Node（frame 顶必 map；空展开/负例校验
  // 随批——骨架空展开回落空 pattern 全配）
  let frame_root : ExpandedNode = match frame_expanded.get(0) {
    Some(ExpandedValue::Node(pattern)) => pattern
    _ => frame_empty_pattern()
  }
  let results : Array[ExpandedValue] = []
  let subjects = frame_subject_map(state).keys().collect()
  subjects.sort()
  frame_invoke(state, subjects, frame_root, Top(results))
  // ⑧ @preserve 解包（compaction 前——REC frame() 步递归替换）
  let unwrapped : Array[ExpandedValue] = []
  for result in results {
    for rewritten in frame_unwrap_preserve(result) {
      unwrapped.push(rewritten)
    }
  }
  // ⑦ prune bnodes（mode≠1.0）：随 tp 簇批（本批 1.0 例不触）
  // ⑨ compaction（frame @context；compactArrays/compactToRelative 旗透传）
  let compacted_items : Array[JsonValue] = []
  for result in unwrapped {
    match result {
      ExpandedValue::Node(out_node) =>
        match compact_node_jv(out_node, active, options) {
          Ok(jv) => compacted_items.push(frame_null_walk(jv))
          Err(e) => return Err(e)
        }
      _ => ()
    }
  }
  // ⑩ wrap：数组恒 → {@graph: [...]}（omitGraph 缺省 false——空 results
  // 亦包裹，#t0003 oracle `{"@context":…,"@graph":[]}` 勘定修正——役47
  // 骨架的 length()>0 守卫是误判）
  let body_pairs : Array[(String, JsonValue)] = []
  let graph_key = compact_iri_word("@graph", true, false, true, active, options)
  body_pairs.push((graph_key, JsonValue::Array(compacted_items)))
  // @context 原文逐字回填（空 context 不发射——compact_document 同款；
  // t0018 无帧 context 例对拍时校）
  let context_empty = match frame_inner {
    JsonValue::Object(pairs) => pairs.is_empty()
    JsonValue::Null => true
    _ => false
  }
  if !context_empty && body_pairs.length() > 0 {
    body_pairs.insert(0, ("@context", frame_inner))
  }
  // "@null"→null 递归（无发射路径——@preserve 发射批同笔）
  Ok(JsonValue::Object(body_pairs))
}
