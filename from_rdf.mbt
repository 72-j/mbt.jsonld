///|
/// fromRDF 主体（役57——REC §RDF-to-Object-Conversion；spec §8.130/§8.131
/// 钉）：N-Quads → 展开且展平形节点对象数组。三段式：①全量入账（结构化
/// term 存储）②形态集合判定（纯列表/复合字面）③统一渲染。核心判据
/// （t0008 破译）：**@list 转换只发生在普通性质对象位**——rdf:first 位引
/// 用恒 {@id} 物化（lista/b1/c1 面）；rest 位链续走吸收。named graph =
/// 图名节点 @graph 位；rdf:type → @type（useRdfType 例外）；xsd:string
/// datatype 剥除；useNativeTypes → native 词形（boolean 词形空间含 1/0、
/// 溢出/INF/非词形回落 typed；decimal 不在 native 列）；@json 字面 =
/// {@type:"@json",@value:解析值}（无效即负例错）；rdfDirection
/// i18n-datatype/compound-literal 两族。

///|
/// rdf:type 全 IRI
let from_rdf_type_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

///|
let from_rdf_first_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"

///|
let from_rdf_rest_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"

///|
let from_rdf_value_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#value"

///|
let from_rdf_language_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#language"

///|
let from_rdf_direction_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#direction"

///|
let from_rdf_nil_iri : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"

///|
let from_rdf_list_type : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#List"

///|
let from_rdf_json_datatype : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"

///|
let from_i18n_datatype_prefix : String = "https://www.w3.org/ns/i18n#"

///|
let from_xsd_string : String = "http://www.w3.org/2001/XMLSchema#string"

///|
/// 同图节点累积面（结构化 term 存储——渲染期统一转换）
priv struct FromRdfNode {
  props : Map[String, Array[NqTerm]]
  prop_order : Array[String]
  types : Array[String]
  /// first 位引用标记（吸收豁免判定——t0008/tli02 双面界定）
}

///|
/// 单图账（order = subject 首见序）
priv struct FromRdfGraph {
  nodes : Map[String, FromRdfNode]
  order : Array[String]
}

///|
fn FromRdfGraph::new() -> FromRdfGraph {
  { nodes: Map([]), order: [], }
}

///|
fn FromRdfGraph::node(self : FromRdfGraph, key : String) -> FromRdfNode {
  match self.nodes.get(key) {
    Some(node) => node
    None => {
      let fresh : FromRdfNode = { props: Map([]), prop_order: [], types: [], }
      self.nodes[key] = fresh
      self.order.push(key)
      fresh
    }
  }
}

///|
fn FromRdfGraph::append_prop(
  self : FromRdfGraph,
  key : String,
  pred : String,
  term : NqTerm,
) -> Unit {
  let node = self.node(key)
  match node.props.get(pred) {
    Some(values) =>
      // RDF 集合语义：同键同值去重（结构等值）
      if !from_rdf_terms_contains(values, term) {
        values.push(term)
      }
    None => {
      node.props[pred] = [term]
      node.prop_order.push(pred)
    }
  }
}

///|
fn from_rdf_terms_contains(values : Array[NqTerm], term : NqTerm) -> Bool {
  for existing in values {
    if from_rdf_term_eq(existing, term) {
      return true
    }
  }
  false
}

///|
fn from_rdf_term_eq(a : NqTerm, b : NqTerm) -> Bool {
  match (a, b) {
    (NqIriTerm(x), NqIriTerm(y)) => x == y
    (NqBnodeTerm(x), NqBnodeTerm(y)) => x == y
    (NqLitTerm(v1, d1, l1), NqLitTerm(v2, d2, l2)) =>
      v1 == v2 &&
      from_rdf_opt_string_eq(d1, d2) &&
      from_rdf_opt_string_eq(l1, l2)
    _ => false
  }
}

///|
fn from_rdf_opt_string_eq(a : String?, b : String?) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => x == y
    (None, None) => true
    _ => false
  }
}

///|
/// term → subject/bnode 账键
fn nq2_term_key(term : NqTerm) -> String {
  match term {
    NqIriTerm(iri) => iri
    NqBnodeTerm(label) => "_:" + label
    NqLitTerm(value, _, _) => value
  }
}

///|
/// 图渲染上下文（账 + 纯列表集合）
priv struct FromRdfGraphCtx {
  graph : FromRdfGraph
  pure_lists : Map[String, Bool]
  is_10 : Bool
}

///|
fn from_rdf_graph_ctx(graph : FromRdfGraph, is_10 : Bool) -> FromRdfGraphCtx {
  let pure_lists : Map[String, Bool] = Map([])
  for key in graph.order {
    if from_rdf_is_pure_list(graph, key, Map([])) {
      pure_lists[key] = true
    }
  }
  { graph, pure_lists, is_10, }
}

///|
/// scoped 版：跨图出现（presence 多图）的键直接出局（t0020/21——同标签
/// 跨图 = 链污染），且污染沿 rest 链传播（z1 多图 ⇒ z0 链头同否）
fn from_rdf_graph_ctx_scoped(
  graph : FromRdfGraph,
  graph_key : String,
  first_refs : Map[String, Map[String, Bool]],
  presence : Map[String, Map[String, Bool]],
  is_10 : Bool,
) -> FromRdfGraphCtx {
  let pure_lists : Map[String, Bool] = Map([])
  for key in graph.order {
    let scoped_ok = from_rdf_is_pure_list_scoped(
      graph,
      key,
      Map([]),
      presence,
      graph_key,
    )
    // first 位物化豁免（1.0 模式面——t0008 lista/b1/c1）：first 位引用且
    // rest 非直 nil 的纯链 = 物化（1.1 嵌套转换不豁免——tli03）
    let first_hit = match first_refs.get(key) {
      Some(graphs) => graphs.contains(graph_key)
      None => false
    }
    let rest_direct_nil = match graph.nodes.get(key) {
      Some(node) =>
        match node.props.get(from_rdf_rest_iri) {
          Some([rest_term]) =>
            match rest_term {
              NqIriTerm(iri) => iri == from_rdf_nil_iri
              _ => false
            }
          _ => false
        }
      None => false
    }
    if scoped_ok && !(is_10 && first_hit && !rest_direct_nil) {
      pure_lists[key] = true
    }
  }
  { graph, pure_lists, is_10, }
}

///|
/// scoped 纯列表判据：入口即查本键 presence 多图出局；rest 递归同规

///|
/// (调试细胞；完即删)
let from_rdf_scoped_log : Array[String] = [""]

///|
fn from_rdf_scoped_log_append(s : String) -> Unit {
  from_rdf_scoped_log[0] = from_rdf_scoped_log[0] + s
}

///|
fn from_rdf_is_pure_list_scoped(
  graph : FromRdfGraph,
  key : String,
  visiting : Map[String, Bool],
  presence : Map[String, Map[String, Bool]],
  graph_key : String,
) -> Bool {
  from_rdf_scoped_log_append("ENTER(" + key + ") ")
  match presence.get(key) {
    Some(graphs) =>
      if graphs.length() > 1 {
        from_rdf_scoped_log_append("X-multi(" + key + ") ")
        return false
      }
    None => return false
  }
  if visiting.contains(key) {
    from_rdf_scoped_log_append("X-visiting(" + key + ") MAP[")
    for mk in visiting.keys() {
      from_rdf_scoped_log_append(mk + " ")
    }
    from_rdf_scoped_log_append("] ")
    return false
  }
  if !from_rdf_is_pure_list(graph, key, visiting) {
    from_rdf_scoped_log_append("X-plainfalse(" + key + ") ")
    return false
  }
  // rest 链续查（链上污染传播）
  let node = graph.nodes[key]
  match node.props.get(from_rdf_rest_iri) {
    Some([rest_term]) =>
      match rest_term {
        NqBnodeTerm(label) => {
          let next_key = "_:" + label
          if next_key == key {
            return false
          }
          visiting[key] = true
          from_rdf_scoped_log_append("REST(" + key + "->" + next_key + ") ")
          let result = from_rdf_is_pure_list_scoped(
            graph, next_key, visiting, presence, graph_key,
          )
          visiting.remove(key)
          from_rdf_scoped_log_append(
            "RESTBACK(" + key + "=" + result.to_string() + ") ",
          )
          result
        }
        NqIriTerm(iri) => iri == from_rdf_nil_iri
        NqLitTerm(_, _, _) => false
      }
    _ => false
  }
}

///|
/// fromRDF 文档入口（REC fromRdf；spec §8.130）
pub fn from_rdf_document(
  text : String,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let quads = match nq2_parse(text) {
    Ok(quads) => quads
    Err(m) => return Err(JsonLdError::InvalidValue("invalid N-Quads: " + m))
  }
  let use_native = options.use_native_types
  let use_rdf_type = options.use_rdf_type
  let rdf_direction = options.rdf_direction
  let default_graph : FromRdfGraph = FromRdfGraph::new()
  let named_graphs : Map[String, FromRdfGraph] = Map([])
  let graph_order : Array[String] = []
  // ① 全量入账
  for quad in quads {
    let pred = match quad.predicate {
      NqIriTerm(iri) => iri
      _ => return Err(JsonLdError::InvalidValue("invalid predicate term"))
    }
    let subj_key = nq2_term_key(quad.subject)
    let graph = match quad.graph {
      None => default_graph
      Some(graph_term) => {
        let graph_key = nq2_term_key(graph_term)
        match named_graphs.get(graph_key) {
          Some(graph) => graph
          None => {
            let fresh : FromRdfGraph = FromRdfGraph::new()
            named_graphs[graph_key] = fresh
            graph_order.push(graph_key)
            fresh
          }
        }
      }
    }
    if pred == from_rdf_type_iri && !use_rdf_type {
      match quad.object {
        NqIriTerm(type_iri) => {
          let node = graph.node(subj_key)
          if !node.types.contains(type_iri) {
            node.types.push(type_iri)
          }
        }
        _ =>
          return Err(JsonLdError::InvalidValue("rdf:type object must be IRI"))
      }
    } else {
      graph.append_prop(subj_key, pred, quad.object)
    }
  }
  // ② 形态集合（各图独立）：纯列表集合 + first 位引用集 + 跨图存在账
  let presence : Map[String, Map[String, Bool]] = Map([])
  for quad in quads {
    let gkey = match quad.graph {
      None => "@default"
      Some(graph_term) => nq2_term_key(graph_term)
    }
    match presence.get(nq2_term_key(quad.subject)) {
      Some(graphs) => graphs[gkey] = true
      None => {
        let fresh : Map[String, Bool] = Map([])
        fresh[gkey] = true
        presence[nq2_term_key(quad.subject)] = fresh
      }
    }
    match quad.object {
      NqIriTerm(iri) =>
        if iri != from_rdf_nil_iri {
          match presence.get(iri) {
            Some(graphs) => graphs[gkey] = true
            None => {
              let fresh : Map[String, Bool] = Map([])
              fresh[gkey] = true
              presence[iri] = fresh
            }
          }
        }
      NqBnodeTerm(label) =>
        match presence.get("_:" + label) {
          Some(graphs) => graphs[gkey] = true
          None => {
            let fresh : Map[String, Bool] = Map([])
            fresh[gkey] = true
            presence["_:" + label] = fresh
          }
        }
      NqLitTerm(_, _, _) => ()
    }
  }
  let first_refs : Map[String, Map[String, Bool]] = Map([])
  from_rdf_collect_first_refs(default_graph, "@default", first_refs)
  for graph_key in graph_order {
    match named_graphs.get(graph_key) {
      Some(graph) => from_rdf_collect_first_refs(graph, graph_key, first_refs)
      None => ()
    }
  }
  let is_10 = options.processing_mode is JsonLd10
  let default_ctx = from_rdf_graph_ctx_scoped(
    default_graph, "@default", first_refs, presence, is_10,
  )
  let named_ctx : Map[String, FromRdfGraphCtx] = Map([])
  for graph_key in graph_order {
    match named_graphs.get(graph_key) {
      Some(graph) =>
        named_ctx[graph_key] = from_rdf_graph_ctx_scoped(
          graph, graph_key, first_refs, presence, is_10,
        )
      None => ()
    }
  }
  // ③ 渲染：默认图节点（纯列表吸收不入成员）→ 具名图节点（@graph 位）
  let out : Array[JsonValue] = []
  let emitted : Map[String, Bool] = Map([])
  let compound_absorb : Map[String, Bool] = if rdf_direction
    is Some("compound-literal") {
    from_rdf_collect_compound(default_graph)
  } else {
    Map([])
  }
  let named_compound : Map[String, Map[String, Bool]] = Map([])
  if rdf_direction is Some("compound-literal") {
    for graph_key in graph_order {
      match named_graphs.get(graph_key) {
        Some(graph) =>
          named_compound[graph_key] = from_rdf_collect_compound(graph)
        None => ()
      }
    }
  }
  for key in default_ctx.graph.order {
    if default_ctx.pure_lists.contains(key) || compound_absorb.contains(key) {
      continue
    }
    out.push(
      match
        from_rdf_render_node(
          default_ctx, key, named_graphs, named_ctx, named_compound, use_native,
          rdf_direction,
        ) {
        Ok(jv) => jv
        Err(e) => return Err(e)
      },
    )
    emitted[key] = true
  }
  for graph_key in graph_order {
    if !emitted.contains(graph_key) {
      out.push(
        match
          from_rdf_render_node(
            default_ctx, graph_key, named_graphs, named_ctx, named_compound, use_native,
            rdf_direction,
          ) {
          Ok(jv) => jv
          Err(e) => return Err(e)
        },
      )
      emitted[graph_key] = true
    }
  }
  Ok(JsonValue::Array(out))
}

///|
/// 节点渲染（默认图性质 + @graph 位若该键为图名）
fn from_rdf_render_node(
  ctx : FromRdfGraphCtx,
  key : String,
  named_graphs : Map[String, FromRdfGraph],
  named_ctx : Map[String, FromRdfGraphCtx],
  named_compound : Map[String, Map[String, Bool]],
  use_native : Bool,
  rdf_direction : String?,
) -> Result[JsonValue, JsonLdError] {
  let node = ctx.graph.node(key)
  let pairs : Array[(String, JsonValue)] = [("@id", JsonValue::String(key))]
  if node.types.length() > 0 {
    let type_values : Array[JsonValue] = []
    for t in node.types {
      type_values.push(JsonValue::String(t))
    }
    pairs.push(("@type", JsonValue::Array(type_values)))
  }
  for pred in node.prop_order {
    match node.props.get(pred) {
      Some(terms) =>
        pairs.push(
          (
            pred,
            match
              from_rdf_render_terms(
                ctx.graph,
                ctx.pure_lists,
                terms,
                use_native,
                rdf_direction,
              ) {
              Ok(jv) => jv
              Err(e) => return Err(e)
            },
          ),
        )
      None => ()
    }
  }
  match named_graphs.get(key) {
    Some(graph) => {
      let member_ctx = match named_ctx.get(key) {
        Some(member_ctx) => member_ctx
        None => from_rdf_graph_ctx(graph, ctx.is_10)
      }
      let graph_arr : Array[JsonValue] = []
      let member_compound = match named_compound.get(key) {
        Some(compound) => compound
        None => Map([])
      }
      for member_key in member_ctx.graph.order {
        if member_ctx.pure_lists.contains(member_key) ||
          member_compound.contains(member_key) {
          continue
        }
        graph_arr.push(
          match
            from_rdf_render_member(
              member_ctx, member_key, use_native, rdf_direction,
            ) {
            Ok(jv) => jv
            Err(e) => return Err(e)
          },
        )
      }
      pairs.push(("@graph", JsonValue::Array(graph_arr)))
    }
    None => ()
  }
  Ok(JsonValue::Object(pairs))
}

///|
/// 具名图内容节点渲染
fn from_rdf_render_member(
  ctx : FromRdfGraphCtx,
  key : String,
  use_native : Bool,
  rdf_direction : String?,
) -> Result[JsonValue, JsonLdError] {
  let node = ctx.graph.node(key)
  let pairs : Array[(String, JsonValue)] = [("@id", JsonValue::String(key))]
  if node.types.length() > 0 {
    let type_values : Array[JsonValue] = []
    for t in node.types {
      type_values.push(JsonValue::String(t))
    }
    pairs.push(("@type", JsonValue::Array(type_values)))
  }
  for pred in node.prop_order {
    match node.props.get(pred) {
      Some(terms) =>
        pairs.push(
          (
            pred,
            match
              from_rdf_render_terms(
                ctx.graph,
                ctx.pure_lists,
                terms,
                use_native,
                rdf_direction,
              ) {
              Ok(jv) => jv
              Err(e) => return Err(e)
            },
          ),
        )
      None => ()
    }
  }
  Ok(JsonValue::Object(pairs))
}

///|
/// 值列渲染（term → JSON 值形；普通性质对象位纯列表头 → @list）
fn from_rdf_render_terms(
  graph : FromRdfGraph,
  pure : Map[String, Bool],
  terms : Array[NqTerm],
  use_native : Bool,
  rdf_direction : String?,
) -> Result[JsonValue, JsonLdError] {
  let values : Array[JsonValue] = []
  for term in terms {
    values.push(
      match
        from_rdf_render_term(
          graph,
          pure,
          term,
          use_native,
          rdf_direction,
          Map([]),
        ) {
        Ok(jv) => jv
        Err(e) => return Err(e)
      },
    )
  }
  Ok(JsonValue::Array(values))
}

///|
/// 单 term 渲染（引用形/字面形；nil = 空列表；复合字面吸收）
fn from_rdf_render_term(
  graph : FromRdfGraph,
  pure : Map[String, Bool],
  term : NqTerm,
  use_native : Bool,
  rdf_direction : String?,
  visiting : Map[String, Bool],
) -> Result[JsonValue, JsonLdError] {
  match term {
    NqIriTerm(iri) =>
      if iri == from_rdf_nil_iri {
        Ok(JsonValue::Object([("@list", JsonValue::Array([]))]))
      } else {
        Ok(JsonValue::Object([("@id", JsonValue::String(iri))]))
      }
    NqBnodeTerm(label) => {
      let ref_key = "_:" + label
      // 复合字面吸收（rdf_direction=compound-literal——di11/12）
      if rdf_direction is Some("compound-literal") {
        match from_rdf_compound_literal(graph, ref_key) {
          Some(value_object) => return Ok(value_object)
          None => ()
        }
      }
      if pure.contains(ref_key) {
        let items : Array[JsonValue] = []
        match
          from_rdf_walk_list(
            graph, ref_key, pure, use_native, rdf_direction, items, visiting,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        Ok(JsonValue::Object([("@list", JsonValue::Array(items))]))
      } else {
        Ok(JsonValue::Object([("@id", JsonValue::String(ref_key))]))
      }
    }
    NqLitTerm(value, datatype, language) =>
      from_rdf_render_literal(
        value, datatype, language, use_native, rdf_direction,
      )
  }
}

///|
/// 复合字面吸收（rdf_direction=compound-literal——di11/12）：节点恰
/// rdf:value + 可选 rdf:direction/rdf:language（各一、字面形、无型）⇒
/// 值对象折叠，bnode 不物化。非复合形 = None
fn from_rdf_compound_literal(graph : FromRdfGraph, key : String) -> JsonValue? {
  let node = match graph.nodes.get(key) {
    Some(node) => node
    None => return None
  }
  if node.types.length() > 0 {
    return None
  }
  let allowed : Map[String, Bool] = Map([])
  allowed[from_rdf_value_iri] = true
  allowed[from_rdf_direction_iri] = true
  allowed[from_rdf_language_iri] = true
  for pred in node.prop_order {
    if !allowed.contains(pred) {
      return None
    }
  }
  let value_terms = match node.props.get(from_rdf_value_iri) {
    Some(terms) => if terms.length() == 1 { terms } else { return None }
    None => return None
  }
  let mut value_text : String? = None
  let mut language : String? = None
  let mut direction : String? = None
  match value_terms[0] {
    NqLitTerm(value, None, None) => value_text = Some(value)
    _ => return None
  }
  match node.props.get(from_rdf_language_iri) {
    Some([NqLitTerm(lang, None, None)]) => language = Some(lang)
    _ => ()
  }
  match node.props.get(from_rdf_direction_iri) {
    Some([NqLitTerm(dir, None, None)]) => direction = Some(dir)
    _ => ()
  }
  let pairs : Array[(String, JsonValue)] = [
    ("@value", JsonValue::String(value_text.unwrap())),
  ]
  match language {
    Some(lang) => pairs.push(("@language", JsonValue::String(lang)))
    None => ()
  }
  match direction {
    Some(dir) => pairs.push(("@direction", JsonValue::String(dir)))
    None => ()
  }
  Some(JsonValue::Object(pairs))
}

///|
/// 字面形装配（@json = {@type:@json,@value:解析值}——解析失败 Err；native
/// 词形；langtag；非 xsd:string datatype；纯值）
fn from_rdf_render_literal(
  value : String,
  datatype : String?,
  language : String?,
  use_native : Bool,
  rdf_direction : String?,
) -> Result[JsonValue, JsonLdError] {
  match datatype {
    Some(dt) =>
      if dt == from_rdf_json_datatype {
        return match parse_json(value) {
          Ok(parsed) =>
            Ok(
              JsonValue::Object([
                ("@type", JsonValue::String("@json")),
                ("@value", parsed),
              ]),
            )
          Err(_) => Err(JsonLdError::InvalidValue("invalid JSON literal"))
        }
      }
    None => ()
  }
  // i18n 方向 datatype（rdf_direction=i18n-datatype——di05/06）：
  // https://www.w3.org/ns/i18n#<lang>_<dir> ⇒ @direction (+@language)，
  // datatype 剥除
  if rdf_direction is Some("i18n-datatype") {
    match datatype {
      Some(dt) =>
        if dt.length() > from_i18n_datatype_prefix.length() &&
          index_of_str_prefix(dt, from_i18n_datatype_prefix) {
          let suffix = dt[from_i18n_datatype_prefix.length():].to_owned()
          // 尾 '_' 切 lang/dir（dir = ltr/rtl；lang 可空可含 '-'）
          let mut split_at : Int? = None
          for i in 0..<suffix.length() {
            if suffix[i] == 95 {
              split_at = Some(i)
            }
          }
          match split_at {
            Some(at) => {
              let lang = suffix[:at].to_owned()
              let dir = suffix[at + 1:].to_owned()
              if dir == "ltr" || dir == "rtl" {
                let pairs : Array[(String, JsonValue)] = []
                pairs.push(("@value", JsonValue::String(value)))
                if lang != "" {
                  pairs.push(("@language", JsonValue::String(lang)))
                }
                pairs.push(("@direction", JsonValue::String(dir)))
                return Ok(JsonValue::Object(pairs))
              }
            }
            None => ()
          }
        }
      None => ()
    }
  }
  if use_native {
    match datatype {
      Some(dt) => {
        // xsd:boolean 词形空间 = true/false/1/0（t0027 boolean-number 面）
        if dt == "http://www.w3.org/2001/XMLSchema#boolean" {
          if value == "true" || value == "1" {
            return Ok(JsonValue::Object([("@value", JsonValue::Bool(true))]))
          }
          if value == "false" || value == "0" {
            return Ok(JsonValue::Object([("@value", JsonValue::Bool(false))]))
          }
          // 词形外（True/False/notnative）→ typed 字面回落
        }
        // native 数值面 = integer/double（decimal 不在 REC useNativeTypes
        // 列——t0018）；词形非法（溢出/INF/notnative）→ typed 回落
        if dt == "http://www.w3.org/2001/XMLSchema#integer" ||
          dt == "http://www.w3.org/2001/XMLSchema#double" {
          match parse_json(value) {
            Ok(JsonValue::Number(num)) =>
              // 溢出词形（0.1e999…→Infinity）= 非词形回落（t0027）；
              // 判定 = |num| != Infinity（num - num 对 NaN/Inf 恒非零）
              if !num.is_nan() && !num.is_inf() {
                return Ok(
                  JsonValue::Object([("@value", JsonValue::Number(num))]),
                )
              }
            _ => ()
          }
        }
      }
      None => ()
    }
  }
  match language {
    Some(lang) =>
      return Ok(
        JsonValue::Object([
          ("@value", JsonValue::String(value)),
          ("@language", JsonValue::String(lang)),
        ]),
      )
    None => ()
  }
  match datatype {
    Some(dt) =>
      if dt != from_xsd_string {
        return Ok(
          JsonValue::Object([
            ("@value", JsonValue::String(value)),
            ("@type", JsonValue::String(dt)),
          ]),
        )
      }
    None => ()
  }
  Ok(JsonValue::Object([("@value", JsonValue::String(value))]))
}

///|
/// 前缀判定（dt 头部 == prefix）
fn index_of_str_prefix(dt : String, prefix : String) -> Bool {
  if dt.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if dt[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// 纯列表节点判据（t0004/0010/0011/0012/0013/0016 语义钉）：恰 first+rest
/// 各一、无他性质、types ⊆ {rdf:List}（带 rdf:List 型链仍转——t0016）；
/// rest 链终 nil（环 = 否；rest 字面 = 否）
fn from_rdf_is_pure_list(
  graph : FromRdfGraph,
  key : String,
  visiting : Map[String, Bool],
) -> Bool {
  if visiting.contains(key) {
    return false // 环（t0012）
  }
  // 纯列表头限 bnode 键（t0009——IRI 键列表节点 = 常规节点物化）
  if !(key.length() > 2 && key[0] == 95 && key[1] == 58) {
    return false
  }
  let node = match graph.nodes.get(key) {
    Some(node) => node
    None => return false
  }
  // types ⊆ {rdf:List}（t0016——rdf:List 型链照转；他型 = 否）
  for t in node.types {
    if t != from_rdf_list_type {
      return false
    }
  }
  if node.prop_order.length() != 2 {
    return false // 有他性质（t0011）或缺 first/rest 位
  }
  match
    (node.props.get(from_rdf_first_iri), node.props.get(from_rdf_rest_iri)) {
    (Some(first_values), Some(rest_values)) =>
      if first_values.length() != 1 || rest_values.length() != 1 {
        return false // 多 rdf:first（t0013）等
      }
    _ => return false
  }
  // rest 对象判定：nil = 链终；bnode/IRI = 递归（须同图纯列表）
  match node.props.get(from_rdf_rest_iri) {
    Some([rest_term]) =>
      match rest_term {
        NqIriTerm(iri) => iri == from_rdf_nil_iri
        NqBnodeTerm(label) => {
          let next_key = "_:" + label
          if next_key == key {
            false
          } else {
            visiting[key] = true
            let result = from_rdf_is_pure_list(graph, next_key, visiting)
            visiting.remove(key)
            result
          }
        }
        NqLitTerm(_, _, _) => false
      }
    _ => false
  }
}

///|
/// 链行走收值（纯列表头已判——first 位 {@id}/@value 形 + first 位列表节
/// 点物化递归、rest 续走；nil 止）
fn from_rdf_walk_list(
  graph : FromRdfGraph,
  key : String,
  pure : Map[String, Bool],
  use_native : Bool,
  rdf_direction : String?,
  items : Array[JsonValue],
  visiting : Map[String, Bool],
) -> Result[Unit, JsonLdError] {
  if visiting.contains(key) {
    return Err(JsonLdError::InvalidValue("list cycle"))
  }
  visiting[key] = true
  let node = match graph.nodes.get(key) {
    Some(node) => node
    None => return Err(JsonLdError::InvalidValue("list node missing"))
  }
  match node.props.get(from_rdf_first_iri) {
    Some([first_term]) =>
      match first_term {
        // nil = 空列表项（tli01）；纯列表头引用 = 嵌套 @list（tli02——
        // _:a/_:b 单节链嵌套转）；first 位多节链/非纯 = {@id} 物化（t0008
        // ——lista/b1/c1 面吸收豁免+物化）
        NqIriTerm(iri) =>
          if iri == from_rdf_nil_iri {
            items.push(JsonValue::Object([("@list", JsonValue::Array([]))]))
          } else if pure.contains(iri) {
            let nested : Array[JsonValue] = []
            match
              from_rdf_walk_list(
                graph, iri, pure, use_native, rdf_direction, nested, visiting,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
            items.push(JsonValue::Object([("@list", JsonValue::Array(nested))]))
          } else {
            items.push(JsonValue::Object([("@id", JsonValue::String(iri))]))
          }
        NqBnodeTerm(label) => {
          let ref_key = "_:" + label
          if pure.contains(ref_key) {
            let nested : Array[JsonValue] = []
            match
              from_rdf_walk_list(
                graph, ref_key, pure, use_native, rdf_direction, nested, visiting,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
            items.push(JsonValue::Object([("@list", JsonValue::Array(nested))]))
          } else {
            items.push(JsonValue::Object([("@id", JsonValue::String(ref_key))]))
          }
        }
        NqLitTerm(value, datatype, language) =>
          match
            from_rdf_render_literal(
              value, datatype, language, use_native, rdf_direction,
            ) {
            Ok(jv) => items.push(jv)
            Err(e) => return Err(e)
          }
      }
    _ => return Err(JsonLdError::InvalidValue("list node missing rdf:first"))
  }
  match node.props.get(from_rdf_rest_iri) {
    Some([rest_term]) =>
      match rest_term {
        NqIriTerm(iri) =>
          if iri == from_rdf_nil_iri {
            Ok(())
          } else {
            // rest 指 IRI——纯列链内已判 IRI 链节；防御直落
            Ok(())
          }
        NqBnodeTerm(label) => {
          let next_key = "_:" + label
          if next_key == key {
            Err(JsonLdError::InvalidValue("list cycle"))
          } else {
            from_rdf_walk_list(
              graph, next_key, pure, use_native, rdf_direction, items, visiting,
            )
          }
        }
        NqLitTerm(_, _, _) =>
          Err(JsonLdError::InvalidValue("list rest must be bnode or nil"))
      }
    _ => Err(JsonLdError::InvalidValue("list node missing rdf:rest"))
  }
}

///|
/// first 位引用收集（rdf:first 值位的节点键集——吸收豁免判定面）
fn from_rdf_collect_first_refs(
  graph : FromRdfGraph,
  graph_key : String,
  first_refs : Map[String, Map[String, Bool]],
) -> Unit {
  for key in graph.order {
    let node = match graph.nodes.get(key) {
      Some(node) => node
      None => continue
    }
    let first_terms = match node.props.get(from_rdf_first_iri) {
      Some(terms) => terms
      None => continue
    }
    for term in first_terms {
      let ref_key = match term {
        NqIriTerm(iri) => if iri != from_rdf_nil_iri { iri } else { continue }
        NqBnodeTerm(label) => "_:" + label
        NqLitTerm(_, _, _) => continue
      }
      match first_refs.get(ref_key) {
        Some(graphs) => graphs[graph_key] = true
        None => {
          let fresh : Map[String, Bool] = Map([])
          fresh[graph_key] = true
          first_refs[ref_key] = fresh
        }
      }
    }
  }
}

///|
/// 复合字面节点集合（rdf_direction=compound-literal——渲染循环吸收面）
fn from_rdf_collect_compound(graph : FromRdfGraph) -> Map[String, Bool] {
  let compound : Map[String, Bool] = Map([])
  for key in graph.order {
    if from_rdf_compound_literal(graph, key) is Some(_) {
      compound[key] = true
    }
  }
  compound
}
