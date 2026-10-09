///|
/// JSON-LD expansion 引擎：gen 调度面（gen.mbt）+ 手写钩子（expand_standard.mbt）的装配层。
/// 引擎只做调度与顶层形态（解析 → 入口分派 → 顶层展开 → 序列化）；语义全部在钩子。
/// J2 首件：#t0001 端到端（deferred → plain，见 suite_expand_test.mbt）。

///|
/// 元素形态（调度词表：scalar/array/object；null 计入 scalar）
fn shape_of(element : JsonValue) -> String {
  match element {
    JsonValue::Array(_) => "array"
    JsonValue::Object(_) => "object"
    _ => "scalar"
  }
}

///|
/// 初始 active context（t0001 片：terms 空、base 取 options）
fn initial_context(options : JsonLdOptions) -> ActiveContext {
  {
    base: options.base,
    vocab: None,
    terms: Map([]),
    previous: None,
    default_language: None,
    default_direction: None,
    compact_by_iri: None,
    compact_reverse: None,
    compact_prefixes: None,
  }
}

///|

///|
/// 顶层展开核心（J3.1 抽取——expand_document / to_rdf_document 共用）：JSON
/// 文本 → 顶层存活元素（ExpandedValue）。选择规则 = serialize_top 同款：顶层
/// 值对象即弃（#t0045）/ free-floating 节点即弃（#t0001）/ 裸 @graph 根节点
/// 表面化为图内容（#t0009/#t0021——toRdf 侧即默认图，REC §6.3）。
fn expand_top_values(
  text : String,
  options : JsonLdOptions,
) -> Result[Array[ExpandedValue], JsonLdError] {
  let element = match parse_json(text) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let expander = StandardExpander::{ }
  let active = match options.expand_context {
    // expandContext 选项（#t0077 oracle）：外部 context 先于文档处理；
    // context 文档 = {"@context": inner} → 解包后处理
    Some(context_value) => {
      let inner = match context_value {
        JsonValue::Object(pairs) => {
          let mut found : JsonValue? = None
          for pair in pairs {
            if pair.0 is "@context" {
              found = Some(pair.1)
            }
          }
          found
        }
        _ => None
      }
      match inner {
        Some(context_json) =>
          match
            ContextProcessor::process_context(
              StandardExpander::{ },
              initial_context(options),
              context_json,
              ContextFlags::element(),
              options,
            ) {
            Ok(context) => context
            Err(e) => return Err(e)
          }
        None => initial_context(options)
      }
    }
    None => initial_context(options)
  }
  let out : Array[ExpandedValue] = []
  match shape_of(element) {
    "array" => {
      let items = match element {
        JsonValue::Array(items) => items
        _ => return Err(JsonLdError::InvalidValue("shape mismatch: array"))
      }
      for item in items {
        let step = match JsonLdStep::dispatch(ExpansionEntry, shape_of(item)) {
          Some(step) => step
          None => continue
        }
        let expanded = match step {
          ExpansionExpandObject =>
            StandardExpander::expand_object(
              expander,
              active,
              item,
              None,
              options,
            )
          ExpansionExpandValue =>
            StandardExpander::expand_value(expander, active, item, None).map(fn(
              v,
            ) {
              Some(v)
            })
          ExpansionExpandArray =>
            return Err(JsonLdError::Unsupported("nested array at top pending"))
          _ => continue
        }
        match expanded {
          Ok(Some(value)) =>
            // 数组成员位非根（te004 oracle）——仅@graph 包裹保留
            push_top_value(
              out,
              value,
              frame_expansion=options.frame_expansion,
              root=false,
            )
          Ok(None) => ()
          Err(e) => return Err(e)
        }
      }
    }
    "object" => {
      let expanded = StandardExpander::expand_object(
        expander,
        active,
        element,
        None,
        options,
      )
      match expanded {
        Ok(Some(value)) =>
          push_top_value(out, value, frame_expansion=options.frame_expansion)
        Ok(None) => ()
        Err(e) => return Err(e)
      }
    }
    _ => {
      let expanded = StandardExpander::expand_value(
        expander,
        active,
        element,
        None,
      )
      match expanded {
        Ok(value) =>
          push_top_value(out, value, frame_expansion=options.frame_expansion)
        Err(e) => return Err(e)
      }
    }
  }
  Ok(out)
}

///|
/// 顶层元素选择（serialize_top 同款判据，ExpandedValue 直收——J3.1 抽取注记
/// 见 expand_top_values）
fn push_top_value(
  out : Array[ExpandedValue],
  value : ExpandedValue,
  frame_expansion? : Bool = false,
  root? : Bool = true,
) -> Unit {
  match value {
    // 顶层值对象即弃（#t0045："Top-level value objects are removed"）
    ExpandedValue::Value(_) => ()
    ExpandedValue::Node(node) =>
      // 顶层 @graph 单一门（文档级批——#t0009/#t0021/#t0046 oracle）：展开后
      // 仅存 @graph 的根节点对象表面化为图内容数组；带任何其他属性（含 @id、
      // @type、正属性、@reverse）则保留节点形态（#t0021：title + @graph 并存）。
      // **root 限定（J9 html 面双 oracle——t0020 根位解包 vs te004 数组成员位
      // 保留）**：仅@graph 包裹解包只属文档根位；顶层数组的成员位仅@graph map
      // 保包裹（REC 5.1 自由浮动丢弃清单=空/@value|@list/仅@id，无仅@graph 臂
      // ——te004 W3C 期待实证）
      if root &&
        node.graph is Some(graph_items) &&
        node.id is None &&
        node.types.is_empty() &&
        node.properties.is_empty() &&
        node.reverse_props.is_empty() {
        for item in graph_items {
          out.push(item)
        }
      } else if is_free_floating(node) && !frame_expansion {
        // 顶层 free-floating 节点即弃（#t0001 同族）；frameExpansion 豁免
        // ——@id-only 帧根是合法 pattern（t0032 判定面：弃则空帧全配）
      } else {
        out.push(value)
      }
    other => out.push(other)
  }
}

///|
/// expansion 文档入口：JSON 文本 → 展开形态（顶层恒为数组；free-floating 顶层节点丢弃）
pub fn expand_document(
  text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let values = match expand_top_values(text, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok(JsonValue::Array(values.map(serialize_value)))
}

///|
/// toRDF 文档入口（J3.1——库级 API，gen 调度面 handler_hook 的调用面）：
/// JSON 文本 → 展开形 → 四元组。负例 = 任一段 Err。
pub fn to_rdf_document(
  text : String,
  options : JsonLdOptions,
) -> Result[Array[JsonLdQuad], JsonLdError] {
  let values = match expand_top_values(text, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  ToRdfProcessor::node_to_quads(StandardExpander::{ }, values, options)
}

///|
/// free-floating：无属性、无类型（@id 有无均计）——顶层展开即弃
/// （#t0001：仅 @id 丢弃；同族：{} 亦丢弃；@graph-bearing 节点不算
/// free-floating——图对象有意义，文档级批扩展）
fn is_free_floating(node : ExpandedNode) -> Bool {
  node.properties.is_empty() &&
  node.types.is_empty() &&
  node.graph is None &&
  node.included is None && // included-bearing 节点不弃（#tin03：仅 @included 的根节点保留）
  // reverse-bearing 节点不弃（@index mapping 批——#t0131 oracle：仅 @reverse 的根节点
  // 保留；@reverse 项进 reverse_props 而非 properties，故须显式豁免）
  node.reverse_props.is_empty() &&
  // index-bearing 节点不弃（#te001 oracle——flatten「Conflicting indexes」负例
  // 实证：@id+@index 裸节点须抵达节点字典合并面，弃则冲突不可见；expand/toRdf
  // 套件均无此形在册案例，零回归面）
  node.index is None
}
// 豁免清单沿革（第五位，2026-10-01 framing 役49）：frameExpansion 模式下
// @id-only 帧根/子 pattern 不弃（t0032 判定面——弃则帧空全配）。
// **族核（用户核）**：与前四位**不同族**——前四位（graph/included/reverse/
// index）是「内容承载节点」**普适豁免**（任何模式下该节点都有意义）；本位是
// **模式条件豁免**（同一 @id-only 节点在常规展开仍弃，仅 frameExpansion 保）。
// 故不作普适判扩展，走调用点 `!options.frame_expansion` 旁路（push_top_value
// + 集合位两门），is_free_floating 本体零改动。

///|
/// ExpandedValue → 展开形态 JsonValue（对拍通道；J2 按覆盖面扩展）
fn serialize_value(value : ExpandedValue) -> JsonValue {
  match value {
    ExpandedValue::Node(node) => serialize_node(node)
    ExpandedValue::Value(literal) => {
      let pairs : Array[(String, JsonValue)] = []
      // raw 保形：number/bool 原样输出（string 走词形）
      pairs.push(
        (
          "@value",
          match literal.raw {
            Some(raw) => raw
            None => JsonValue::String(literal.value)
          },
        ),
      )
      match literal.datatype {
        Some(dt) => pairs.push(("@type", JsonValue::String(dt)))
        None => ()
      }
      match literal.language {
        Some(lang) => pairs.push(("@language", JsonValue::String(lang)))
        None => ()
      }
      match literal.direction {
        Some(dir) => pairs.push(("@direction", JsonValue::String(dir)))
        None => ()
      }
      // 值对象位 Included Blocks 保形（#tin05 oracle：还原 "@included" 键，
      // 内层节点照常渲染）
      match literal.included {
        Some(inc_nodes) =>
          pairs.push(
            (
              "@included",
              JsonValue::Array(
                inc_nodes.map(fn(n) { serialize_value(ExpandedValue::Node(n)) }),
              ),
            ),
          )
        None => ()
      }
      // 值对象位 @index（@index mapping 批——#t0036 oracle：字面量条目的索引）
      match literal.index {
        Some(index) => pairs.push(("@index", JsonValue::String(index)))
        None => ()
      }
      JsonValue::Object(pairs)
    }
    ExpandedValue::List(items, ..) =>
      JsonValue::Object([
        ("@list", JsonValue::Array(items.map(serialize_value))),
      ])
  }
}

///|
fn serialize_node(node : ExpandedNode) -> JsonValue {
  let pairs : Array[(String, JsonValue)] = []
  match node.id {
    // EXPLICIT_NULL_ID 哨兵 = @id 被忽略的节点（t0122 oracle：字面 "@id": null）
    Some(EXPLICIT_NULL_ID) => pairs.push(("@id", JsonValue::Null))
    Some(id) => pairs.push(("@id", JsonValue::String(id)))
    None => ()
  }
  if node.types.length() > 0 {
    pairs.push(
      (
        "@type",
        JsonValue::Array(node.types.map(fn(t) { JsonValue::String(t) })),
      ),
    )
  }
  for pair in node.properties {
    pairs.push((pair.0, JsonValue::Array(pair.1.map(serialize_value))))
  }
  // @reverse 映射输出（reverse 批——#t0042 oracle："@reverse": {iri: [values]}）
  if node.reverse_props.length() > 0 {
    let rev_pairs : Array[(String, JsonValue)] = []
    for pair in node.reverse_props {
      rev_pairs.push((pair.0, JsonValue::Array(pair.1.map(serialize_value))))
    }
    pairs.push(("@reverse", JsonValue::Object(rev_pairs)))
  }
  // 节点位 @graph 输出（文档级批——#t0020 oracle：节点下 @graph 保留）
  match node.graph {
    Some(items) =>
      pairs.push(("@graph", JsonValue::Array(items.map(serialize_value))))
    None => ()
  }
  // Included Blocks 键渲染（@included 纯形批——in01-in04 oracle：@included
  // 作为节点对象键保形输出，included 节点照常渲染；嵌套 included 随递归
  // 自展——in04）
  match node.included {
    Some(inc_nodes) =>
      pairs.push(
        (
          "@included",
          JsonValue::Array(
            inc_nodes.map(fn(n) { serialize_value(ExpandedValue::Node(n)) }),
          ),
        ),
      )
    None => ()
  }
  // index map 条目 @index（@container 映射批——#tc013 oracle）
  match node.index {
    Some(index) => pairs.push(("@index", JsonValue::String(index)))
    None => ()
  }
  JsonValue::Object(pairs)
}

///|
/// 对拍归一：对象键序不敏感（键按字典序重排，递归）；数组保序
pub fn json_canonical(value : JsonValue) -> JsonValue {
  match value {
    JsonValue::Object(pairs) => {
      let sorted = pairs.map(fn(pair) { (pair.0, json_canonical(pair.1)) })
      sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
      JsonValue::Object(sorted)
    }
    JsonValue::Array(items) => JsonValue::Array(items.map(json_canonical))
    other => other
  }
}

///|
/// JSON-LD 文档比对（W3C README「JSON-LD Object comparison」移植；役65
/// 定位改判：功能=通用文档比对器——对象键序不敏感；数组默认无序——唯一
/// 例外 @list 键下的数组保序；标量严格相等。语言标签大小写不敏感项未采
/// （现役从严）。「suite」系历史名非用途限定。tn004 双 nest 保序输出
/// [v2,v4,v3] 与 expected [v2,v3,v4] 同判——合法置换。
pub fn canonical_for_suite(value : JsonValue) -> JsonValue {
  canonical_suite_inner(value, false)
}

///|
fn canonical_suite_inner(
  value : JsonValue,
  order_significant : Bool,
) -> JsonValue {
  match value {
    JsonValue::Object(pairs) => {
      let sorted = pairs.map(fn(pair) {
        (pair.0, canonical_suite_inner(pair.1, pair.0 is "@list"))
      })
      sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
      JsonValue::Object(sorted)
    }
    JsonValue::Array(items) =>
      if order_significant {
        JsonValue::Array(
          items.map(fn(item) { canonical_suite_inner(item, false) }),
        )
      } else {
        let canon = items.map(fn(item) { canonical_suite_inner(item, false) })
        canon.sort_by(json_total_compare)
        JsonValue::Array(canon)
      }
    other => other
  }
}

///|
/// JsonValue 全序比较（套件无序数组排序用）：变体秩 -> 内容逐层
fn json_total_compare(a : JsonValue, b : JsonValue) -> Int {
  let rank = fn(v : JsonValue) -> Int {
    match v {
      JsonValue::Null => 0
      JsonValue::Bool(_) => 1
      JsonValue::Number(_) => 2
      JsonValue::String(_) => 3
      JsonValue::Array(_) => 4
      JsonValue::Object(_) => 5
    }
  }
  let ra = rank(a)
  let rb = rank(b)
  if ra != rb {
    return ra - rb
  }
  match (a, b) {
    (JsonValue::Bool(x), JsonValue::Bool(y)) =>
      match (x, y) {
        (true, false) => 1
        (false, true) => -1
        _ => 0
      }
    (JsonValue::Number(x), JsonValue::Number(y)) => x.compare(y)
    (JsonValue::String(x), JsonValue::String(y)) => x.compare(y)
    (JsonValue::Array(xs), JsonValue::Array(ys)) => {
      let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
      for i in 0..<n {
        let c = json_total_compare(xs[i], ys[i])
        if c != 0 {
          return c
        }
      }
      xs.length().compare(ys.length())
    }
    (JsonValue::Object(xs), JsonValue::Object(ys)) => {
      let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
      for i in 0..<n {
        let c = xs[i].0.compare(ys[i].0)
        if c != 0 {
          return c
        }
        let cv = json_total_compare(xs[i].1, ys[i].1)
        if cv != 0 {
          return cv
        }
      }
      xs.length().compare(ys.length())
    }
    _ => 0
  }
}

///|
/// JSON-LD 文档同构判定（bnode 双射兜底；役65 定位改判：功能=通用同构
/// 比对器——直比对拍不过时，bnode 词面升为存在变量——存在标签双射 f 使
/// relabel 后规范形逐字节相等 ⇒ 同构成立。词面位三钉（flatten 输出形）：
/// 谓词键位 / "@id" 值位 / "@type" 数组串值位；"@value" 字面量串不重标
/// （字面量 "_:x" 非节点词面）。标签数 > 8 直接 false——**8 是排列数工作
/// 界，非经验值**：回溯最坏 = n! 次全文档重标规范渲染，8! = 40320 次为可
/// 接受上界；套件实测最大 4 标签（#t0038，24 排列），8 留 4 倍标签余量。
/// 「suite」系历史名非用途限定。
pub fn isomorphic_for_suite(ours : JsonValue, expected : JsonValue) -> Bool {
  // @graph 数组集合语义（役52 交棒钉兑现——RDF 图无序；framing unordered
  // oracle 序不判定。只松不紧：canonical 直比通道不受扰，兜底面放宽）
  let ours_norm = jv_sort_graph_arrays(ours)
  let expected_norm = jv_sort_graph_arrays(expected)
  let ours_canon = render_json(canonical_for_suite(ours_norm))
  let expected_canon = render_json(canonical_for_suite(expected_norm))
  if ours_canon == expected_canon {
    return true
  }
  let la : Map[String, Bool] = Map([])
  jv_bnode_labels(ours, la)
  let lb : Map[String, Bool] = Map([])
  jv_bnode_labels(expected, lb)
  if la.length() != lb.length() || la.length() > 8 {
    return false
  }
  let left = la.keys().collect()
  left.sort()
  let right = lb.keys().collect()
  right.sort()
  jv_bnode_assign(left, right, 0, Map([]), Map([]), ours, expected_canon)
}

///|
/// @graph 数组排序规范化（役52 序勘定低成本路线）：对象含 @graph 键且值
/// 为数组 ⇒ 元素按 canonical 词形排序（深走全树）；其余结构原样递归
fn jv_sort_graph_arrays(value : JsonValue) -> JsonValue {
  match value {
    JsonValue::Object(pairs) => {
      let new_pairs : Array[(String, JsonValue)] = []
      for pair in pairs {
        new_pairs.push((pair.0, jv_sort_graph_arrays(pair.1)))
      }
      for i, pair in new_pairs {
        if pair.0 == "@graph" {
          match pair.1 {
            JsonValue::Array(items) => {
              let keyed : Array[(String, JsonValue)] = []
              for item in items {
                keyed.push((render_json(canonical_for_suite(item)), item))
              }
              keyed.sort_by(fn(a, b) { String::compare(a.0, b.0) })
              let sorted : Array[JsonValue] = []
              for kv in keyed {
                sorted.push(kv.1)
              }
              new_pairs[i] = (pair.0, JsonValue::Array(sorted))
            }
            _ => ()
          }
        }
      }
      JsonValue::Object(new_pairs)
    }
    JsonValue::Array(items) => {
      let new_items : Array[JsonValue] = []
      for item in items {
        new_items.push(jv_sort_graph_arrays(item))
      }
      JsonValue::Array(new_items)
    }
    _ => value
  }
}

///|
/// bnode 词面收集（三钉位递归全走；词面去重入表——判定器同形 nq_term_is_bnode）
fn jv_bnode_labels(value : JsonValue, into : Map[String, Bool]) -> Unit {
  match value {
    JsonValue::Object(pairs) =>
      for pair in pairs {
        if nq_term_is_bnode(pair.0) {
          into[pair.0] = true
        }
        match (pair.0, pair.1) {
          ("@id", JsonValue::String(word)) =>
            if nq_term_is_bnode(word) {
              into[word] = true
            }
          ("@type", JsonValue::Array(items)) =>
            for item in items {
              match item {
                JsonValue::String(word) =>
                  if nq_term_is_bnode(word) {
                    into[word] = true
                  }
                _ => ()
              }
            }
          _ => ()
        }
        jv_bnode_labels(pair.1, into)
      }
    JsonValue::Array(items) =>
      for item in items {
        jv_bnode_labels(item, into)
      }
    _ => ()
  }
}

///|
/// bnode 词面重标（三钉位替换——与收集位对称；mapping 只含 bnode 词面，
/// 命中即换、未命中保留原形）
fn jv_relabel_bnodes(
  value : JsonValue,
  mapping : Map[String, String],
) -> JsonValue {
  match value {
    JsonValue::Object(pairs) => {
      let out : Array[(String, JsonValue)] = []
      for pair in pairs {
        let key = match mapping.get(pair.0) {
          Some(relabeled) => relabeled
          None => pair.0
        }
        let value_out = match (pair.0, pair.1) {
          ("@id", JsonValue::String(word)) =>
            match mapping.get(word) {
              Some(relabeled) => JsonValue::String(relabeled)
              None => pair.1
            }
          ("@type", JsonValue::Array(items)) =>
            JsonValue::Array(
              items.map(fn(item) {
                match item {
                  JsonValue::String(word) =>
                    match mapping.get(word) {
                      Some(relabeled) => JsonValue::String(relabeled)
                      None => item
                    }
                  _ => item
                }
              }),
            )
          _ => jv_relabel_bnodes(pair.1, mapping)
        }
        out.push((key, value_out))
      }
      JsonValue::Object(out)
    }
    JsonValue::Array(items) =>
      JsonValue::Array(items.map(fn(item) { jv_relabel_bnodes(item, mapping) }))
    other => other
  }
}

///|
/// 标签双射回溯（left 逐个向 right 未用词面派位；满位即重标对拍——
/// mapping 同位覆写无需撤销，used 撤销保双射）
fn jv_bnode_assign(
  left : Array[String],
  right : Array[String],
  depth : Int,
  mapping : Map[String, String],
  used : Map[String, Bool],
  ours : JsonValue,
  expected_canon : String,
) -> Bool {
  if depth == left.length() {
    let relabeled = jv_relabel_bnodes(ours, mapping)
    return render_json(canonical_for_suite(relabeled)) == expected_canon
  }
  for j in 0..<right.length() {
    if !used.contains(right[j]) {
      used[right[j]] = true
      mapping[left[depth]] = right[j]
      if jv_bnode_assign(
          left,
          right,
          depth + 1,
          mapping,
          used,
          ours,
          expected_canon,
        ) {
        return true
      }
      used.remove(right[j])
    }
  }
  false
}

///|
/// flatten 状态（J5——spec §8.40 作用域模型）：bnode 序号 / 成员账
/// （scope → 成员对列表——"" = 顶层/default，"g:词面" = 具名图作用域）/
/// 注册账（scope|term——同作用域同 id 只注册一次）/ 作用域防环账
priv struct FlattenState {
  mut counter : Int
  visited : Map[String, Bool]
  members : Map[String, Array[Array[(String, JsonValue)]]]
  scopes : Map[String, Bool]
  reserved : Map[String, Bool]
}

///|
/// flatten 主体词面：有词面恒保留（#t0046 oracle：@base null 下相对 IRI
/// "0"/"" 恒词面——base 解析已在 expansion 全链完成，此处无第二次解析面；
/// bnode/绝对 IRI 自然在内）；无 id ⇒ 新生 "_:bN" 并回写
fn flatten_term(state : FlattenState, node : ExpandedNode) -> String {
  match node.id {
    Some(id) => id
    None => {
      let t = flatten_fresh_bnode(state)
      node.id = Some(t)
      t
    }
  }
}

///|
/// 新生 bnode（序号跳过**输入在册标签**——#t0045 oracle：输入明写 "_:b0" 与
/// 新生 "_:b0" 撞号 ⇒ 注入错体；reserved 预扫防）
fn flatten_fresh_bnode(state : FlattenState) -> String {
  let mut t = "_:b\{state.counter}"
  state.counter += 1
  while state.reserved.contains(t) {
    t = "_:b\{state.counter}"
    state.counter += 1
  }
  t
}

///|
/// bnode 标签预扫收集（ExpandedValue 树全走——#t0045 oracle）
fn flatten_reserve(value : ExpandedValue, into : Map[String, Bool]) -> Unit {
  match value {
    ExpandedValue::Node(node) => {
      match node.id {
        Some(id) => if nq_term_is_bnode(id) { into[id] = true }
        None => ()
      }
      for pair in node.properties {
        for v in pair.1 {
          flatten_reserve(v, into)
        }
      }
      for pair in node.reverse_props {
        for v in pair.1 {
          flatten_reserve(v, into)
        }
      }
      match node.graph {
        Some(items) =>
          for it in items {
            flatten_reserve(it, into)
          }
        None => ()
      }
      match node.included {
        Some(incs) =>
          for inc in incs {
            flatten_reserve(ExpandedValue::Node(inc), into)
          }
        None => ()
      }
    }
    ExpandedValue::List(items, ..) =>
      for it in items {
        flatten_reserve(it, into)
      }
    ExpandedValue::Value(_) => ()
  }
}

///|
/// JsonValue → JSON 文本（**往返保真 min-JSON**；役65 库化整形晋 pub——
/// 真调用点 = html extract_all 合并源 + isomorphic_for_suite 规范渲染 +
/// 去重键；库出口承诺 = compact/expand 返回 JsonValue 须有官方序列化器）。
/// **≠ json_canonical**：键序/数词形/数组序一概不动（规范形归
/// json_canonical，本函数只管词法保真）。字符串转义 `"` `\` 与全部控制
/// 字符（`\b\f\n\r\t` 命名形 + 其余 \u00XX）；数词形 = Double 插值词形
/// （render∘parse 往返值等价，wbtest 钉）。
pub fn render_json(value : JsonValue) -> String {
  match value {
    JsonValue::Null => "null"
    JsonValue::Bool(b) => if b { "true" } else { "false" }
    JsonValue::Number(nv) => "\{nv}"
    JsonValue::String(sv) => render_json_string(sv)
    JsonValue::Array(items) => {
      let parts = StringBuilder()
      parts.write_string("[")
      for i, item in items {
        if i > 0 {
          parts.write_string(",")
        }
        parts.write_string(render_json(item))
      }
      parts.write_string("]")
      parts.to_string()
    }
    JsonValue::Object(pairs) => {
      let parts = StringBuilder()
      parts.write_string("{")
      for i, pair in pairs {
        if i > 0 {
          parts.write_string(",")
        }
        parts.write_string(render_json(JsonValue::String(pair.0)))
        parts.write_string(":")
        parts.write_string(render_json(pair.1))
      }
      parts.write_string("}")
      parts.to_string()
    }
  }
}

///|
/// JSON 字符串词形（引号包裹 + 转义门：`"` `\` 控制字符——役65 晋 pub 前
/// 补，此前零转义渲染含 `"` 串值产非法 JSON；html 50/50 纯因无此形输入）
fn render_json_string(sv : String) -> String {
  let parts = StringBuilder()
  parts.write_char('"')
  for ch in sv {
    let code = ch.to_int()
    if ch == '"' {
      parts.write_string("\\\"")
    } else if ch == '\\' {
      parts.write_string("\\\\")
    } else if code == 8 {
      parts.write_string("\\b")
    } else if code == 12 {
      parts.write_string("\\f")
    } else if code == 10 {
      parts.write_string("\\n")
    } else if code == 13 {
      parts.write_string("\\r")
    } else if code == 9 {
      parts.write_string("\\t")
    } else if code < 0x20 {
      // 其余控制字符 → \u00XX（大写十六进制，JSON 惯例）
      parts.write_string("\\u00")
      parts.write_char(render_json_hex_digit(code / 16))
      parts.write_char(render_json_hex_digit(code % 16))
    } else {
      parts.write_char(ch)
    }
  }
  parts.write_char('"')
  parts.to_string()
}

///|
/// 0-15 → 十六进制位字符（大写；控制字符 \u 转义用）
fn render_json_hex_digit(n : Int) -> Char {
  if n < 10 {
    Int::unsafe_to_char(48 + n)
  } else {
    Int::unsafe_to_char(55 + n)
  }
}

///|
/// 属性值行走分发（节点 → 词面引用 + 作用域注册；字面量/列表 → 词面对象）。
/// None = null 条目弃。
fn flatten_walk_value(
  state : FlattenState,
  value : ExpandedValue,
  scope : String,
) -> JsonValue? {
  match value {
    ExpandedValue::Node(child) => {
      let term = flatten_walk_node(state, child, scope)
      Some(JsonValue::Object([("@id", JsonValue::String(term))]))
    }
    ExpandedValue::Value(l) => Some(serialize_value(ExpandedValue::Value(l)))
    ExpandedValue::List(items, ..) => {
      // @list 保序保重复（#t0027 oracle：list 2,2 保留）
      let arr : Array[JsonValue] = []
      for it in items {
        match flatten_walk_value(state, it, scope) {
          Some(jv) => arr.push(jv)
          None => ()
        }
      }
      Some(JsonValue::Object([("@list", JsonValue::Array(arr))]))
    }
  }
}

///|
/// 属性值数组组装（**非 @list 值去重**——RDF 集合语义：#t0027 myset 2,2,3 →
/// 1,2,3；@list 值对象为单值不受影响）
fn flatten_vals(
  state : FlattenState,
  values : Array[ExpandedValue],
  scope : String,
) -> Array[JsonValue] {
  let vals : Array[JsonValue] = []
  let seen : Map[String, Bool] = Map([])
  for v in values {
    match v {
      ExpandedValue::List(_) =>
        match flatten_walk_value(state, v, scope) {
          Some(jv) => vals.push(jv)
          None => ()
        }
      _ =>
        match flatten_walk_value(state, v, scope) {
          Some(jv) => {
            let key = render_json(jv)
            if !seen.contains(key) {
              seen[key] = true
              vals.push(jv)
            }
          }
          None => ()
        }
    }
  }
  vals
}

///|
/// 同 id 节点图载体判定（@graph 在场——图载体恒顶层成员，#t0021 oracle）
fn nq_has_graph(node : ExpandedNode) -> Bool {
  node.graph is Some(_)
}

///|
/// 成员值级并集（役56 tin06——同 id 全形再现并入既有成员：types 未见追加、
/// 属性同键值级去重续 append（JsonValue 结构等值）、键缺失即新建。**只在
/// visited 命中且全形时调用**——裸引用/环再入不走此臂）
fn flatten_member_merge(
  state : FlattenState,
  scope : String,
  term : String,
  node : ExpandedNode,
) -> Unit {
  let own_scope = if nq_has_graph(node) {
    "" // 图载体恒顶层成员（与 flatten_walk_node own_scope 同规）
  } else {
    scope
  }
  let lists = match state.members.get(own_scope) {
    Some(lists) => lists
    None => return
  }
  // 定位成员（@id 对 = String(term)）
  let mut target : Array[(String, JsonValue)]? = None
  for entry in lists {
    if entry.length() > 0 {
      match entry[0] {
        ("@id", JsonValue::String(id_word)) =>
          if id_word == term {
            target = Some(entry)
          }
        _ => ()
      }
    }
  }
  let member_pairs = match target {
    Some(pairs) => pairs
    None => return
  }
  // types 未见追加（"@type" 对缺省 = 末位新建；canonical 键序归一不挑位）
  if node.types.length() > 0 {
    let mut type_array : Array[JsonValue]? = None
    for member_entry in member_pairs {
      if member_entry.0 == "@type" {
        match member_entry.1 {
          JsonValue::Array(values) => type_array = Some(values)
          _ => ()
        }
      }
    }
    match type_array {
      Some(values) => {
        let seen_t : Map[String, Bool] = Map([])
        for v in values {
          match v {
            JsonValue::String(word) => seen_t[word] = true
            _ => ()
          }
        }
        for t in node.types {
          if !seen_t.contains(t) {
            values.push(JsonValue::String(t))
            seen_t[t] = true
          }
        }
      }
      None => {
        let values : Array[JsonValue] = []
        for t in node.types {
          values.push(JsonValue::String(t))
        }
        member_pairs.push(("@type", JsonValue::Array(values)))
      }
    }
  }
  // 属性：同键值级去重续 append（@value/@id 渲染形结构等值判重）；缺键新建
  for pair in node.properties {
    let rendered = flatten_vals(state, pair.1, own_scope)
    let mut slot : Array[JsonValue]? = None
    for member_pair in member_pairs {
      if member_pair.0 == pair.0 {
        match member_pair.1 {
          JsonValue::Array(values) => slot = Some(values)
          _ => ()
        }
      }
    }
    match slot {
      Some(values) =>
        for v in rendered {
          if !values.contains(v) {
            values.push(v)
          }
        }
      None => member_pairs.push((pair.0, JsonValue::Array(rendered)))
    }
  }
}

///|
/// 节点行走 + 作用域成员注册（返回主体词面）：
/// - **图载体节点（@graph 在场）= 恒顶层 "" 成员**（#t0021 oracle：_:b0/_:b1
///   恒顶层；其 @graph 内容 = 新具名作用域 "g:词面" 的成员——book 提升入
///   图内、chapters 内联 _:b1）；自身属性值节点行走于 ""。
/// - 普通节点 = 当前作用域成员（嵌套节点提升入所在图——#t0021 book；
///   同作用域同 id 一次——#flatten-0005 oracle：裸引用不实体化）。
/// - **@reverse 反转注入**（#t0037/#t0045/#t0046 oracle——flatten 为反转形，
///   与 expand t0042 保形分叉）：reverse 值节点作主体、注入 (pred, 本体引用)
///   至其成员对列表。
fn flatten_walk_node(
  state : FlattenState,
  node : ExpandedNode,
  scope : String,
) -> String {
  let term = flatten_term(state, node)
  let visit_key = "\{scope}|\{term}"
  let is_graph = nq_has_graph(node)
  if state.visited.contains(visit_key) {
    // 全形再现 = 成员值级并集（役56 tin06 勘定——REC Generate Node Map
    // 语义：同 id 每次出现都并入节点图成员；visited 早退只应吞裸引用/
    // 环再入。included 先行序下后到全形携带的属性不得整弃）
    if node.types.length() > 0 ||
      node.properties.length() > 0 ||
      node.reverse_props.length() > 0 {
      flatten_member_merge(state, scope, term, node)
    }
    return term
  }
  state.visited[visit_key] = true
  let own_scope = if is_graph {
    "" // 图载体恒顶层成员（#t0021 oracle）
  } else {
    scope
  }
  // included：同作用域成员行走（#tin01 oracle——flatten 不渲染 @included 键，
  // included 节点提升为所在作用域成员；in01 键渲染保形是 expand 套件面）
  match node.included {
    Some(incs) =>
      for inc in incs {
        let _ = flatten_walk_node(state, inc, own_scope)
      }
    None => ()
  }
  // 同谓词跨对合并（F2 拼接产生同名多对——#t0038 oracle：types/props 去重）
  let prop_map : Map[String, Array[ExpandedValue]] = Map([])
  let prop_order : Array[String] = []
  for pair in node.properties {
    match prop_map.get(pair.0) {
      Some(existing) =>
        for v in pair.1 {
          existing.push(v)
        }
      None => {
        let vals : Array[ExpandedValue] = []
        for v in pair.1 {
          vals.push(v)
        }
        prop_map[pair.0] = vals
        prop_order.push(pair.0)
      }
    }
  }
  let pairs : Array[(String, JsonValue)] = [("@id", JsonValue::String(term))]
  // @type（去重）
  if node.types.length() > 0 {
    let seen_t : Map[String, Bool] = Map([])
    let types : Array[JsonValue] = []
    for t in node.types {
      if !seen_t.contains(t) {
        seen_t[t] = true
        types.push(JsonValue::String(t))
      }
    }
    pairs.push(("@type", JsonValue::Array(types)))
  }
  // 属性（值去重经 flatten_vals）
  for pred in prop_order {
    match prop_map.get(pred) {
      Some(vals) =>
        pairs.push(
          (pred, JsonValue::Array(flatten_vals(state, vals, own_scope))),
        )
      None => ()
    }
  }
  // @index
  match node.index {
    Some(ix) => pairs.push(("@index", JsonValue::String(ix)))
    None => ()
  }
  // 图内容：新作用域续走（成员入 "g:词面"）+ @graph 成员装配（内联——
  // #flatten-0020-out 实证）
  match node.graph {
    Some(items) => {
      let graph_scope = "g:" + term
      if !state.scopes.contains(graph_scope) {
        state.scopes[graph_scope] = true
        state.members[graph_scope] = []
        for it in items {
          let _ = flatten_walk_value(state, it, graph_scope)
        }
      }
      let graph_arr : Array[JsonValue] = []
      match state.members.get(graph_scope) {
        Some(member_lists) =>
          for mentry in member_lists {
            graph_arr.push(JsonValue::Object(mentry))
          }
        None => ()
      }
      pairs.push(("@graph", JsonValue::Array(graph_arr)))
    }
    None => ()
  }
  // 裸 {@id} 引用不实体化（#flatten-0005/#t0020 oracle）——引用即词面；
  // 带 reverse 者例外（反转注入使其非裸）
  if pairs.length() == 1 && node.reverse_props.length() == 0 {
    return term
  }
  // 注册成员对列表（reverse 注入可寻址——数组引用原地变异）
  match state.members.get(own_scope) {
    Some(lists) => lists.push(pairs)
    None => {
      let lists : Array[Array[(String, JsonValue)]] = []
      lists.push(pairs)
      state.members[own_scope] = lists
    }
  }
  // @reverse 反转注入（flatten 为反转形——#t0037/#t0045/#t0046 oracle，
  // 与 expand t0042 保形分叉）：值节点作主体，注入 (pred, 本体引用)；
  // 裸跳过者 ensure {@id} 占位成员
  for pair in node.reverse_props {
    for v in pair.1 {
      match v {
        ExpandedValue::Node(child) => {
          let ct = flatten_term(state, child)
          let ckey = "\{own_scope}|\{ct}"
          if !state.visited.contains(ckey) {
            let _ = flatten_walk_node(state, child, own_scope)
          }
          let mut found : Array[(String, JsonValue)]? = None
          match state.members.get(own_scope) {
            Some(lists) =>
              for target in lists {
                if found is None && target.length() > 0 {
                  match target[0].1 {
                    JsonValue::String(id_term) =>
                      if id_term == ct {
                        found = Some(target)
                      }
                    _ => ()
                  }
                }
              }
            None => ()
          }
          // 注入目标 = child 成员对列表（**并入既有同谓词对**——#t0037/#t0039
          // oracle：@reverse 注入与显式 knows 同值只留一份，RDF 集合语义）
          let value_obj = JsonValue::Object([("@id", JsonValue::String(term))])
          let value_key = render_json(value_obj)
          let child_pairs : Array[(String, JsonValue)] = match found {
            Some(target) => target
            None => {
              let fresh : Array[(String, JsonValue)] = [
                ("@id", JsonValue::String(ct)),
              ]
              state.members[own_scope].push(fresh)
              fresh
            }
          }
          let mut merged = false
          for i in 0..<child_pairs.length() {
            if child_pairs[i].0 == pair.0 {
              match child_pairs[i].1 {
                JsonValue::Array(vals) => {
                  let mut dup = false
                  for existing in vals {
                    if render_json(existing) == value_key {
                      dup = true
                    }
                  }
                  if !dup {
                    vals.push(value_obj)
                  }
                  merged = true
                }
                _ => ()
              }
            }
          }
          if !merged {
            child_pairs.push((pair.0, JsonValue::Array([value_obj])))
          }
        }
        _ => ()
      }
    }
  }
  // 收账：reverse 注入成员（child_pairs 引用已在 members 中——此处按词面收）
  term
}

///|
/// flatten 文档入口（J5——spec §8.40）：JSON 文本 → 展开全链 → F2 同 id
/// 预合并 → 作用域成员注册 → 顶层作用域枚举。负例 = 任一段 Err。
/// flatten 唯一入口（REC flatten(input, context, options) 同形——context
/// 可选；役65 库化整形：原 flatten_document/with_context 双入口合一，
/// 兑现役56「暴露面随 harness 裁量收缩」承诺）。context 缺省 = 展平直出
/// （数组形）；context 给定 = 展平后以该 context 压缩（flatten_with_context_inner）。
pub fn flatten_document(
  text : String,
  context? : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  match context {
    Some(context_text) =>
      flatten_with_context_inner(text, context_text, options)
    None => {
      let top = match flatten_core(text, options) {
        Ok(top) => top
        Err(e) => return Err(e)
      }
      let out : Array[JsonValue] = []
      for pairs in top {
        out.push(JsonValue::Object(pairs))
      }
      Ok(JsonValue::Array(out))
    }
  }
}

///|
/// flatten + compaction 合成（REC flatten(input, context)——context 非
/// null ⇒ 展平后以该 context 压缩；役56 t0044。成员**再展开**（flatten
/// 展开形幂等——绝对 IRI 键/引用/@value 形不变形）后走压缩正机
/// （compact_node_jv）；wrap 三钉同 compact_document，compactArrays=false
/// 单节点也 @graph 包裹（#t0091 同款）。
fn flatten_with_context_inner(
  text : String,
  context_text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let top = match flatten_core(text, options) {
    Ok(top) => top
    Err(e) => return Err(e)
  }
  let ctx_doc = match parse_json(context_text) {
    Ok(doc) => doc
    Err(e) => return Err(e)
  }
  let inner : JsonValue = match ctx_doc {
    JsonValue::Object(pairs) => {
      let mut found : JsonValue? = None
      for pair in pairs {
        if pair.0 is "@context" {
          found = Some(pair.1)
        }
      }
      match found {
        Some(v) => v
        None => ctx_doc
      }
    }
    _ => ctx_doc
  }
  let active = match
    ContextProcessor::process_context(
      StandardExpander::{ },
      initial_context(options),
      inner,
      ContextFlags::element(),
      options,
    ) {
    Ok(context) => context
    Err(e) => return Err(e)
  }
  // 成员再展开 + 逐节点压缩
  let expander = StandardExpander::{ }
  let expansion_active = initial_context(options)
  let compacted : Array[JsonValue] = []
  for member_pairs in top {
    let element = JsonValue::Object(member_pairs)
    match
      StandardExpander::expand_object(
        expander,
        expansion_active,
        element,
        None,
        options,
      ) {
      Ok(Some(ExpandedValue::Node(member_node))) =>
        match compact_node_jv(member_node, active, options) {
          Ok(jv) => compacted.push(jv)
          Err(e) => return Err(e)
        }
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  // 顶层包裹（**flatten API 固定形制**，与 compact_document 的"单节点解包"分道）：
  // API compact() 明文"The final output is a map derived from compacted output.
  // If compacted output is an array, it is included with an entry of (a possibly
  // aliased) @graph"——flatten 的输入恒为**展平数组**，故顶层恒 `@graph` 包裹、
  // **不适用单节点解包**（oracle：html #tf001 单节点 ⇒ 仍 @graph；#tf003 两节点 ⇒
  // 条目内部单值仍按 compactArrays 出标量——即"顶层解包禁用、内部照旧"）
  let body_pairs : Array[(String, JsonValue)] = []
  if compacted.length() == 0 {
    return Ok(JsonValue::Object([]))
  } else {
    let graph_key = compact_iri_word(
      "@graph", true, false, true, active, options,
    )
    body_pairs.push((graph_key, JsonValue::Array(compacted)))
  }
  body_pairs.insert(0, ("@context", inner))
  Ok(JsonValue::Object(body_pairs))
}

///|
/// flatten 核心（展开 → F2 同 id 预合并 → 走图）——渲染成员对列；输出
/// 形分叉（直出/带 context 压缩）由入口裁定
fn flatten_core(
  text : String,
  options : JsonLdOptions,
) -> Result[Array[Array[(String, JsonValue)]], JsonLdError] {
  let values = match expand_top_values(text, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  // F2 同 id 预合并复用：同一 ctx 贯穿全值（跨值同 id 对象并集到首见）；
  // @index 冲突同点检出（#te001 oracle——同 id 双 @index 不等 = colliding
  // indexes 错，REC Generate Node Map 合并面）
  let merge_ctx : MergeCtx = { anon: 0, seen: Map([]), }
  for value in values {
    match nq_merge_same_id(value, merge_ctx, "") {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let state : FlattenState = {
    counter: 0,
    visited: Map([]),
    members: Map([("", [])]),
    scopes: Map([("", true)]),
    reserved: Map([]),
  }
  // bnode 标签预扫（#t0045 oracle——新生序号避开输入在册标签；全值一遍）
  for value in values {
    flatten_reserve(value, state.reserved)
  }
  for value in values {
    let _ = flatten_walk_value(state, value, "")
  }
  match state.members.get("") {
    Some(arr) => Ok(arr)
    None => Ok([])
  }
}

///|
/// compaction 文档入口（J6——spec §8.41 钉一）：JSON 文本 + 主动 context
/// 文本 → 展开全链 → context 处理 → 压缩序列化（compact_standard.mbt）。
/// 负例 = 任一段 Err。输出形三钉：展开空 → {}；单节点 → 对象；n 节点 →
/// @graph 包裹。@context 键 = **原文逐字**发射（223/223 实证），context 空
/// 不发射（6 例实证——ctx {} 族）。
pub fn compact_document(
  input_text : String,
  context_text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let values = match expand_top_values(input_text, options) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let ctx_doc = match parse_json(context_text) {
    Ok(doc) => doc
    Err(e) => return Err(e)
  }
  // context 文档形：{"@context": inner} 包装解包，裸形直用
  let inner : JsonValue = match ctx_doc {
    JsonValue::Object(pairs) => {
      let mut found : JsonValue? = None
      for pair in pairs {
        if pair.0 is "@context" {
          found = Some(pair.1)
        }
      }
      match found {
        Some(v) => v
        None => ctx_doc
      }
    }
    _ => ctx_doc
  }
  let active = match
    ContextProcessor::process_context(
      StandardExpander::{ },
      initial_context(options),
      inner,
      ContextFlags::element(),
      options,
    ) {
    Ok(context) => context
    Err(e) => return Err(e)
  }
  // 压缩主体（顶层形三钉；单节点解包随 compactArrays——#t0091 oracle：
  // compactArrays=false 时单节点也 @graph 包裹）
  let body_pairs : Array[(String, JsonValue)] = []
  if values.length() == 1 && options.compact_arrays {
    match values[0] {
      ExpandedValue::Node(node) =>
        match compact_node_jv(node, active, options) {
          Ok(JsonValue::Object(pairs)) =>
            for pair in pairs {
              body_pairs.push(pair)
            }
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      _ => ()
    }
  } else if values.length() == 1 {
    // 单节点未塌缩（compactArrays=false）→ @graph 包裹（REC §9.1 步 9.2——
    // compact 输出为数组时包 @graph 键；#t0091 oracle）
    match values[0] {
      ExpandedValue::Node(node) =>
        match compact_node_jv(node, active, options) {
          Ok(jv) => {
            let graph_key = compact_iri_word(
              "@graph", true, false, true, active, options,
            )
            body_pairs.push((graph_key, JsonValue::Array([jv])))
          }
          Err(e) => return Err(e)
        }
      _ => ()
    }
  } else if values.length() > 1 {
    let arr : Array[JsonValue] = []
    for value in values {
      match value {
        ExpandedValue::Node(node) =>
          match compact_node_jv(node, active, options) {
            Ok(jv) => arr.push(jv)
            Err(e) => return Err(e)
          }
        _ => ()
      }
    }
    // @graph 包裹键走 term 词形（关键字别名——#t0014/#t0052 oracle：
    // "data":"@graph"/"graph":"@graph" → 别名作键；无别名回落 "@graph"）
    let graph_key = compact_iri_word(
      "@graph", true, false, true, active, options,
    )
    body_pairs.push((graph_key, JsonValue::Array(arr)))
  }
  // @context 原文发射（context 空 / 主体空均不发射）
  let context_empty = match inner {
    JsonValue::Object(pairs) => pairs.is_empty()
    JsonValue::Null => true
    _ => false
  }
  if !context_empty && body_pairs.length() > 0 {
    body_pairs.insert(0, ("@context", inner))
  }
  Ok(JsonValue::Object(body_pairs))
}
