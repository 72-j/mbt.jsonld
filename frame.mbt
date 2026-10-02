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
  /// "@default"（frame 顶层 @graph ⇒ frameDefault）| "@merged"（缺省）；
  /// mut（named-graph 递归位换名——§8.103，变异-恢复）
  mut graph_name : String
  /// graph map（REC Node Map Generation 产物）：graph 名 → subject id → 节点
  graph_map : Map[String, Map[String, ExpandedNode]]
  /// 无 id 节点铸号器（flatten_fresh_bnode 同款 "_:bN"；输入标签避撞预扫
  /// 随 bnode 簇批补）
  mut bnode_counter : Int
  /// embedded 旗（REC "copy of state with embedded=true" 的变异-恢复等价
  /// ——DFS 单链无交织面；§8.99 embed 状态机）
  mut embedded : Bool
  /// embed 路径栈（环检测 = 目标 id ∈ 栈；顶位主体入栈、递归推入/弹出）
  embed_stack : Array[String]
  /// 已嵌账（键 = graph|id；**每顶层匹配树重置**——t0014 bnode 两树各嵌
  /// 全形 oracle 定音辖域）
  embedded_map : Map[String, Bool]
  /// @last 前嵌位账（键 = graph|id → (parent 节点, 性质)——替换走性质位
  /// 值组扫描）
  last_locations : Map[String, (ExpandedNode, String)]
  mut probe : String?
}

///|
fn frame_fresh_bnode(state : FrameState) -> String {
  let term = "_:b\{state.bnode_counter}"
  state.bnode_counter += 1
  match state.probe {
    Some(t) => state.probe = Some(t + "MINT " + term + "\n")
    None => ()
  }
  term
}

///|
fn frame_trace(state : FrameState, line : String) -> Unit {
  match state.probe {
    Some(t) => state.probe = Some(t + line + "\n")
    None => ()
  }
}

///|
/// subject map：当前 graph 名下的 subject 集合；"@merged" = 全 graph 并集
/// （REC Merge Node Maps 真语义——同 id 跨图**逐位并**而非整节点替换；
/// t0068 勘定：图序排序迭代保确定序，"@default" 恒先）
fn frame_subject_map(state : FrameState) -> Map[String, ExpandedNode] {
  if state.graph_name == "@merged" {
    let merged : Map[String, ExpandedNode] = Map([])
    let graph_names = state.graph_map.keys().collect()
    graph_names.sort()
    for graph_name in graph_names {
      match state.graph_map.get(graph_name) {
        Some(nodes) =>
          for id, node in nodes {
            match merged.get(id) {
              Some(base) => merged[id] = frame_merged_union(base, node)
              None => merged[id] = node
            }
          }
        None => ()
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
/// @merged 逐位并集（t0068——types 保序去重、properties 同键值列续append
/// 不去重（对齐 jsonld.js merge 语义）、graph/included/reverse 缺位补位、
/// index 缺位补。值与子节点共享引用——framing 对输入树只读，新容器 =
/// 并集载体。t0048 外层裸壳面被本式自然覆盖：壳无位可并，全节点不丢）
fn frame_merged_union(
  base : ExpandedNode,
  extra : ExpandedNode,
) -> ExpandedNode {
  let merged_types : Array[String] = []
  for t in base.types {
    if !merged_types.contains(t) {
      merged_types.push(t)
    }
  }
  for t in extra.types {
    if !merged_types.contains(t) {
      merged_types.push(t)
    }
  }
  let merged_props : Array[(String, Array[ExpandedValue])] = []
  for pair in base.properties {
    merged_props.push((pair.0, pair.1.copy()))
  }
  for pair in extra.properties {
    let mut found = false
    for i in 0..<merged_props.length() {
      if merged_props[i].0 == pair.0 {
        found = true
        for v in pair.1 {
          merged_props[i].1.push(v)
        }
        break
      }
    }
    if !found {
      merged_props.push((pair.0, pair.1.copy()))
    }
  }
  let merged_reverse : Array[(String, Array[ExpandedValue])] = []
  for pair in base.reverse_props {
    merged_reverse.push((pair.0, pair.1.copy()))
  }
  for pair in extra.reverse_props {
    let mut found = false
    for i in 0..<merged_reverse.length() {
      if merged_reverse[i].0 == pair.0 {
        found = true
        for v in pair.1 {
          merged_reverse[i].1.push(v)
        }
        break
      }
    }
    if !found {
      merged_reverse.push((pair.0, pair.1.copy()))
    }
  }
  let merged_graph : Array[ExpandedValue]? = match (base.graph, extra.graph) {
    (Some(graph_a), Some(graph_b)) => {
      let both = graph_a.copy()
      for v in graph_b {
        both.push(v)
      }
      Some(both)
    }
    (Some(graph_a), None) => Some(graph_a.copy())
    (None, Some(graph_b)) => Some(graph_b.copy())
    (None, None) => None
  }
  let merged_included : Array[ExpandedNode]? = match
    (base.included, extra.included) {
    (Some(included_a), Some(included_b)) => {
      let both = included_a.copy()
      for node in included_b {
        both.push(node)
      }
      Some(both)
    }
    (Some(included_a), None) => Some(included_a.copy())
    (None, Some(included_b)) => Some(included_b.copy())
    (None, None) => None
  }
  {
    id: if base.id is Some(_) {
      base.id
    } else {
      extra.id
    },
    types: merged_types,
    properties: merged_props,
    reverse_props: merged_reverse,
    graph: merged_graph,
    included: merged_included,
    index: if base.index is Some(_) {
      base.index
    } else {
      extra.index
    },
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
      // 自身 id 先铸（t0049 oracle 定音——无 id 的图承载节点：图名**复用
      // 自身 id** 一枚，不另铸图名）
      let self_id = match node.id {
        Some(id) =>
          if id == EXPLICIT_NULL_ID {
            frame_fresh_bnode(state)
          } else {
            id
          }
        None => frame_fresh_bnode(state)
      }
      // named graph 内容注册（内容节点属以其 @id 命名的图）
      match node.graph {
        Some(items) => {
          let graph_id = match node.id {
            Some(id) => id
            None => self_id
          }
          for item in items {
            let _ = frame_register(state, graph_id, item)
          }
        }
        None => ()
      }
      // 自身注册**先于性质下走**（后向边勘定——tg003 根因：后向
      // reference 在祖先自注册前递归，把裸引用抢注进图字典，first-wins
      // 随即弃真节点 ⇒ subject map 空壳、匹配全空）。先注册真节点，后向
      // 边命中 contains 即跳过；F2 预合并已保证同 id 全节点单点
      let nodes = match state.graph_map.get(graph_name) {
        Some(existing) => existing
        None => {
          let fresh : Map[String, ExpandedNode] = Map([])
          state.graph_map[graph_name] = fresh
          fresh
        }
      }
      frame_trace(
        state,
        "PLACE [" +
        self_id +
        "] graph=" +
        graph_name +
        " types=" +
        node.types.length().to_string() +
        " props=" +
        node.properties.length().to_string(),
      )
      if !nodes.contains(self_id) {
        nodes[self_id] = node
      } else {
        // 最全者胜（后向边占位勘定二——tg005 根因：后向 reference 先注
        // 册成裸壳，真节点后到被 first-wins 挡外 ⇒ 空壳匹配不上。F2 预
        // 合并保证同 id 至多一个全节点 ⇒ 全节点到即换、裸引用互不换）
        let existing = match nodes.get(self_id) {
          Some(e) => e
          None => node
        }
        let existing_bare = existing.types.is_empty() &&
          existing.properties.is_empty() &&
          existing.reverse_props.is_empty() &&
          existing.graph is None &&
          existing.included is None
        let node_bare = node.types.is_empty() &&
          node.properties.is_empty() &&
          node.reverse_props.is_empty() &&
          node.graph is None &&
          node.included is None
        if existing_bare && !node_bare {
          nodes[self_id] = node
        }
      }
      // 性质位抽取（原位替换为 reference；map 条目 = 同对象，原位变更可见）
      for pair in node.properties {
        for i, item in pair.1 {
          pair.1[i] = frame_register(state, graph_name, item)
        }
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
  /// @reverse 配得数组 / list 递归输出数组（§8.101）
  Values(Array[ExpandedValue])
  /// named graph 递归父位（§8.103——值入节点 graph 槽）
  Graph(ExpandedNode)
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
      // Value 精确同形去重（t0059 oracle——F2 并集把两处同 id 的同名值并
      // 出重复；REC node map 语义值本集；framing 局部去重不动共享合并面）
      match value {
        ExpandedValue::Value(new_lit) =>
          for existing in pair.1 {
            match existing {
              ExpandedValue::Value(old_lit) =>
                if old_lit.value == new_lit.value &&
                  old_lit.datatype == new_lit.datatype &&
                  old_lit.language == new_lit.language {
                  return
                }
              _ => ()
            }
          }
        _ => ()
      }
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
    Values(arr) => arr.push(value)
    Graph(node) =>
      match node.graph {
        Some(items) => items.push(value)
        None => node.graph = Some([value])
      }
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
/// 合成帧（REC："create a new frame using a new map with properties for
/// @embed, @explicit and @requireAll **taken from** embed, explicit and
/// requireAll"——子帧缺位时合成帧继承当前旗——tg007 bookmark 副本 topics
/// 全嵌 oracle 定音：非继承则 @once 化引用）
fn frame_synthesized_pattern(
  embed : EmbedPolicy,
  explicit : Bool,
  require_all : Bool,
) -> ExpandedNode {
  let pattern = frame_empty_pattern()
  let embed_word = match embed {
    Always => "@always"
    Once => "@once"
    Never => "@never"
    Last => "@last"
  }
  pattern.properties.push(("@embed", [literal_of(embed_word, None)]))
  pattern.properties.push(
    ("@explicit", [literal_of(if explicit { "true" } else { "false" }, None)]),
  )
  pattern.properties.push(
    (
      "@requireAll",
      [literal_of(if require_all { "true" } else { "false" }, None)],
    ),
  )
  pattern
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
  let node_id = node_id_of(node)
  // match-none 性质位节点级预检（REC："node does not match if values is
  // not empty and the value of property in frame is match none"——#t0023
  // Sub2 出局 oracle；值缺位不否决，走缺位发射）
  for pair in frame_node.properties {
    if pair.0.get_char(0) is Some('@') {
      continue
    }
    if pair.1.is_empty() && !frame_node_values(node, pair.0).is_empty() {
      return false
    }
  }
  // @id 位硬过滤：pattern 形（frameExpansion 保形——t0032/33）优先，单 IRI
  // 形（id 字段）回落
  let id_patterned = frame_property_values(frame_node, "@id") is Some(_)
  match frame_property_values(frame_node, "@id") {
    Some(id_patterns) => {
      let mut id_match = false
      for pattern in id_patterns {
        match pattern {
          ExpandedValue::Value(lit) =>
            if lit.value == node_id {
              id_match = true
            }
          ExpandedValue::Node(wild) =>
            if frame_is_wildcard_pattern(wild) {
              id_match = true
            }
          _ => ()
        }
      }
      if !id_match {
        return false
      }
    }
    None =>
      match frame_node.id {
        Some(frame_id) => if frame_id != node_id { return false }
        None => ()
      }
  }
  // @type 位硬过滤：pattern 形（IRI 清单任配 / {} 通配须有型 / 空清单
  // match-none 须无型——t0031）优先，types 字段形回落（t0005/t0026）
  let type_patterned = frame_property_values(frame_node, "@type") is Some(_)
  match frame_property_values(frame_node, "@type") {
    Some(type_patterns) => {
      let mut type_match = type_patterns.is_empty() && node.types.is_empty()
      for pattern in type_patterns {
        match pattern {
          ExpandedValue::Value(lit) =>
            if node.types.contains(lit.value) {
              type_match = true
            }
          ExpandedValue::Node(pattern_node) =>
            if frame_is_wildcard_pattern(pattern_node) {
              if !node.types.is_empty() {
                type_match = true
              }
            } else if frame_property_values(pattern_node, "@default") is Some(_) {
              // @type default 对象 = 无条件配（t0064——REC 匹配 default
              // 臂；jsonld.js matchThis=true 不视节点类型有无）
              type_match = true
            }
          _ => ()
        }
      }
      if !type_match {
        return false
      }
    }
    None =>
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
  }
  // 语义位 = 非 @ 键性质 ∪ pattern 形 @id/@type（旗/@default 键不算——REC
  // "no other keywords are considered"；全无 = 帧空/旗-only 即配）
  let has_types_or_id = !frame_node.types.is_empty() || frame_node.id is Some(_)
  let mut has_semantic = id_patterned || type_patterned || has_types_or_id
  for pair in frame_node.properties {
    if !(pair.0.get_char(0) is Some('@')) {
      has_semantic = true
      break
    }
  }
  if !has_semantic {
    return true
  }
  // 性质位记账：@id/@type 到此必已配（计入 any/all）；pattern 递归判余位
  let mut all_match = true
  let mut any_match = id_patterned ||
    type_patterned ||
    !frame_node.types.is_empty() ||
    frame_node.id is Some(_)
  let mut saw_semantic = id_patterned || type_patterned
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
  // match-none（空 pattern 清单）：值缺位 = 配（有值已在节点级预检出局
  // ——t0023 双向 oracle）
  if patterns.is_empty() {
    return values.is_empty()
  }
  for pattern in patterns {
    match pattern {
      ExpandedValue::List(patterns_in_list, ..) =>
        // list pattern 臂（§8.101——t0056-58 any-item-any-pattern 定音；
        // 整表输出不滤）。list-vs-list 交叉，任项配即配
        for item in values {
          match item {
            ExpandedValue::List(items, ..) => {
              let mut list_matched = false
              for one_pattern in patterns_in_list {
                for listitem in items {
                  if frame_list_item_matches(
                      state, one_pattern, listitem, require_all,
                    ) {
                    list_matched = true
                    break
                  }
                }
                if list_matched {
                  break
                }
              }
              if list_matched {
                return true
              }
            }
            _ => ()
          }
        }
      ExpandedValue::Value(pattern_lit) =>
        // 串/词形 pattern = 精确值 pattern（t0036：v/t/l 全等）
        for item in values {
          match item {
            ExpandedValue::Value(lit) =>
              if frame_literal_matches(pattern_lit, lit) {
                return true
              }
            _ => ()
          }
        }
      ExpandedValue::Node(pattern_node) =>
        if frame_is_value_pattern(pattern_node) {
          // 值 pattern（@value/@type/@language 成分——t0037-45）
          for item in values {
            match item {
              ExpandedValue::Value(lit) =>
                if frame_value_pattern_matches(pattern_node, lit) {
                  return true
                }
              _ => ()
            }
          }
        } else {
          let mut has_iri_props = false
          for pp in pattern_node.properties {
            if !(pp.0.get_char(0) is Some('@')) {
              has_iri_props = true
              break
            }
          }
          let has_id_or_type = pattern_node.id is Some(_) ||
            !pattern_node.types.is_empty()
          if !has_iri_props && !has_id_or_type {
            // 通配/默认-only 形：{} 有值即配（t0023 ex:q / t0024）；@-键
            // -only（@default/@旗）恒配——缺位走发射（t0025 requireAll
            // 三节点全配 oracle；#t0009 p4 复验）
            if pattern_node.properties.is_empty() {
              if !values.is_empty() {
                return true
              }
            } else {
              return true
            }
          } else {
            // node pattern 递归：值位 references 的 id 下代匹配非空
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
        }
      _ => ()
    }
  }
  false
}

///|
/// 通配 pattern 判（`{}`——无 id/types/properties 全空）
fn frame_is_wildcard_pattern(pattern_node : ExpandedNode) -> Bool {
  pattern_node.id is None &&
  pattern_node.types.is_empty() &&
  pattern_node.properties.is_empty()
}

///|
/// 值 pattern 判（含 @value/@type/@language 保形键——frameExpansion 值
/// pattern 模式产物）
fn frame_is_value_pattern(pattern_node : ExpandedNode) -> Bool {
  for pair in pattern_node.properties {
    match pair.0 {
      "@value" | "@type" | "@language" => return true
      _ => ()
    }
  }
  false
}

///|
/// 精确值 pattern 配（串 pattern 展开 Value——v/t/l 全等；语言折叠比对）
fn frame_literal_matches(
  pattern : ExpandedLiteral,
  lit : ExpandedLiteral,
) -> Bool {
  let value_ok = pattern.value == lit.value
  let type_ok = match (pattern.datatype, lit.datatype) {
    (Some(a), Some(b)) => a == b
    (None, None) => true
    _ => false
  }
  let lang_ok = match (pattern.language, lit.language) {
    (Some(a), Some(b)) => lang_tag_eq(a, b)
    (None, None) => true
    _ => false
  }
  value_ok && type_ok && lang_ok
}

///|
/// 值 pattern 配（REC Value Pattern Matching——成分缺位 = 值须无该成分
///（t0045 p 位只留 plain oracle）；{} 通配位 = 有成分即配（须值位非空成
/// 分）；空清单 = match-none（值须无成分——t0040/t0041）；清单 = 任配
///（t0042）；语言折叠（t0045 "R"↔"r"））
fn frame_value_pattern_matches(
  pattern_node : ExpandedNode,
  lit : ExpandedLiteral,
) -> Bool {
  // v 位（v1 恒非空 ⇒ 无 @value 键 = 不配）
  let v_ok = match frame_property_values(pattern_node, "@value") {
    None => false
    Some(components) => {
      let mut wildcard = false
      let mut listed = false
      for component in components {
        match component {
          ExpandedValue::Value(component_lit) =>
            if component_lit.value == lit.value {
              listed = true
            }
          ExpandedValue::Node(wild) =>
            if frame_is_wildcard_pattern(wild) {
              wildcard = true
            }
          _ => ()
        }
      }
      wildcard || listed
    }
  }
  // t 位
  let t_ok = match frame_property_values(pattern_node, "@type") {
    None => lit.datatype is None
    Some(components) => {
      let mut wildcard = false
      let mut listed = false
      for component in components {
        match component {
          ExpandedValue::Value(component_lit) =>
            match lit.datatype {
              Some(dt) => if component_lit.value == dt { listed = true }
              None => ()
            }
          ExpandedValue::Node(wild) =>
            if frame_is_wildcard_pattern(wild) {
              wildcard = true
            }
          _ => ()
        }
      }
      (wildcard && lit.datatype is Some(_)) ||
      listed ||
      (lit.datatype is None && components.is_empty())
    }
  }
  // l 位（折叠）
  let l_ok = match frame_property_values(pattern_node, "@language") {
    None => lit.language is None
    Some(components) => {
      let mut wildcard = false
      let mut listed = false
      for component in components {
        match component {
          ExpandedValue::Value(component_lit) =>
            match lit.language {
              Some(tag) =>
                if lang_tag_eq(component_lit.value, tag) {
                  listed = true
                }
              None => ()
            }
          ExpandedValue::Node(wild) =>
            if frame_is_wildcard_pattern(wild) {
              wildcard = true
            }
          _ => ()
        }
      }
      (wildcard && lit.language is Some(_)) ||
      listed ||
      (lit.language is None && components.is_empty())
    }
  }
  v_ok && t_ok && l_ok
}

///|
/// 值位 pattern 过滤（invoke 收值门——t0045 非配值不收）：无 pattern 全收；
/// match-none 不收；精确/值 pattern 按配收；通配/node pattern 位值照收
fn frame_value_kept(
  frame_node : ExpandedNode,
  property : String,
  item : ExpandedValue,
) -> Bool {
  let lit = match item {
    ExpandedValue::Value(value_lit) => value_lit
    _ => return true
  }
  match frame_property_values(frame_node, property) {
    None => true
    Some(patterns) =>
      match patterns.get(0) {
        None => false
        Some(ExpandedValue::Value(pattern_lit)) =>
          frame_literal_matches(pattern_lit, lit)
        Some(ExpandedValue::Node(pattern_node)) =>
          if frame_is_value_pattern(pattern_node) {
            frame_value_pattern_matches(pattern_node, lit)
          } else {
            true
          }
        Some(_) => true
      }
  }
}

///|
/// list 项配（§8.101——值字面精确/值 pattern/node pattern 递归/通配）
fn frame_list_item_matches(
  state : FrameState,
  pattern : ExpandedValue,
  listitem : ExpandedValue,
  require_all : Bool,
) -> Bool {
  match pattern {
    ExpandedValue::Value(pattern_lit) =>
      match listitem {
        ExpandedValue::Value(lit) => frame_literal_matches(pattern_lit, lit)
        _ => false
      }
    ExpandedValue::Node(pattern_node) =>
      if frame_is_value_pattern(pattern_node) {
        match listitem {
          ExpandedValue::Value(lit) =>
            frame_value_pattern_matches(pattern_node, lit)
          _ => false
        }
      } else if frame_is_wildcard_pattern(pattern_node) {
        true
      } else {
        match listitem {
          ExpandedValue::Node(ref_node) =>
            match ref_node.id {
              Some(ref_id) =>
                !frame_matching(state, [ref_id], pattern_node, require_all).is_empty()
              None => false
            }
          _ => false
        }
      }
    ExpandedValue::List(_, ..) => false
  }
}

///|
/// embed 策略（§8.99 状态机——帧旗 @embed per-invocation 读帧；词形归一：
/// @always→Always / @once|true|缺省→Once / @never|false→Never / @last→Last
/// ——Last 仅 1.0（t0059 oracle）；值域校验随负例批）
priv enum EmbedPolicy {
  Always
  Once
  Never
  Last
}

///|
fn frame_embed_policy(frame_node : ExpandedNode) -> EmbedPolicy {
  match frame_flag_word(frame_node, "@embed") {
    Some("@always") => Always
    Some("@never") => Never
    Some("false") => Never
    Some("@last") => Last
    _ => Once
  }
}

///|
/// node reference 装配（{@id} 形——embed 三支的引用发射）
fn frame_reference(id : String) -> ExpandedValue {
  ExpandedValue::Node({
    id: Some(id),
    types: [],
    properties: [],
    reverse_props: [],
    graph: None,
    included: None,
    index: None,
  })
}

///|
/// @last 前嵌位替换：性质位值组中 id 全形节点原地换引用（t0059 oracle——
/// "replaces previous embed values with node reference"）
fn frame_replace_embed_with_ref(
  parent_node : ExpandedNode,
  property : String,
  id : String,
) -> Unit {
  for pair in parent_node.properties {
    if pair.0 == property {
      for i, item in pair.1 {
        match item {
          ExpandedValue::Node(embedded) =>
            match embedded.id {
              Some(embedded_id) =>
                if embedded_id == id {
                  pair.1[i] = frame_reference(id)
                }
              None => ()
            }
          _ => ()
        }
      }
      return
    }
  }
}

///|
/// 输入 bnode 重铸号（役52——tp021/t0015 oracle：输入 bnode 标签全换新
/// _:bN——节点 id 位与 @type 位同一映射保持一致；seen 表跨树一致；铸号
/// 器与 frame_register 共享（state 先建）⇒ 零碰撞）
fn frame_relabel_bnodes(
  state : FrameState,
  value : ExpandedValue,
  seen : Map[String, String],
) -> Unit {
  match value {
    ExpandedValue::Node(n) => {
      match n.id {
        Some(id) =>
          if nq_term_is_bnode(id) {
            let fresh = match seen.get(id) {
              Some(f) => f
              None => {
                let f = frame_fresh_bnode(state)
                // fresh 标签身份自映（键统一勘定——已铸标签再遇 = 命中自身，
                // 不再二次铸号改写共享节点 ⇒ 双键分裂根因封堵）
                seen[f] = f
                seen[id] = f
                f
              }
            }
            n.id = Some(fresh)
          }
        None => ()
      }
      for i, t in n.types {
        if nq_term_is_bnode(t) {
          let fresh = match seen.get(t) {
            Some(f) => f
            None => {
              let f = frame_fresh_bnode(state)
              seen[f] = f
              seen[t] = f
              f
            }
          }
          n.types[i] = fresh
        }
      }
      for pair in n.properties {
        for v in pair.1 {
          frame_relabel_bnodes(state, v, seen)
        }
      }
      match n.graph {
        Some(items) =>
          for item in items {
            frame_relabel_bnodes(state, item, seen)
          }
        None => ()
      }
      match n.included {
        Some(incs) =>
          for inc in incs {
            frame_relabel_bnodes(state, ExpandedValue::Node(inc), seen)
          }
        None => ()
      }
    }
    ExpandedValue::List(items, ..) =>
      for item in items {
        frame_relabel_bnodes(state, item, seen)
      }
    ExpandedValue::Value(_) => ()
  }
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
  // 帧旗覆写（REC 步 2——帧内 @requireAll/@explicit/@embed 覆写本帧子树；
  // 词形 "true"/"false" 自 frameExpansion 保形）
  let require_all = match frame_flag_word(frame_node, "@requireAll") {
    Some("true") => true
    _ => false
  }
  let explicit = match frame_flag_word(frame_node, "@explicit") {
    Some("true") => true
    _ => false
  }
  let embed = frame_embed_policy(frame_node)
  let matched = frame_matching(state, subjects, frame_node, require_all)
  let subject_map = frame_subject_map(state)
  for id in matched {
    match subject_map.get(id) {
      Some(node) => {
        // @once/@last 辖域 = 每顶层匹配树（t0014 bnode 两树各嵌全形 oracle
        // ——顶位进树前重置三账）
        match parent {
          Top(_) => {
            state.embedded_map.clear()
            state.embed_stack.clear()
            state.last_locations.clear()
          }
          _ => ()
        }
        let output : ExpandedNode = {
          id: Some(id),
          types: [],
          properties: [],
          reverse_props: [],
          graph: None,
          included: None,
          index: None,
        }
        // embed 三支（REC Framing Algorithm 序；§8.99 状态机）
        let embed_key = state.graph_name + "|" + id
        match state.probe {
          Some(t) => {
            let line = "TURN id=" +
              id +
              " map=" +
              state.embedded_map.length().to_string() +
              " stack=" +
              state.embed_stack.length().to_string() +
              "\n"
            state.probe = Some(t + line)
          }
          None => ()
        }
        // 支一：顶位（embedded=false）且已嵌 ⇒ 跳过不添（named-graph 递归
        // 位——本批不触，graph 批落）
        if !state.embedded && state.embedded_map.contains(embed_key) {
          continue
        }
        // 支二/三：递归位（embedded=true）
        if state.embedded {
          let circular = state.embed_stack.contains(id)
          if embed is Never || circular {
            match state.probe {
              Some(t) => {
                let line = "  REF(never-or-circ) id=" +
                  id +
                  " circ=" +
                  circular.to_string() +
                  "\n"
                state.probe = Some(t + line)
              }
              None => ()
            }
            // 恒引用 / 环上 ⇒ {@id} 引用发射（t0011/30 never、g003 环 oracle）
            frame_parent_add(parent, frame_reference(id))
            continue
          }
          if embed is Once && state.embedded_map.contains(embed_key) {
            // 树内已嵌 ⇒ 引用（前嵌留全形；t0013 oracle）
            frame_parent_add(parent, frame_reference(id))
            continue
          }
        }
        // @last：前嵌位原地换引用（t0059 oracle），新位全嵌
        if embed is Last {
          match state.last_locations.get(embed_key) {
            Some((old_parent, old_property)) =>
              frame_replace_embed_with_ref(old_parent, old_property, id)
            None => ()
          }
        }
        // named graph 递归（§8.103——REC："If graph map in state has an
        // entry for id"：帧无 @graph ⇒ 递归除非 graphName=@merged；帧有
        // @graph ⇒ 子帧 = 首值（缺 ⇒ 合成），id 为 @merged/@default 不递归；
        // 递归 = graphName=id + embedded=false + 子 subjects + Graph 父位）
        if state.graph_map.contains(id) {
          let frame_has_graph = frame_node.graph is Some(_)
          let mut recurse = true
          let graph_subframe : ExpandedNode = if !frame_has_graph {
            if state.graph_name == "@merged" {
              recurse = false
              frame_empty_pattern()
            } else {
              frame_synthesized_pattern(embed, explicit, require_all)
            }
          } else {
            match frame_node.graph {
              Some(items) =>
                match items.get(0) {
                  Some(ExpandedValue::Node(pattern)) => pattern
                  _ => frame_synthesized_pattern(embed, explicit, require_all)
                }
              None => frame_synthesized_pattern(embed, explicit, require_all)
            }
          }
          if recurse {
            let saved_graph_name = state.graph_name
            let saved_embedded = state.embedded
            state.graph_name = id
            state.embedded = false
            let graph_subjects = match state.graph_map.get(id) {
              Some(nodes) => {
                let keys = nodes.keys().collect()
                keys.sort()
                keys
              }
              None => []
            }
            frame_invoke(state, graph_subjects, graph_subframe, Graph(output))
            state.embedded = saved_embedded
            state.graph_name = saved_graph_name
          }
        }
        // @included 帧（REC 步 6——同 subjects 复用、embedded=false 拷贝态、
        // output 复用为父、active = @included；子帧 = @included 首值节点
        // pattern。tin01-03 面——included 键别名/@container @set 随压缩面）
        match frame_node.included {
          Some(included_items) =>
            match included_items.get(0) {
              Some(included_pattern) => {
                let saved_embedded_included = state.embedded
                state.embedded = false
                frame_invoke(
                  state,
                  subjects,
                  included_pattern,
                  Prop(output, "@included"),
                )
                state.embedded = saved_embedded_included
              }
              None => ()
            }
          None => ()
        }
        state.embed_stack.push(id)
        // keyword 位拷贝（REC "If property is a keyword, add"——展开 IR
        // 中 @type/@index 居专字段）；types 去重（F2 并集重复——t0057
        // "ex:T","ex:T" oracle；匹配 contains 语义本集）
        for wanted in node.types {
          if !output.types.contains(wanted) {
            output.types.push(wanted)
          }
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
                      _ =>
                        frame_synthesized_pattern(embed, explicit, require_all)
                    }
                  None =>
                    frame_synthesized_pattern(embed, explicit, require_all)
                }
                match ref_node.id {
                  Some(ref_id) => {
                    // REC "copy of state with embedded=true"——变异-恢复
                    // 等价（DFS 单链）
                    let saved_embedded = state.embedded
                    state.embedded = true
                    frame_invoke(
                      state,
                      [ref_id],
                      sub_frame,
                      Prop(output, property),
                    )
                    state.embedded = saved_embedded
                  }
                  None => ()
                }
              }
              ExpandedValue::Value(_) =>
                // 值位 pattern 过滤（值 pattern 精确/通配/match-none——
                // t0036-45/t0023 判定面）
                if frame_value_kept(frame_node, property, item) {
                  // 语言 pattern 配值小写规范形（t0045 oracle——REC Value
                  // Pattern Matching 双侧小写规范的输出侧显形；拷贝发，
                  // 不扰 subject map 原值）
                  let mut lowered = false
                  match frame_property_values(frame_node, property) {
                    Some(patterns) =>
                      match patterns.get(0) {
                        Some(ExpandedValue::Node(pattern_node)) =>
                          if frame_is_value_pattern(pattern_node) &&
                            frame_property_values(pattern_node, "@language")
                            is Some(_) {
                            match item {
                              ExpandedValue::Value(value_lit) => {
                                frame_output_add(
                                  output,
                                  property,
                                  ExpandedValue::Value(
                                    frame_language_lowered_lit(value_lit),
                                  ),
                                )
                                lowered = true
                              }
                              _ => ()
                            }
                          }
                        Some(ExpandedValue::Value(pattern_lit)) =>
                          if pattern_lit.language is Some(_) {
                            match item {
                              ExpandedValue::Value(value_lit) => {
                                frame_output_add(
                                  output,
                                  property,
                                  ExpandedValue::Value(
                                    frame_language_lowered_lit(value_lit),
                                  ),
                                )
                                lowered = true
                              }
                              _ => ()
                            }
                          }
                        _ => ()
                      }
                    None => ()
                  }
                  if !lowered {
                    frame_output_add(output, property, item)
                  }
                }
              ExpandedValue::List(items, ..) => {
                // list 位（§8.101——REC 逐项：ref 递归嵌（子帧 = 帧 list
                // pattern 首值，缺 ⇒ 合成空帧）；值项收；t0055-58）
                let list_patterns : Array[ExpandedValue] = match
                  frame_property_values(frame_node, property) {
                  Some(fvs) =>
                    match fvs.get(0) {
                      Some(ExpandedValue::List(ps, ..)) => ps
                      _ => []
                    }
                  None => []
                }
                let out_items : Array[ExpandedValue] = []
                frame_trace(
                  state,
                  "  LIST " +
                  property +
                  " patterns=" +
                  list_patterns.length().to_string() +
                  " items=" +
                  items.length().to_string(),
                )
                for listitem in items {
                  match listitem {
                    ExpandedValue::Node(ref_node) =>
                      match ref_node.id {
                        Some(ref_id) => {
                          // 子帧 = 帧 list pattern 首个 node pattern；pattern
                          // 全为值 pattern ⇒ 节点项不配不收（t0057 node2
                          // oracle——值 pattern 不嵌节点）；pattern 缺 ⇒ 合成
                          // 帧继承旗（t0055）
                          let mut node_pattern : ExpandedNode? = None
                          for one_pattern in list_patterns {
                            match one_pattern {
                              ExpandedValue::Node(pn) =>
                                if !frame_is_value_pattern(pn) {
                                  node_pattern = Some(pn)
                                  break
                                }
                              _ => ()
                            }
                          }
                          match node_pattern {
                            Some(_) =>
                              frame_trace(
                                state,
                                "  LISTITEM node-embed " + ref_id,
                              )
                            None =>
                              if list_patterns.is_empty() {
                                frame_trace(
                                  state,
                                  "  LISTITEM synth-embed " + ref_id,
                                )
                              } else {
                                frame_trace(state, "  LISTITEM DROP " + ref_id)
                              }
                          }
                          let sub_frame : ExpandedNode = match node_pattern {
                            Some(pattern) => pattern
                            None =>
                              if list_patterns.is_empty() {
                                frame_synthesized_pattern(
                                  embed, explicit, require_all,
                                )
                              } else {
                                continue
                              }
                          }
                          let saved_embedded = state.embedded
                          state.embedded = true
                          frame_invoke(
                            state,
                            [ref_id],
                            sub_frame,
                            Values(out_items),
                          )
                          state.embedded = saved_embedded
                        }
                        None => ()
                      }
                    ExpandedValue::Value(_) => out_items.push(listitem)
                    _ => out_items.push(listitem)
                  }
                }
                match state.probe {
                  Some(t) => {
                    let n_s = StringBuilder()
                    for oi in out_items {
                      match oi {
                        ExpandedValue::Value(lit) => {
                          n_s.write_string("V(")
                          n_s.write_string(lit.value)
                          n_s.write_string(") ")
                        }
                        ExpandedValue::Node(nn) => {
                          n_s.write_string("N(")
                          n_s.write_string(probe_id_text(nn))
                          n_s.write_string(") ")
                        }
                        ExpandedValue::List(_, ..) => n_s.write_string("L ")
                      }
                    }
                    state.probe = Some(
                      t +
                      "  LIST-OUT " +
                      property +
                      " n=" +
                      out_items.length().to_string() +
                      " [" +
                      n_s.to_string() +
                      "]\n",
                    )
                  }
                  None => ()
                }
                frame_output_add(
                  output,
                  property,
                  ExpandedValue::List(out_items, index=None),
                )
              }
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
            // @type default 注入（t0064——jsonld.js "allow through default
            // types"：节点无型时帧 @type default IRI 即其型；有型 = 已在
            // output 不注入。expanded 形 Node pattern 携 @default IRI）
            if property is "@type" && output.types.is_empty() {
              for type_value in frame_pair.1 {
                match type_value {
                  ExpandedValue::Node(pattern_node) =>
                    match frame_property_values(pattern_node, "@default") {
                      Some(default_values) =>
                        match default_values.get(0) {
                          Some(ExpandedValue::Value(lit)) =>
                            if !output.types.contains(lit.value) {
                              output.types.push(lit.value)
                            }
                          _ => ()
                        }
                      None => ()
                    }
                  _ => ()
                }
              }
            }
            continue
          }
          let already = match frame_property_values(output, property) {
            Some(existing) => !existing.is_empty()
            None => false
          }
          if already {
            continue
          }
          // 性质帧：pattern 首值；match-none 形（空清单——t0023 ex:p）=
          // 无帧（无 @default/@omitDefault 可读 ⇒ 发 "@null"）
          let property_frame : ExpandedNode? = match frame_pair.1.get(0) {
            Some(ExpandedValue::Node(pattern)) => Some(pattern)
            _ => None
          }
          let omit = match property_frame {
            Some(pf) => frame_flag_word(pf, "@omitDefault") is Some("true")
            None => false
          }
          if omit {
            continue
          }
          let preserved : Array[ExpandedValue] = match property_frame {
            Some(pf) =>
              match frame_property_values(pf, "@default") {
                Some(default_values) => {
                  let copy : Array[ExpandedValue] = []
                  for v in default_values {
                    copy.push(v)
                  }
                  copy
                }
                None => [literal_of("@null", None)]
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
        // @reverse 臂（§8.101——flattened subjects 反扫：正性质 rev_prop
        // 含指向 id 之 reference 者入配得数组；帧侧 reverse_props 汇流
        // 字面键与别名 term——t0028/29）
        let reverse_subjects = subject_map.keys().collect()
        reverse_subjects.sort()
        for rev_pair in frame_node.reverse_props {
          let rev_prop = rev_pair.0
          let sub_frame : ExpandedNode = match rev_pair.1.get(0) {
            Some(ExpandedValue::Node(pattern)) => pattern
            _ => frame_empty_pattern()
          }
          let rev_items : Array[ExpandedValue] = []
          for other_id in reverse_subjects {
            if other_id == id {
              continue
            }
            match subject_map.get(other_id) {
              Some(other_node) => {
                let mut points = false
                for v in frame_node_values(other_node, rev_prop) {
                  match v {
                    ExpandedValue::Node(ref_node) =>
                      match ref_node.id {
                        Some(ref_id) => if ref_id == id { points = true }
                        None => ()
                      }
                    _ => ()
                  }
                }
                if points {
                  let saved_embedded = state.embedded
                  state.embedded = true
                  frame_invoke(state, [other_id], sub_frame, Values(rev_items))
                  state.embedded = saved_embedded
                }
              }
              None => ()
            }
          }
          output.reverse_props.push((rev_prop, rev_items))
        }
        frame_parent_add(parent, ExpandedValue::Node(output))
        let _ = state.embed_stack.pop()
        state.embedded_map[embed_key] = true
        match parent {
          Prop(parent_node, parent_property) =>
            if embed is Last {
              state.last_locations[embed_key] = (parent_node, parent_property)
            }
          _ => ()
        }
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
/// 语言标签小写（ASCII 折叠——lang_tag_eq 同族；语言子序列恒 ASCII）
fn frame_lower_tag(tag : String) -> String {
  let builder = StringBuilder()
  for c in tag {
    builder.write_char(ascii_fold_lower(c).unsafe_to_char())
  }
  builder.to_string()
}

///|
/// 语言小写规范值拷贝（framing 发射位——不扰 subject map 原值）
fn frame_language_lowered_lit(lit : ExpandedLiteral) -> ExpandedLiteral {
  {
    value: lit.value,
    datatype: lit.datatype,
    language: match lit.language {
      Some(tag) => Some(frame_lower_tag(tag))
      None => None
    },
    direction: lit.direction,
    raw: lit.raw,
    index: lit.index,
    included: lit.included,
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
  // 帧无 @context ⇒ compaction context = 空 map（t0018 勘定——原样落整帧
  // 对象会被 process_context 当 context 处理而炸：@type 数组项即 invalid
  // context entry）
  let mut frame_inner : JsonValue = JsonValue::Object([])
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
    omit_graph: false,
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
    embedded: false,
    embed_stack: [],
    embedded_map: Map([]),
    last_locations: Map([]),
    probe: None,
  }
  // 输入 bnode 重铸号（先于注册——tp021/t0015 面）
  let relabel_seen : Map[String, String] = Map([])
  for value in values {
    frame_relabel_bnodes(state, value, relabel_seen)
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
  // ⑦ prune bnodes（REC——mode≠1.0：仅现一次于性质值位的 bnode @id 摘除
  // ——tp 族 + t0056 id-less 节点面；0 次现（无值位引用）亦摘）
  let is_10 = match options.processing_mode {
    JsonLd10 => true
    JsonLd11 => false
  }
  if !is_10 {
    let counts : Map[String, Int] = Map([])
    fn count_values(value : ExpandedValue) -> Unit {
      match value {
        ExpandedValue::Node(n) => {
          match n.id {
            Some(id) =>
              if nq_term_is_bnode(id) {
                counts[id] = counts.get(id).unwrap_or(0) + 1
              }
            None => ()
          }
          // @type 位 bnode 引用同计入（tp021 oracle——_:b0 被 republic 的
          // @type 引用 + 自身 @id = 2 ⇒ 不摘）
          for t in n.types {
            if nq_term_is_bnode(t) {
              counts[t] = counts.get(t).unwrap_or(0) + 1
            }
          }
          for pair in n.properties {
            for v in pair.1 {
              count_values(v)
            }
          }
          match n.graph {
            Some(items) =>
              for item in items {
                count_values(item)
              }
            None => ()
          }
        }
        ExpandedValue::List(items, ..) =>
          for item in items {
            count_values(item)
          }
        ExpandedValue::Value(_) => ()
      }
    }
    for result in results {
      match result {
        ExpandedValue::Node(n) => {
          // 自身 @id 计入（tp020 oracle 定音——top 步骤 bnode 两处现
          // （自身 @id + instructions 值位）⇒ 不摘；t0056 无值位引用者
          // 计 1 ⇒ 摘）
          match n.id {
            Some(id) =>
              if nq_term_is_bnode(id) {
                counts[id] = counts.get(id).unwrap_or(0) + 1
              }
            None => ()
          }
          for pair in n.properties {
            for v in pair.1 {
              count_values(v)
            }
          }
        }
        _ => ()
      }
    }
    fn prune_ids(value : ExpandedValue) -> Unit {
      match value {
        ExpandedValue::Node(n) => {
          match n.id {
            Some(id) =>
              if nq_term_is_bnode(id) && counts.get(id).unwrap_or(0) <= 1 {
                n.id = None
              }
            None => ()
          }
          for pair in n.properties {
            for v in pair.1 {
              prune_ids(v)
            }
          }
          match n.graph {
            Some(items) =>
              for item in items {
                prune_ids(item)
              }
            None => ()
          }
        }
        ExpandedValue::List(items, ..) =>
          for item in items {
            prune_ids(item)
          }
        ExpandedValue::Value(_) => ()
      }
    }
    for result in results {
      prune_ids(result)
    }
  }
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
  // ⑩ wrap 三分（oracle 规则——1.0 恒 @graph 包裹：t0001/02/04/05/09；
  // 1.1：空 ⇒ `@graph:[]`（t0003）、单 ⇒ 解包直出（t0023/26/31/32/34/35）、
  // 多 ⇒ 包裹（t0033）——1.1 单解包 = compaction compactArrays 单节点
  // 解包行为经 frame() 管线的显形）
  let body_pairs : Array[(String, JsonValue)] = []
  let is_10 = match options.processing_mode {
    JsonLd10 => true
    JsonLd11 => false
  }
  if compacted_items.length() == 1 && !is_10 {
    match compacted_items[0] {
      JsonValue::Object(pairs) =>
        for pair in pairs {
          body_pairs.push(pair)
        }
      other => {
        let graph_key = compact_iri_word(
          "@graph", true, false, true, active, options,
        )
        body_pairs.push((graph_key, JsonValue::Array([other])))
      }
    }
  } else {
    let graph_key = compact_iri_word(
      "@graph", true, false, true, active, options,
    )
    body_pairs.push((graph_key, JsonValue::Array(compacted_items)))
  }
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

///|
/// framing 调试入口（役52 诊断面——tp046/t0015 判定链直取；收官时裁去
/// 或转正由用户定）：管线复刻 frame_document（probe 位开），返回 TURN/
/// REF 判定追迹 + 结果树形貌。与 frame_document 的镜像同步责任在改二者
/// 的同一笔（debug 面漂移不伤正确性，只伤追迹保真）。
/// （役53 勘误注：本轮实证镜像曾漂移——debug 用原 options 展开帧、生产
/// 用 frame_expansion=true，追迹据此误导「pre-compact 正确」勘一轮；已
/// 对齐 frame_options 旗 + RESULTS 段升级 List 内容直出。）
pub fn frame_debug(
  input_text : String,
  frame_text : String,
  options : JsonLdOptions,
) -> String {
  let trace = StringBuilder()
  let values = match expand_top_values(input_text, options) {
    Ok(v) => {
      trace.write_string("top values: " + v.length().to_string() + "\n")
      v
    }
    Err(e) => return "expand err: " + debug_show_error(e)
  }
  let merge_ctx : MergeCtx = { anon: 0, seen: Map([]), }
  for value in values {
    let _ = nq_merge_same_id(value, merge_ctx, "")
  }
  trace.write_string("after merge+relabel+register\n")
  let state : FrameState = {
    graph_name: if has_top_level_graph(frame_text) {
      "@default"
    } else {
      "@merged"
    },
    graph_map: Map([]),
    bnode_counter: 0,
    embedded: false,
    embed_stack: [],
    embedded_map: Map([]),
    last_locations: Map([]),
    probe: Some(""),
  }
  let relabel_seen : Map[String, String] = Map([])
  for value in values {
    frame_relabel_bnodes(state, value, relabel_seen)
  }
  for value in values {
    let _ = frame_register(state, "@default", value)
  }
  let sm = frame_subject_map(state)
  let keys = sm.keys().collect()
  keys.sort()
  for k in keys {
    match sm.get(k) {
      Some(n) => {
        trace.write_string(
          "[" +
          k +
          "] types=" +
          n.types.length().to_string() +
          " props=" +
          n.properties.length().to_string() +
          "\n",
        )
        for pair in n.properties {
          for v in pair.1 {
            match v {
              ExpandedValue::Node(c) =>
                trace.write_string(
                  "    " +
                  pair.0 +
                  " -> node [" +
                  probe_id_text(c) +
                  "] types=" +
                  c.types.length().to_string() +
                  " props=" +
                  c.properties.length().to_string() +
                  "\n",
                )
              ExpandedValue::Value(lit) =>
                trace.write_string(
                  "    " + pair.0 + " -> value \"" + lit.value + "\"\n",
                )
              ExpandedValue::List(_, ..) =>
                trace.write_string("    " + pair.0 + " -> list\n")
            }
          }
        }
      }
      None => ()
    }
  }
  // 帧展开旗对齐生产（役53 勘误——frame_expansion=true，镜像漂移修）
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
    omit_graph: false,
  }
  let frame_expanded = match expand_top_values(frame_text, frame_options) {
    Ok(v) => v
    Err(e) => return "frame expand err: " + debug_show_error(e)
  }
  let frame_root : ExpandedNode = match frame_expanded.get(0) {
    Some(ExpandedValue::Node(pattern)) => pattern
    _ => frame_empty_pattern()
  }
  let results : Array[ExpandedValue] = []
  frame_invoke(state, keys, frame_root, Top(results))
  let probe_dump = match state.probe {
    Some(t) => t
    None => "(none)"
  }
  trace.write_string("TURN/REF TRACE\n" + probe_dump + "\n")
  trace.write_string("RESULTS\n")
  for r in results {
    match r {
      ExpandedValue::Node(n) => {
        trace.write_string(
          "  top [" +
          probe_id_text(n) +
          "] types=" +
          n.types.length().to_string() +
          " props=" +
          n.properties.length().to_string() +
          "\n",
        )
        for pair in n.properties {
          for v in pair.1 {
            trace.write_string(
              "    " + pair.0 + " -> " + probe_value_text(v) + "\n",
            )
          }
        }
      }
      _ => trace.write_string("  top non-node\n")
    }
  }
  trace.to_string()
}

///|
/// 值位形貌（debug 面——List 递归展内容，幽灵二分用）
fn probe_value_text(v : ExpandedValue) -> String {
  let buf = StringBuilder()
  fn walk(depth : Int, value : ExpandedValue) -> Unit {
    match value {
      ExpandedValue::Node(c) => {
        buf.write_string(
          "N[" + probe_id_text(c) + "] t=" + c.types.length().to_string(),
        )
        if depth > 0 {
          buf.write_string("{")
          for pair in c.properties {
            for item in pair.1 {
              buf.write_string(pair.0 + "=")
              walk(depth - 1, item)
              buf.write_string(" ")
            }
          }
          buf.write_string("}")
        }
      }
      ExpandedValue::Value(lit) => buf.write_string("V(" + lit.value + ")")
      ExpandedValue::List(items, ..) => {
        buf.write_string("L[")
        for item in items {
          walk(depth, item)
          buf.write_string(" ")
        }
        buf.write_string("]")
      }
    }
  }
  walk(1, v)
  buf.to_string()
}

///|
fn probe_id_text(n : ExpandedNode) -> String {
  match n.id {
    Some(i) => i
    None => "None"
  }
}

///|
fn debug_show_error(e : JsonLdError) -> String {
  match e {
    JsonLdError::Unsupported(msg) => "unsupported: " + msg
    JsonLdError::InvalidValue(msg) => "invalid value: " + msg
    JsonLdError::Syntax(msg) => "syntax: " + msg
    JsonLdError::InvalidContext(msg) => "invalid context: " + msg
    JsonLdError::InvalidIri(msg) => "invalid iri: " + msg
    JsonLdError::InvalidList(msg) => "invalid list: " + msg
    JsonLdError::ContextOverflow(msg) => "context overflow: " + msg
  }
}

///|
/// 帧顶层 @graph 判定（frame_debug 用——原文直查）
fn has_top_level_graph(frame_text : String) -> Bool {
  match parse_json(frame_text) {
    Ok(JsonValue::Object(pairs)) => {
      let mut has = false
      for pair in pairs {
        if pair.0 is "@graph" {
          has = true
        }
      }
      has
    }
    _ => false
  }
}
