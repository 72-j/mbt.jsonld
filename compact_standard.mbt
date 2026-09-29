///|
/// compaction 序列化器（J6——spec §8.41/§8.42）：expand 逆面，逐值递归、无
/// 节点字典面（F2 禁复用——§8.41 钉一）。落地面 = 精确 term / 最长前缀
/// compact IRI / base 相对化（段界对齐）/ datatype+language 吸收 / 裸值缺省
/// 塌缩 / @id-term 串塌缩 / @list 吸收 + @set 保形 + 数组塌缩 / 值去重 /
/// @reverse 正向提升（reverse term 匹配）/ @nest 重嵌 / @graph·@index 面 /
/// 顶层形三钉（0 → {} / 1 → 单对象 / n → @graph 包裹）/ @context 原文发射。
/// 未实现面（deferred 在册）：scoped context 压缩面（type-scoped/property-
/// scoped term 选择——#tc001/#tc013 族）、容器逆形分组（@index/@id/@type/
/// @language/@graph 容器——#tm001/#tla01 族）、@nest 链式/别名细化。

///|
/// term 名确定性序（同 IRI 多候选——Map 迭代序不定，选取须可复现）：
/// 容器缺省优先 → 名短优先 → 字典序。`want_reverse` 分选：正向位匹配 td.iri，
/// 反转位匹配 td.reverse（@reverse 正向提升——#t0033/#t0050 oracle）
fn compact_term_candidates(
  pred : String,
  want_reverse : Bool,
  active : ActiveContext,
) -> Array[String] {
  let names : Array[String] = []
  for pair in active.terms {
    let hit = if want_reverse {
      // 反转位：td.reverse 匹配（@reverse term 的 iri 同载反转 IRI——
      // 不以 iri 有无分流；#t0033/#t0050 oracle）
      match pair.1.reverse {
        Some(riri) => riri == pred
        None => false
      }
    } else {
      // 正向位：iri 匹配且非 reverse-bearing（反转 term 不作正向键——语义翻转）
      match pair.1.iri {
        Some(iri) => iri == pred && pair.1.reverse is None
        None => false
      }
    }
    if hit {
      names.push(pair.0)
    }
  }
  names.sort_by(fn(a, b) {
    let ca = match active.terms.get(a) {
      Some(td) => if td.container is None { 0 } else { 1 }
      None => 2
    }
    let cb = match active.terms.get(b) {
      Some(td) => if td.container is None { 0 } else { 1 }
      None => 2
    }
    if ca != cb {
      return ca - cb
    }
    let la = a.length()
    let lb = b.length()
    if la != lb {
      return la - lb
    }
    a.compare(b)
  })
  names
}

///|
/// IRI 压缩（REC §6.3 首波子集）：精确 term → 最长前缀 compact IRI（term 名
/// 不含 "/"、is_prefix 未显式抑制、@keyword 别名跳过）→ base 相对化
/// （compactToRelative 门 + 段界对齐）→ 原样
fn compact_iri_word(
  iri : String,
  allow_exact : Bool,
  allow_vocab : Bool,
  active : ActiveContext,
  options : JsonLdOptions,
) -> String {
  // 精确 term（容器缺省优先；allow_exact=false = 失配兜底位——term 不可用，
  // #t0006 oracle：datatype 失配 term 不作键，落前缀词）
  if allow_exact {
    let exact = compact_term_candidates(iri, false, active)
    if exact.length() > 0 {
      return exact[0]
    }
  }
  // 最长前缀 compact IRI
  let mut best_prefix : String? = None
  let mut best_name : String? = None
  for pair in active.terms {
    let name = pair.0
    match pair.1.iri {
      Some(pfx) =>
        if pfx.length() < iri.length() &&
          iri.has_prefix(pfx) &&
          name.contains("/") is false &&
          name.contains("@") is false &&
          // 前缀资格闸（REC 4.2.2——1.1：@prefix 显式 true，或简单 string 形
          // 缺省 true；map 形缺省 false——#tp001 oracle）
          (
            pair.1.is_prefix is Some(true) ||
            (pair.1.is_prefix is None &&
            pair.1.simple_form &&
            // 映射词尾闸（§8.46 精化——简单形隐式资格受词尾约束；@prefix:true
            // 显式豁免词尾——#tp003 oracle 落闸 vs #tp005/#tp006 oracle
            // @prefix:true 过闸：mapping 尾 '-' 照压缩）
            (match pair.1.iri {
              Some(pfx_word) =>
                match pfx_word.get_char(pfx_word.length() - 1) {
                  Some(':') | Some('/') | Some('?') | Some('#') | Some('[') |
                  Some(']') | Some('@') => true
                  _ => false
                }
              None => false
            }))
          ) {
          match best_prefix {
            Some(bp) =>
              if pfx.length() > bp.length() {
                best_prefix = Some(pfx)
                best_name = Some(name)
              }
            None => {
              best_prefix = Some(pfx)
              best_name = Some(name)
            }
          }
        }
      None => ()
    }
  }
  match (best_name, best_prefix) {
    (Some(name), Some(pfx)) => {
      let suffix = iri[pfx.length():].to_owned()
      // compact IRI = 词形原样拼接（REC：suffix 原样）
      return name + ":" + suffix
    }
    _ => ()
  }
  // @vocab 相对词形（#t0021 oracle：@vocab "http://example.com/subdir/" +
  // "…/subdir/vocab/embed" → "vocab/embed"——仅谓词/类型位；@id 值位禁，
  // allow_vocab=false）
  if allow_vocab {
    match active.vocab {
      Some(vocab) =>
        if vocab.length() < iri.length() && iri.has_prefix(vocab) {
          return iri[vocab.length():].to_owned()
        }
      None => ()
    }
  }
  // base 相对化（compactToRelative 门——×1 件保绝对词面；段界对齐：base 尾
  // 无 "/" 补一段再对前缀，防 "http://example.com" vs "…/com/foo" 误剥——
  // #tr001 oracle：option base "http://example.org/" → "@id":"a"）
  if options.compact_to_relative {
    match active.base {
      Some(base) => {
        let boundary = match base.get_char(base.length() - 1) {
          Some('/') => base
          _ => base + "/"
        }
        if boundary.length() < iri.length() && iri.has_prefix(boundary) {
          return iri[boundary.length():].to_owned()
        }
      }
      None => ()
    }
  }
  iri
}

///|
/// 值适配判定（两遍分选核心——同 IRI 多 term 按值拆键：#t0006 datatype 失配
/// term 弃用落前缀词、#t0015 五 term 按值归组、#t0002 纯 term 容语言值对象）：
/// bare_fit = 该 term 可把值吸成裸形（datatype/language 吸收、@list 容器吸收、
/// @id-term 串塌缩、纯 term 语言态对齐）；object_fit = 值对象形在本 term 下
/// 重展开安全（@type/@language 钉死在对象内——#t0002 term2/term3 oracle）
fn compact_bare_fit(
  value : ExpandedValue,
  td : TermDefinition,
  active : ActiveContext,
) -> Bool {
  match value {
    ExpandedValue::List(items) => {
      if td.container is Some(List) {
        // 方向感知选择（§8.48——td 带方向映射时首项方向须合：
        // #tdi03 oracle——同 IRI 双 list term 按 ltr/rtl 分选）
        match td.direction_mapping {
          Some(Set(d)) =>
            match items.get(0) {
              Some(ExpandedValue::Value(lit)) => lit.direction == Some(d)
              _ => true
            }
          _ => true
        }
      } else {
        false
      }
    }
    ExpandedValue::Node(child) => {
      let id_only = child.types.is_empty() &&
        child.properties.is_empty() &&
        child.reverse_props.is_empty() &&
        child.graph is None &&
        child.included is None &&
        child.index is None
      if !id_only {
        return false
      }
      match td.datatype {
        Some("@id") | Some("@vocab") => true
        _ => false
      }
    }
    ExpandedValue::Value(lit) => {
      // 方向态对齐总闸（§8.48——方向不合者不入 bare，与语言态同判据：
      // 裸形重展开由 term/缺省注回同向才安全——#tdi01/#tdi07 oracle）
      let dir_aligned = match td.direction_mapping {
        Some(Set(d)) => lit.direction == Some(d)
        Some(Null) => lit.direction is None
        None =>
          match lit.direction {
            Some(d) => d == active.default_direction.unwrap_or("")
            None => active.default_direction is None
          }
      }
      if !dir_aligned {
        return false
      }
      match td.datatype {
        Some(dt) => {
          if dt is ("@id" | "@vocab") {
            // @id 型 term 对字面量无吸收面（裸串重展开会被强转）——不计 bare
            return false
          }
          match lit.datatype {
            Some(ldt) => ldt == dt
            None => false
          }
        }
        None =>
          // 无 datatype 的 term：language 吸收臂
          match td.language_mapping {
            Some(Set(lang)) =>
              match lit.language {
                Some(l) => l == lang
                None => false
              }
            Some(Null) => lit.language is None
            None =>
              // 纯 term：语言态对齐 = 值语言 == context 缺省语言（裸形重展开
              // 带回缺省语言——失配即不安全）
              match lit.language {
                Some(lang) => lang == active.default_language.unwrap_or("")
                None => active.default_language is None
              }
          }
      }
    }
  }
}

///|
/// 值适配判定·对象形（值对象形在本 term 下重展开安全）：@type/@language 钉死
/// 在值对象内不随 term 强转——#t0002 term2/term3 oracle（纯 term 容
/// datatype/language 值对象）
fn compact_object_fit(
  value : ExpandedValue,
  td : TermDefinition,
  _active : ActiveContext,
) -> Bool {
  match value {
    // @list 值对象恒安全（重展开保 @list 形）
    ExpandedValue::List(_) => true
    // 节点值：@id 型 term（非裸引用亦安全——对象形重展开仍为节点）；无
    // datatype 的 term 对象形安全；datatype 版 term 冲突不可用
    // （#t0006 term2 oracle：裸引用对象形落回 term 键）
    ExpandedValue::Node(_) =>
      match td.datatype {
        Some(dt) => dt is ("@id" | "@vocab")
        None => true
      }
    ExpandedValue::Value(lit) => {
      // 方向态对齐总闸（§8.48——与 bare_fit 同判据；方向不合者对象形也
      // 不入 term，落残余兜底键——#tdi07 oracle）
      let dir_aligned = match td.direction_mapping {
        Some(Set(d)) => lit.direction == Some(d)
        Some(Null) => lit.direction is None
        None =>
          match lit.direction {
            Some(d) => d == _active.default_direction.unwrap_or("")
            None => _active.default_direction is None
          }
      }
      if !dir_aligned {
        return false
      }
      match td.datatype {
        // @id 型 term + 字面量：值对象形不被强转（仅裸串强转）——安全
        Some("@id") | Some("@vocab") => true
        // datatype 版 term 与值态失配 → 无形可用（#t0006 oracle）
        Some(_) => false
        None =>
          match td.language_mapping {
            // language 版 term 与值语言态失配 → 无形可用
            Some(_) => false
            // 纯 term：对象形可用的残域 = datatype 在场（钉 @type——
            // #t0002 term2 oracle）或 language 在场（钉 @language——
            // #t0002 term3 oracle）；纯串无修饰时对象形重展开仍会被注入
            // 缺省语言 → 不安全（#t0015 plain literal oracle）
            None => lit.datatype is Some(_) || lit.language is Some(_)
          }
      }
      }
  }
}

///|
/// 值压缩（REC §6.4 首波子集）：td datatype 吸收 → 裸 raw；td language 吸收
/// → 裸串；缺省臂无 datatype（或 xsd:string）、无 language/direction/index
/// 的纯 @value 值对象 → 裸值（#t0009 oracle）；否则值对象形（@type 压缩
/// 词形 + @language/@direction/@index 保留）
fn compact_value_jv(
  literal : ExpandedLiteral,
  td_opt : TermDefinition?,
  active : ActiveContext,
  options : JsonLdOptions,
) -> JsonValue {
  match td_opt {
    Some(td) => {
      // datatype 吸收（raw 保形——数值/布尔原样）
      match (td.datatype, literal.datatype) {
        (Some(dt), Some(ldt)) =>
          if dt == ldt {
            return match literal.raw {
              Some(raw) => raw
              None => JsonValue::String(literal.value)
            }
          }
        _ => ()
      }
      // language 吸收（串值裸形；方向态须合——§8.48 同判据）
      match td.language_mapping {
        Some(Set(lang)) =>
          match literal.language {
            Some(l) =>
              if l == lang {
                let dir_ok = match td.direction_mapping {
                  Some(Set(d)) => literal.direction == Some(d)
                  Some(Null) => literal.direction is None
                  None => true
                }
                if dir_ok {
                  return JsonValue::String(literal.value)
                }
              }
            None => ()
          }
        _ => ()
      }
      // direction 吸收（串值裸形——§8.48 #tdi03 oracle：list 项 @direction
      // 合 td 方向映射即裸形，重展开注回同向）
      match td.direction_mapping {
        Some(Set(d)) =>
          if literal.direction == Some(d) {
            return JsonValue::String(literal.value)
          }
        Some(Null) =>
          if literal.direction is None {
            return JsonValue::String(literal.value)
          }
        None => ()
      }
    }
    None => ()
  }
  let bare_datatype = match literal.datatype {
    Some(dt) => dt == "http://www.w3.org/2001/XMLSchema#string"
    None => true
  }
  // 语言态对齐（#t0015 v1 oracle——de 值在缺省 de 下裸形重展开带回同语言，
  // 安全；纯串无修饰且缺省在场则对象形也不安全，分选层已拒）
  let language_aligned = match literal.language {
    Some(lang) => lang == active.default_language.unwrap_or("")
    None => active.default_language is None
  }
  if bare_datatype &&
    language_aligned &&
    literal.direction is None &&
    literal.index is None {
    return match literal.raw {
      Some(raw) => raw
      None => JsonValue::String(literal.value)
    }
  }
  let pairs : Array[(String, JsonValue)] = [
    (
      "@value",
      match literal.raw {
        Some(raw) => raw
        None => JsonValue::String(literal.value)
      },
    ),
  ]
  match literal.datatype {
    Some(dt) =>
      // xsd:string 缺省 @type 不发（REC 值压缩）；其余压缩词形保留
      if dt != "http://www.w3.org/2001/XMLSchema#string" {
        pairs.push(
          (
            "@type",
            JsonValue::String(compact_iri_word(dt, true, true, active, options)),
          ),
        )
      }
    None => ()
  }
  // @language/@direction 走别名键（#tdi02 oracle——"direction":"@direction"
  // → 键 "direction"；无别名回落关键字字面）
  let lang_key = compact_iri_word("@language", true, false, active, options)
  let dir_key = compact_iri_word("@direction", true, false, active, options)
  match literal.language {
    Some(lang) => pairs.push((lang_key, JsonValue::String(lang)))
    None => ()
  }
  match literal.direction {
    Some(dir) => pairs.push((dir_key, JsonValue::String(dir)))
    None => ()
  }
  match literal.index {
    Some(ix) => pairs.push(("@index", JsonValue::String(ix)))
    None => ()
  }
  JsonValue::Object(pairs)
}

///|
/// 单值压缩分发（节点引用串塌缩：@id-only 子节点 + td @type @id/@vocab →
/// 压缩词串；否则子节点递归对象形）
fn compact_value_item(
  value : ExpandedValue,
  td_opt : TermDefinition?,
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  // property-scoped context 套用（压缩面——tc001/tc013 族：td @context 在
  // 节点有效链之上套用，值渲染全走此链；套用失败回退——定义期已校验）
  let active : ActiveContext = match td_opt {
    Some(td) =>
      match td.local_context {
        Some(lc) =>
          match
            ContextProcessor::process_context(
              StandardExpander::{ },
              active,
              lc,
              ContextFlags::property_scoped(),
              options,
            ) {
            Ok(c) => c
            Err(_) => active
          }
        None => active
      }
    None => active
  }
  match value {
    ExpandedValue::Node(child) => {
      let id_only = child.types.is_empty() &&
        child.properties.is_empty() &&
        child.reverse_props.is_empty() &&
        child.graph is None &&
        child.included is None &&
        child.index is None
      if id_only {
        match child.id {
          Some(id) =>
            match td_opt {
              // @id/@vocab 型 term（@type 三形态）→ 串塌缩（#t0005 term2 oracle）
              Some(td) =>
                match td.datatype {
                  Some("@id") =>
                    return Ok(
                      JsonValue::String(
                        compact_iri_word(id, false, false, active, options),
                      ),
                    )
                  // @vocab 型塌缩走 vocab 相对词（#tc013 oracle："buzz"；
                  // 重展开 vocab 拼回同形）
                  Some("@vocab") =>
                    return Ok(
                      JsonValue::String(
                        compact_iri_word(id, false, true, active, options),
                      ),
                    )
                  _ => ()
                }
              None => ()
            }
          None => ()
        }
        // 对象形：{"@id": 压缩词}
        let word = match child.id {
          Some(id) => compact_iri_word(id, false, false, active, options)
          None => ""
        }
        return Ok(JsonValue::Object([("@id", JsonValue::String(word))]))
      }
      compact_node_jv(child, active, options)
    }
    ExpandedValue::Value(literal) =>
      Ok(compact_value_jv(literal, td_opt, active, options))
    ExpandedValue::List(items) => {
      // @list 容器吸收（td @container @list → 裸数组——#t0015 term4 oracle）；
      // 1.0 嵌套 list = compaction to list of lists 错（#te001 oracle）；
      // 无容器 → @list 值对象形
      let is_list_container = match td_opt {
        Some(td) => td.container is Some(List)
        None => false
      }
      let arr : Array[JsonValue] = []
      for it in items {
        if it is ExpandedValue::List(_) && options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidList("compaction to list of lists"))
        }
        match compact_value_item(it, td_opt, active, options) {
          Ok(jv) => arr.push(jv)
          Err(e) => return Err(e)
        }
      }
      if is_list_container {
        return Ok(JsonValue::Array(arr))
      }
      Ok(JsonValue::Object([("@list", JsonValue::Array(arr))]))
    }
  }
}

///|
/// 值数组压缩（容器旗 + 去重 + 塌缩）：@list 容器吸收（单 List 值 → 裸数组，
/// 1.0 嵌套 list = compaction to list of lists 错）；@set 保形；非容器单值
/// 塌缩（compactArrays 门）；同形值去重
fn compact_property_values(
  vals : Array[ExpandedValue],
  td_opt : TermDefinition?,
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  // @list 容器吸收（#te001[1.0] oracle：嵌套 list = compaction to list of lists）
  match td_opt {
    Some(td) =>
      if td.container is Some(List) {
        if vals.length() == 1 {
          match vals[0] {
            ExpandedValue::List(items) => {
              let arr : Array[JsonValue] = []
              for it in items {
                if it is ExpandedValue::List(_) &&
                  options.processing_mode is JsonLd10 {
                  return Err(
                    JsonLdError::InvalidList("compaction to list of lists"),
                  )
                }
                match compact_value_item(it, td_opt, active, options) {
                  Ok(jv) => arr.push(jv)
                  Err(e) => return Err(e)
                }
              }
              return Ok(JsonValue::Array(arr))
            }
            _ => ()
          }
        }
      }
    None => ()
  }
  let mut keep_array = match td_opt {
    Some(td) => td.container is Some(Set)
    None => false
  }
  if !options.compact_arrays {
    keep_array = true
  }
  let vals_jv : Array[JsonValue] = []
  let seen : Map[String, Bool] = Map([])
  for v in vals {
    match compact_value_item(v, td_opt, active, options) {
      Ok(jv) => {
        let key = jv_render(jv)
        if !seen.contains(key) {
          seen[key] = true
          vals_jv.push(jv)
        }
      }
      Err(e) => return Err(e)
    }
  }
  if !keep_array && vals_jv.length() == 1 {
    return Ok(vals_jv[0])
  }
  Ok(JsonValue::Array(vals_jv))
}

///|
/// 属性对压缩（term 选择 + 值数组；键 = term 名或压缩 IRI）——正向与反转对
/// 共用（反转位 term 选择走 td.reverse 匹配）
fn compact_property_pair(
  pred : String,
  want_reverse : Bool,
  vals : Array[ExpandedValue],
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[(String, JsonValue), JsonLdError] {
  let cands = compact_term_candidates(pred, want_reverse, active)
  let td_opt : TermDefinition? = match cands {
    cs if cs.length() > 0 => active.terms.get(cs[0])
    _ => None
  }
  let key = match cands {
    cs if cs.length() > 0 => cs[0]
    _ => compact_iri_word(pred, true, true, active, options)
  }
  match compact_property_values(vals, td_opt, active, options) {
    Ok(jv) => Ok((key, jv))
    Err(e) => Err(e)
  }
}

///|
/// 节点压缩：@id（压缩词）/ @type（压缩词 + 塌缩）/ 属性（@nest 重嵌——
/// td.nest 组账）/ @index / @graph（内容恒数组——#compact-t0039 oracle 单例
/// 不解包）/ @reverse（正向提升——reverse term 匹配即普通属性；无匹配保
/// 包裹形）
fn compact_node_jv(
  node : ExpandedNode,
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  // type-scoped 套用（压缩面——双链分立，#tc009 vs #tc013 同形异判对 oracle：
  // type-scoped 定义的 term **只作键名**、 datatype/container/language 不参与
  // 值成形；property-scoped 全参与。scoped = 键选择链；active（outer）=
  // 值成形链）
  let scoped = compact_apply_type_scoped(node.types, active, options)
  let pairs : Array[(String, JsonValue)] = []
  // @id 键走 term 词形（关键字别名 term——#t0008 oracle："uri":"@id" →
  // "uri" 作键；无别名回落 "@id" 字面）
  let id_key = compact_iri_word("@id", true, false, scoped, options)
  match node.id {
    Some(id) =>
      pairs.push(
        (
          id_key,
          JsonValue::String(compact_iri_word(id, true, false, active, options)),
        ),
      )
    None => ()
  }
  if node.types.length() > 0 {
    let types : Array[JsonValue] = []
    for t in node.types {
      types.push(
        JsonValue::String(compact_iri_word(t, true, true, active, options)),
      )
    }
    if options.compact_arrays && types.length() == 1 {
      pairs.push(("@type", types[0]))
    } else {
      pairs.push(("@type", JsonValue::Array(types)))
    }
  }
  // @nest 归组账（td.nest → 组内 pairs——#tn001 oracle："p2":{"@nest":
  // "@nest"} → "@nest":{"p2":"v2"}；nest 键 = 关键字位原样 / term 名原样）
  let nest_groups : Map[String, Array[(String, JsonValue)]] = Map([])
  let nest_order : Array[String] = []
  // 正向属性：值感知分选（同 IRI 多 term 按值拆键——#t0006/#t0015 oracle；
  // 两遍 = bare_fit 优先、object_fit 次之、残余落前缀/相对词兜底键）+
  // 容器逆形映射归组路由（§8.43——单映射容器 term 成批机制）
  for pair in node.properties {
    let cands = compact_term_candidates(pair.0, false, scoped)
    let cand_tds : Array[(String, TermDefinition)] = []
    for name in cands {
      match scoped.terms.get(name) {
        Some(td) => cand_tds.push((name, td))
        None => ()
      }
    }
    // 映射容器候选（单 @index/@id/@type/@language——§8.43 共性路由位）
    let map_tds : Array[(String, TermDefinition)] = []
    for entry in cand_tds {
      let is_map = match entry.1.container {
        Some(Id) | Some(Type) | Some(Index) | Some(Language) => true
        _ => false
      }
      if is_map && entry.1.graph_secondary is None {
        map_tds.push(entry)
      }
    }
    // @graph 容器候选（§8.45——container=Graph，次级 Id/Index/None）
    let mut graph_td : (String, TermDefinition)? = None
    for entry in cand_tds {
      if entry.1.container is Some(Graph) {
        graph_td = Some(entry)
        break
      }
    }
    // 图归组账（次级键 → 内容数组；裸次级 → 内容数组直列）
    let graph_subs : Array[(String, Array[JsonValue])] = []
    let graph_bares : Array[JsonValue] = []
    // 映射归组账（term 键 → (subkey, 渲染值) 列表；首现序）
    let map_names : Array[String] = []
    let map_subs : Map[String, Array[(String, JsonValue)]] = Map([])
    for entry in map_tds {
      map_names.push(entry.0)
      map_subs[entry.0] = []
    }
    // 分组账：键 → 值数组（首现序）
    let group_keys : Array[String] = []
    let group_vals : Map[String, Array[JsonValue]] = Map([])
    let group_array : Map[String, Bool] = Map([])
    let group_tds : Map[String, TermDefinition] = Map([])
    let leftovers : Array[JsonValue] = []
    for v in pair.1 {
      // @graph 容器路由优先（§8.45——图载体值；次级定归组键）
      let mut graph_done = false
      match graph_td {
        Some((_, gtd)) =>
          match v {
            ExpandedValue::Node(child) =>
              match child.graph {
                Some(items) => {
                  let content : Array[JsonValue] = []
                  for it in items {
                    match it {
                      ExpandedValue::Node(sub) =>
                        match compact_node_jv(sub, active, options) {
                          Ok(jv) => content.push(jv)
                          Err(e) => return Err(e)
                        }
                      _ => ()
                    }
                  }
                  let none_key = compact_iri_word(
                    "@none",
                    true,
                    false,
                    active,
                    options,
                  )
                  match gtd.graph_secondary {
                    Some(Id) => {
                      let subkey = match child.id {
                        Some(id) =>
                          compact_iri_word(id, false, false, active, options)
                        None => none_key
                      }
                      graph_subs.push((subkey, content))
                    }
                    Some(Index) => {
                      let subkey = match child.index {
                        Some(ix) => ix
                        None => none_key
                      }
                      graph_subs.push((subkey, content))
                    }
                    Some(List) | Some(Set) | Some(Language) | Some(Type) | Some(Graph) => ()
                    None => graph_bares.push(JsonValue::Array(content))
                  }
                  graph_done = true
                }
                None => ()
              }
            _ => ()
          }
        None => ()
      }
      if graph_done {
        continue
      }
      // 映射归组优先（§8.43——值 fit 映射容器即归组；不适值照旧分选）
      let mut map_done = false
      for entry in map_tds {
        match compact_map_entry(v, entry.1, active, options) {
          Some((subkey, rendered)) => {
            match map_subs.get(entry.0) {
              Some(arr) => arr.push((subkey, rendered))
              None => ()
            }
            map_done = true
            break
          }
          None => ()
        }
      }
      if map_done {
        continue
      }
      // 两遍选 term：bare_fit 优先（吸收成裸形），object_fit 次之
      let mut chosen : (String, TermDefinition, Bool)? = None
      for pass_bare in [true, false] {
        for entry in cand_tds {
          let fits = if pass_bare {
            compact_bare_fit(v, entry.1, active)
          } else {
            compact_object_fit(v, entry.1, active)
          }
          if fits {
            chosen = Some((entry.0, entry.1, pass_bare))
            break
          }
        }
        if chosen is Some(_) {
          break
        }
      }
      match chosen {
        Some((name, td_scoped, is_bare)) => {
          // shaping td（#tc009/#tc013 同形异判对）：outer 同名 term 全权；
          // scoped-only term 剥 datatype/container/language（不作值成形）、
          // 保 local_context（property-scoped 链照走——#tc013 bar）
          let td : TermDefinition = match active.terms.get(name) {
            Some(outer_td) => outer_td
            None => {
              datatype: None,
              container: td_scoped.container,
              reverse: td_scoped.reverse,
              local_context: td_scoped.local_context,
              context_base_url: td_scoped.context_base_url,
              index_mapping: td_scoped.index_mapping,
              graph_secondary: td_scoped.graph_secondary,
              is_protected: td_scoped.is_protected,
              language_mapping: None,
              direction_mapping: None,
              is_prefix: td_scoped.is_prefix,
              nest: td_scoped.nest,
              simple_form: td_scoped.simple_form,
              iri: td_scoped.iri,
            }
          }
          let jv = match compact_value_item(v, Some(td), active, options) {
            Ok(out) => out
            Err(e) => return Err(e)
          }
          match group_vals.get(name) {
            Some(arr) => arr.push(jv)
            None => {
              group_vals[name] = [jv]
              group_keys.push(name)
              group_tds[name] = td
              let pair_is_list_absorb = match (td.container, v) {
                (Some(List), ExpandedValue::List(_)) => true
                _ => false
              }
              group_array[name] = if pair_is_list_absorb {
                false // 吸收形：jv 已是裸数组，emit 直出
              } else {
                match td.container {
                  Some(Set) | Some(List) => true
                  _ => !options.compact_arrays
                }
              }
            }
          }
          let _ = is_bare
        }
        None => {
          let jv = match compact_value_item(v, None, active, options) {
            Ok(out) => out
            Err(e) => return Err(e)
          }
          leftovers.push(jv)
        }
      }
    }
    // @graph 容器出键（§8.45——次级键映射归并内容数组；裸次级数组直出）
    match graph_td {
      Some((gname, gtd)) => {
        if graph_subs.length() > 0 {
          let sub_pairs : Array[(String, JsonValue)] = []
          let sub_keys : Array[String] = []
          let sub_vals : Map[String, Array[JsonValue]] = Map([])
          for entry in graph_subs {
            match sub_vals.get(entry.0) {
              Some(arr) =>
                for jv in entry.1 {
                  arr.push(jv)
                }
              None => {
                sub_vals[entry.0] = entry.1
                sub_keys.push(entry.0)
              }
            }
          }
          for sub in sub_keys {
            match sub_vals.get(sub) {
              Some(arr) => sub_pairs.push((sub, JsonValue::Array(arr)))
              None => ()
            }
          }
          pairs.push((gname, JsonValue::Object(sub_pairs)))
        } else if graph_bares.length() > 0 {
          let out = if graph_bares.length() == 1 {
            graph_bares[0]
          } else {
            JsonValue::Array(graph_bares)
          }
          pairs.push((gname, out))
        }
        let _ = gtd
      }
      None => ()
    }
    // 容器逆形映射出键（§8.43——subkey → 值；单值塌缩随 compactArrays）
    for name in map_names {
      match map_subs.get(name) {
        Some(entries) =>
          if entries.length() > 0 {
            let sub_pairs : Array[(String, JsonValue)] = []
            let sub_keys : Array[String] = []
            let sub_vals : Map[String, Array[JsonValue]] = Map([])
            for entry in entries {
              match sub_vals.get(entry.0) {
                Some(arr) => arr.push(entry.1)
                None => {
                  sub_vals[entry.0] = [entry.1]
                  sub_keys.push(entry.0)
                }
              }
            }
            for sub in sub_keys {
              match sub_vals.get(sub) {
                Some(arr) => {
                  let out = if options.compact_arrays && arr.length() == 1 {
                    arr[0]
                  } else {
                    JsonValue::Array(arr)
                  }
                  sub_pairs.push((sub, out))
                }
                None => ()
              }
            }
            pairs.push((name, JsonValue::Object(sub_pairs)))
          }
        None => ()
      }
    }
    // 各 term 组出键（单值塌缩——容器/@set/compactArrays 门）
    for name in group_keys {
      match (group_vals.get(name), group_array.get(name)) {
        (Some(arr), Some(keep)) => {
          // @json 值直出（#tjs07 oracle——@json 原值即 JSON，容器/塌缩不包）
          let td_json = match group_tds.get(name) {
            Some(td) =>
              td.datatype
              is Some("http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON")
            None => false
          }
          let out = if td_json && arr.length() == 1 {
            arr[0]
          } else if !keep && arr.length() == 1 {
            arr[0]
          } else {
            JsonValue::Array(arr)
          }
          let pair_out = (name, out)
          let td_nest = match group_tds.get(name) {
            Some(td) => td.nest
            None => None
          }
          match td_nest {
            Some(nest_term) =>
              match nest_groups.get(nest_term) {
                Some(group) => group.push(pair_out)
                None => {
                  nest_groups[nest_term] = [pair_out]
                  nest_order.push(nest_term)
                }
              }
            None => pairs.push(pair_out)
          }
        }
        _ => ()
      }
    }
    // 残余 → 兜底键（前缀/相对词形——#t0006 "ex:term1" oracle）；本属性
    // 已有 term 组时禁 vocab 步（#tdi07 oracle——vocab 相对词撞 term 键，
    // 落全 IRI）
    if leftovers.length() > 0 {
      let fallback_vocab = group_keys.length() == 0 && map_names.length() == 0
      let fallback_key = compact_iri_word(
        pair.0,
        false,
        fallback_vocab,
        active,
        options,
      )

      let out = if options.compact_arrays && leftovers.length() == 1 {
        leftovers[0]
      } else {
        JsonValue::Array(leftovers)
      }
      pairs.push((fallback_key, out))
    }
  }
  for nest_term in nest_order {
    match nest_groups.get(nest_term) {
      Some(group) => pairs.push((nest_term, JsonValue::Object(group)))
      None => ()
    }
  }
  match node.index {
    Some(ix) => pairs.push(("@index", JsonValue::String(ix)))
    None => ()
  }
  match node.included {
    Some(incs) => {
      // @included 面（#tin01 oracle：alias term "included" 作键、内容恒数组）
      let arr : Array[JsonValue] = []
      for inc in incs {
        match compact_node_jv(inc, active, options) {
          Ok(jv) => arr.push(jv)
          Err(e) => return Err(e)
        }
      }
      let included_key = compact_iri_word(
        "@included", true, false, active, options,
      )
      pairs.push((included_key, JsonValue::Array(arr)))
    }
    None => ()
  }
  match node.graph {
    Some(items) => {
      let arr : Array[JsonValue] = []
      for it in items {
        match it {
          ExpandedValue::Node(child) =>
            match compact_node_jv(child, active, options) {
              Ok(jv) => arr.push(jv)
              Err(e) => return Err(e)
            }
          _ => ()
        }
      }
      pairs.push(("@graph", JsonValue::Array(arr)))
    }
    None => ()
  }
  // @reverse 正向提升（#t0033/#t0050 oracle——reverse term 匹配 → 普通属性；
  // 无匹配 → "@reverse" 包裹形保真）
  let rev_pairs : Array[(String, JsonValue)] = []
  for pair in node.reverse_props {
    let cands = compact_term_candidates(pair.0, true, active)
    if cands.length() > 0 {
      match compact_property_pair(pair.0, true, pair.1, active, options) {
        Ok(pair_out) => pairs.push(pair_out)
        Err(e) => return Err(e)
      }
    } else {
      match compact_property_pair(pair.0, false, pair.1, active, options) {
        Ok(pair_out) => rev_pairs.push(pair_out)
        Err(e) => return Err(e)
      }
    }
  }
  if rev_pairs.length() > 0 {
    pairs.push(("@reverse", JsonValue::Object(rev_pairs)))
  }
  Ok(JsonValue::Object(pairs))
}

///|
/// 容器逆形映射条目（§8.43 成批机制——fit + 子键 + 键化成员剥离一体；
/// None = 值不入该映射容器，落常规分选）。四类差异钉：
/// @id = 节点 @id 作键（@id 值位旗词形——exact/vocab 禁）、值 @id 整剥
/// （#tm001/#tm002/#tm005）；@type = 首 type 作键（类型位旗词形）、值留
/// 残余 type（#tm003/#tm004）；@index = @index 原文作键、值 @index 剥；
/// @language = 语言原文作键、值裸串（#tm012/#tla01）；无键化成员 →
/// @none 兜底（别名词形感知——#tm012 "none" / #tm017 字面）
fn compact_map_entry(
  value : ExpandedValue,
  td : TermDefinition,
  active : ActiveContext,
  options : JsonLdOptions,
) -> (String, JsonValue)? {
  let none_key = compact_iri_word("@none", true, false, active, options)
  match td.container {
    Some(Id) =>
      match value {
        ExpandedValue::Node(child) => {
          let subkey = match child.id {
            Some(id) => compact_iri_word(id, false, false, active, options)
            None => none_key
          }
          let id_key = compact_iri_word("@id", true, false, active, options)
          match compact_node_jv(child, active, options) {
            Ok(JsonValue::Object(pairs)) => {
              let stripped : Array[(String, JsonValue)] = []
              for p in pairs {
                if p.0 != id_key {
                  stripped.push(p)
                }
              }
              Some((subkey, JsonValue::Object(stripped)))
            }
            Ok(other) => Some((subkey, other))
            Err(_) => None
          }
        }
        _ => None
      }
    Some(Type) => {
      let first : String? = match value {
        ExpandedValue::Node(child) => child.types.get(0)
        ExpandedValue::Value(lit) => lit.datatype
        _ => None
      }
      let rendered : Result[JsonValue, JsonLdError] = match value {
        ExpandedValue::Node(child) => {
          // 首 type 键化、残余留（#tm004 oracle——types[1:] 浅拷贝出形）；
          // 剥后 id-only ⇒ 串塌缩**无条件**（#tm020/#tm022 oracle——不要求
          // td @type；vocab 旗仍随 td：tm020 base 相对 / tm022 vocab 相对）
          let rest : Array[String] = []
          for i in 1..<child.types.length() {
            rest.push(child.types[i])
          }
          let variant : ExpandedNode = {
            id: child.id,
            types: rest,
            properties: child.properties,
            reverse_props: child.reverse_props,
            graph: child.graph,
            included: child.included,
            index: child.index,
          }
          let variant_bare = variant.types.is_empty() &&
            variant.properties.is_empty() &&
            variant.reverse_props.is_empty() &&
            variant.graph is None &&
            variant.included is None &&
            variant.index is None
          if variant_bare {
            match variant.id {
              Some(id) =>
                Ok(
                  JsonValue::String(
                    compact_iri_word(
                      id,
                      false,
                      td.datatype is Some("@vocab"),
                      active,
                      options,
                    ),
                  ),
                )
              None => compact_node_jv(variant, active, options)
            }
          } else {
            compact_node_jv(variant, active, options)
          }
        }
        ExpandedValue::Value(lit) => {
          // 字面量 datatype 键化 → 值对象去 @type 对
          let rendered_lit = compact_value_jv(lit, None, active, options)
          match rendered_lit {
            JsonValue::Object(pairs) => {
              let stripped : Array[(String, JsonValue)] = []
              for p in pairs {
                if p.0 != "@type" {
                  stripped.push(p)
                }
              }
              Ok(JsonValue::Object(stripped))
            }
            other => Ok(other)
          }
        }
        _ => Ok(JsonValue::Null)
      }
      match rendered {
        Ok(jv) => {
          let subkey = match first {
            Some(t) => compact_iri_word(t, true, true, active, options)
            None => none_key
          }
          Some((subkey, jv))
        }
        Err(_) => None
      }
    }
    Some(Index) => {
      // 属性化索引分支（§8.47——td.index_mapping Some：子键 = index 属性
      // 首值；残余留；键化值节点对象形 / @none 组走常规值压缩——不对称出形）
      match td.index_mapping {
        Some(raw_index_name) => {
          // index_mapping 存原始 term 名（展开侧同款——用时期 IRI 展开得
          // 属性 IRI；expand_iri vocab=false/docRel=true 与展开侧 3880 行
          // 同参——@base 随压缩 active 链）
          let prop_iri = match IriExpander::expand_iri(
            StandardExpander::{ },
            active,
            raw_index_name,
            false,
            true,
          ) {
            Ok(iri) => iri
            Err(_) => raw_index_name
          }
          match value {
            ExpandedValue::Node(child) => {
              let idx_vals : Array[ExpandedValue] = []
              let rest_props : Array[(String, Array[ExpandedValue])] = []
              for p in child.properties {
                if p.0 == prop_iri {
                  for iv in p.1 {
                    idx_vals.push(iv)
                  }
                } else {
                  rest_props.push(p)
                }
              }
              // 子键推导：首值字面量直取串；节点引用按 prop 自己的 term 定
              // 塌缩（无 term / 不可塌缩 = 无键 → @none——#tpi06 oracle）
              let subkey_opt : String? = match idx_vals.get(0) {
                Some(ExpandedValue::Value(lit)) => Some(lit.value)
                Some(ExpandedValue::Node(ref_node)) =>
                  if ref_node.id is Some(_) {
                    let prop_cands = compact_term_candidates(prop_iri, false, active)
                    let prop_td : TermDefinition? = match prop_cands {
                      pcs if pcs.length() > 0 => active.terms.get(pcs[0])
                      _ => None
                    }
                    match prop_td {
                      Some(ptd) =>
                        match ptd.datatype {
                          Some("@id") | Some("@vocab") =>
                            match ref_node.id {
                              Some(rid) =>
                                Some(
                                  compact_iri_word(
                                    rid,
                                    false,
                                    ptd.datatype is Some("@vocab"),
                                    active,
                                    options,
                                  ),
                                )
                              None => None
                            }
                          _ => None
                        }
                      None => None
                    }
                  } else {
                    None
                  }
                _ => None
              }
              // variant：prop 属性 = 残余值（空则整剥）
              let variant_props : Array[(String, Array[ExpandedValue])] = []
              for p in rest_props {
                variant_props.push(p)
              }
              let variant : ExpandedNode = {
                id: child.id,
                types: child.types,
                properties: variant_props,
                reverse_props: child.reverse_props,
                graph: child.graph,
                included: child.included,
                index: child.index,
              }
              if idx_vals.length() > 0 {
                // 无键（首值不可串塌缩——#tpi06 oracle）→ 全形落 @none 组
                //（prop 保原形走常规渲染）
                if subkey_opt is None {
                  match compact_value_item(value, Some(td), active, options) {
                    Ok(jv) => return Some((none_key, jv))
                    Err(_) => return None
                  }
                }
                // 键化（或有残余可键化候选）：子键取首值；variant 挂残余
                if rest_props.length() == child.properties.length() - 1 ||
                  idx_vals.length() > 1 {
                  // 残余值重挂回 prop 属性（首值已键化）
                  let with_rest : Array[(String, Array[ExpandedValue])] = []
                  for p in variant_props {
                    with_rest.push(p)
                  }
                  if idx_vals.length() > 1 {
                    let rest_vals : Array[ExpandedValue] = []
                    for i in 1..<idx_vals.length() {
                      rest_vals.push(idx_vals[i])
                    }
                    with_rest.push((prop_iri, rest_vals))
                  }
                  let variant2 : ExpandedNode = {
                    id: variant.id,
                    types: variant.types,
                    properties: with_rest,
                    reverse_props: variant.reverse_props,
                    graph: variant.graph,
                    included: variant.included,
                    index: variant.index,
                  }
                  match compact_node_jv(variant2, active, options) {
                    Ok(jv) => {
                      let subkey = match subkey_opt {
                        Some(sk) => sk
                        None => none_key
                      }
                      return Some((subkey, jv))
                    }
                    Err(_) => return None
                  }
                } else {
                  match compact_node_jv(variant, active, options) {
                    Ok(jv) => {
                      let subkey = match subkey_opt {
                        Some(sk) => sk
                        None => none_key
                      }
                      return Some((subkey, jv))
                    }
                    Err(_) => return None
                  }
                }
              } else {
                // 无 index 属性 → @none 组（常规值压缩链——#tpi05/#tpi06）
                match compact_value_item(value, Some(td), active, options) {
                  Ok(jv) => return Some((none_key, jv))
                  Err(_) => return None
                }
              }
            }
            _ => return None
          }
        }
        None => ()
      }
      let subkey_opt : String? = match value {
        ExpandedValue::Node(child) => child.index
        ExpandedValue::Value(lit) => lit.index
        _ => None
      }
      let rendered : Result[JsonValue, JsonLdError] = match value {
        ExpandedValue::Node(child) => {
          // @index 键化 → 剥（浅拷贝 index None）
          let variant : ExpandedNode = {
            id: child.id,
            types: child.types,
            properties: child.properties,
            reverse_props: child.reverse_props,
            graph: child.graph,
            included: child.included,
            index: None,
          }
          compact_node_jv(variant, active, options)
        }
        ExpandedValue::Value(lit) => {
          // index 清除副本（#tm009 oracle——字面量 index 键化后须裸形；
          // index 在场会挡 compact_value_jv 缺省裸臂）
          let bare_lit : ExpandedLiteral = {
            value: lit.value,
            datatype: lit.datatype,
            language: lit.language,
            direction: lit.direction,
            raw: lit.raw,
            index: None,
            included: lit.included,
          }
          Ok(compact_value_jv(bare_lit, None, active, options))
        }
        _ => Ok(JsonValue::Null)
      }
      match rendered {
        Ok(jv) => {
          let subkey = match subkey_opt {
            Some(ix) => ix
            None => none_key
          }
          Some((subkey, jv))
        }
        Err(_) => None
      }
    }
    Some(Language) =>
      match value {
        ExpandedValue::Value(lit) => {
          // 方向过滤（§8.48——方向不合者不入语言图，落残余兜底键——
          // #tdi07 oracle：不合值成 vocab:label 值对象数组）
          let dir_ok = match td.direction_mapping {
            Some(Set(d)) => lit.direction == Some(d)
            Some(Null) => lit.direction is None
            None =>
              match lit.direction {
                Some(d) => d == active.default_direction.unwrap_or("")
                None => active.default_direction is None
              }
          }
          if !dir_ok {
            return None
          }
          // 串值裸形（语言键化即剥——#tm012 oracle）；无语言 → @none
          let subkey = match lit.language {
            Some(lang) => lang
            None => none_key
          }
          Some((subkey, JsonValue::String(literal_value_of(lit))))
        }
        _ => None
      }
    _ => None
  }
}

///|
/// 字面量串值取形（language map 裸形用；raw 在场取 raw——数值型语言图
/// 不入册，此处词形兜底）
fn literal_value_of(lit : ExpandedLiteral) -> String {
  lit.value
}


///|
/// type-scoped context 套用（压缩面——tc013/tc006/tc014 族）：节点 types 依次
/// 命中带 local_context 的 term（词表候选序）即套用（type_scoped 旗 =
/// propagate false + override protected false）；套用失败回退当前链
/// （定义期已校验，运行期失败罕见——回退不吞数据）
fn compact_apply_type_scoped(
  types : Array[String],
  active : ActiveContext,
  options : JsonLdOptions,
) -> ActiveContext {
  let mut current = active
  for t in types {
    for name in compact_term_candidates(t, false, active) {
      match active.terms.get(name) {
        Some(td) =>
          match td.local_context {
            Some(lc) =>
              match
                ContextProcessor::process_context(
                  StandardExpander::{ },
                  current,
                  lc,
                  ContextFlags::type_scoped(),
                  options,
                ) {
                Ok(c) => current = c
                Err(_) => ()
              }
            None => ()
          }
        None => ()
      }
    }
  }
  current
}
