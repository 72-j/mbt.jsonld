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
  { base: options.base, vocab: None, terms: Map([]), }
}

///|
/// expansion 文档入口：JSON 文本 → 展开形态（顶层恒为数组；free-floating 顶层节点丢弃）
pub fn expand_document(
  text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let element = match parse_json(text) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  let expander = StandardExpander::{ }
  let active = initial_context(options)
  // 顶层形态三分：数组（逐元素展开收集、free-floating/值对象即弃——#t0013）、
  // 对象（单节点路径）、标量（挂后续例）
  match shape_of(element) {
    "array" => {
      let items = match element {
        JsonValue::Array(items) => items
        _ => return Err(JsonLdError::InvalidValue("shape mismatch: array"))
      }
      let out : Array[JsonValue] = []
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
          Ok(Some(ExpandedValue::Node(node))) =>
            if is_free_floating(node) {
              () // 顶层 free-floating 节点即弃（#t0001 同族）
            } else {
              out.push(serialize_value(ExpandedValue::Node(node)))
            }
          Ok(Some(ExpandedValue::Value(_))) => () // 顶层值对象即弃（#t0045 同族）
          Ok(Some(other)) => out.push(serialize_value(other))
          Ok(None) => ()
          Err(e) => return Err(e)
        }
      }
      Ok(JsonValue::Array(out))
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
        Ok(value) => Ok(serialize_top(value))
        Err(e) => Err(e)
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
        Ok(value) => Ok(serialize_top(Some(value)))
        Err(e) => Err(e)
      }
    }
  }
}

///|
/// 顶层形态：展开结果恒为数组；free-floating 顶层节点（仅 @id、无属性/类型）丢弃
/// ——#t0001 判定（"drop free-floating nodes"）；嵌套位置的 free-floating 挂后续例。
fn serialize_top(expanded : ExpandedValue?) -> JsonValue {
  match expanded {
    None => Array([])
    // 顶层值对象即弃（#t0045："Top-level value objects are removed"）
    Some(ExpandedValue::Value(_)) => Array([])
    Some(ExpandedValue::Node(node)) =>
      // 顶层 @graph 单一门（文档级批——#t0009/#t0021/#t0046 oracle）：展开后
      // 仅存 @graph 的根节点对象表面化为图内容数组；带任何其他属性（含 @id、
      // @type、正属性、@reverse）则保留节点形态（#t0021：title + @graph 并存）
      if node.graph is Some(graph_items) &&
        node.id is None &&
        node.types.is_empty() &&
        node.properties.is_empty() &&
        node.reverse_props.is_empty() {
        Array(graph_items.map(serialize_value))
      } else if is_free_floating(node) {
        Array([])
      } else {
        Array([serialize_value(ExpandedValue::Node(node))])
      }
    Some(other) => Array([serialize_value(other)])
  }
}

///|
/// free-floating：无属性、无类型（@id 有无均计）——顶层展开即弃
/// （#t0001：仅 @id 丢弃；同族：{} 亦丢弃；@graph-bearing 节点不算
/// free-floating——图对象有意义，文档级批扩展）
fn is_free_floating(node : ExpandedNode) -> Bool {
  node.properties.is_empty() && node.types.is_empty() && node.graph is None
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
