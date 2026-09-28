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
          Ok(Some(value)) => push_top_value(out, value)
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
        Ok(Some(value)) => push_top_value(out, value)
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
        Ok(value) => push_top_value(out, value)
        Err(e) => return Err(e)
      }
    }
  }
  Ok(out)
}

///|
/// 顶层元素选择（serialize_top 同款判据，ExpandedValue 直收——J3.1 抽取注记
/// 见 expand_top_values）
fn push_top_value(out : Array[ExpandedValue], value : ExpandedValue) -> Unit {
  match value {
    // 顶层值对象即弃（#t0045："Top-level value objects are removed"）
    ExpandedValue::Value(_) => ()
    ExpandedValue::Node(node) =>
      // 顶层 @graph 单一门（文档级批——#t0009/#t0021/#t0046 oracle）：展开后
      // 仅存 @graph 的根节点对象表面化为图内容数组；带任何其他属性（含 @id、
      // @type、正属性、@reverse）则保留节点形态（#t0021：title + @graph 并存）
      if node.graph is Some(graph_items) &&
        node.id is None &&
        node.types.is_empty() &&
        node.properties.is_empty() &&
        node.reverse_props.is_empty() {
        for item in graph_items {
          out.push(item)
        }
      } else if is_free_floating(node) {
        () // 顶层 free-floating 节点即弃（#t0001 同族）
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
    ExpandedValue::List(items) =>
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
/// W3C 官方比对归一（suite 比对通道；README「JSON-LD Object comparison」移植）：
/// 对象键序不敏感；数组默认无序——唯一例外 @list 键下的数组保序；标量严格
/// 相等。语言标签大小写不敏感项未采（现役从严）。tn004 双 nest 保序输出
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
/// suite 判定器 bnode 双射兜底（flatten 批——引用实现重标签语义 oracle）：
/// 直比对拍不过时，bnode 词面升为存在变量——存在标签双射 f 使 relabel 后
/// 规范形逐字节相等 ⇒ 同构成立。词面位三钉（flatten 输出形）：谓词键位 /
/// "@id" 值位 / "@type" 数组串值位；"@value" 字面量串不重标（字面量
/// "_:x" 非节点词面）。标签数 > 8 直接 false——**8 是排列数工作界，非经验
/// 值**：回溯最坏 = n! 次全文档重标规范渲染，8! = 40320 次为可接受上界；
/// 套件实测最大 4 标签（#t0038，24 排列），8 留 4 倍标签余量。
pub fn isomorphic_for_suite(ours : JsonValue, expected : JsonValue) -> Bool {
  let ours_canon = jv_render(canonical_for_suite(ours))
  let expected_canon = jv_render(canonical_for_suite(expected))
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
    return jv_render(canonical_for_suite(relabeled)) == expected_canon
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
    ExpandedValue::List(items) =>
      for it in items {
        flatten_reserve(it, into)
      }
    ExpandedValue::Value(_) => ()
  }
}

///|
/// JsonValue 渲染（去重键用——主包侧无 diag_json_str，测试包件不可见）
fn jv_render(value : JsonValue) -> String {
  match value {
    JsonValue::Null => "null"
    JsonValue::Bool(b) => if b { "true" } else { "false" }
    JsonValue::Number(nv) => "\{nv}"
    JsonValue::String(sv) => "\"" + sv + "\""
    JsonValue::Array(items) => {
      let parts = StringBuilder()
      parts.write_string("[")
      for i, item in items {
        if i > 0 {
          parts.write_string(",")
        }
        parts.write_string(jv_render(item))
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
        parts.write_string(jv_render(JsonValue::String(pair.0)))
        parts.write_string(":")
        parts.write_string(jv_render(pair.1))
      }
      parts.write_string("}")
      parts.to_string()
    }
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
    ExpandedValue::List(items) => {
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
            let key = jv_render(jv)
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
          let value_key = jv_render(value_obj)
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
                    if jv_render(existing) == value_key {
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
pub fn flatten_document(
  text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
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
  let top = match state.members.get("") {
    Some(arr) => arr
    None => []
  }
  let out : Array[JsonValue] = []
  for pairs in top {
    out.push(JsonValue::Object(pairs))
  }
  Ok(JsonValue::Array(out))
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
  // 压缩主体（顶层形三钉）
  let body_pairs : Array[(String, JsonValue)] = []
  if values.length() == 1 {
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
    let graph_key = compact_iri_word("@graph", true, false, active, options)
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
