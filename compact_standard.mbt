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
  allow_base : Bool,
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
  // @vocab 相对词形（#t0021 oracle：@vocab "http://example.com/subdir/" +
  // "…/subdir/vocab/embed" → "vocab/embed"——仅谓词/类型位；@id 值位禁，
  // allow_vocab=false）
  if allow_vocab {
    match active.vocab {
      Some(vocab) =>
        if vocab.length() < iri.length() && iri.has_prefix(vocab) {
          // 撞词守门（#t0043 oracle——suffix 为在册 term 时重展开撞词，
          // 跳过 vocab 步保全 IRI）
          let suffix = iri[vocab.length():].to_owned()
          if !active.terms.contains(suffix) {
            return suffix
          }
        }
      None => ()
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
            (
              pair.1.is_prefix is None &&
              pair.1.simple_form &&
              // 映射词尾闸（§8.46 精化——简单形隐式资格受词尾约束；@prefix:true
              // 显式豁免词尾——#tp003 oracle 落闸 vs #tp005/#tp006 oracle
              // @prefix:true 过闸：mapping 尾 '-' 照压缩）
              (match pair.1.iri {
                Some(pfx_word) =>
                  match pfx_word.get_char(pfx_word.length() - 1) {
                    Some(':')
                    | Some('/')
                    | Some('?')
                    | Some('#')
                    | Some('[')
                    | Some(']')
                    | Some('@') => true
                    _ => false
                  }
                None => false
              })
            )
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
  // base 相对化（compactToRelative 门——×1 件保绝对词面；段界对齐：base 尾
  // 无 "/" 补一段再对前缀，防 "http://example.com" vs "…/com/foo" 误剥——
  // #tr001 oracle：option base "http://example.org/" → "@id":"a"）
  if options.compact_to_relative && allow_base {
    match active.base {
      Some(base) => {
        // 片段相对优先（#tc015 oracle——base 无尾 '/' 且 iri = base + "#…"
        // ⇒ "#…" 形，先于目录位判定）
        if iri.has_prefix(base) {
          let rest = iri[base.length():].to_owned()
          if rest.has_prefix("#") {
            return rest
          }
        }
        // 边界 = base 目录位：尾 '/' 即用；否则剥最后一段取目录
        // （#t0076/#t0066 oracle——@base 为文档 URL 时 @id 相对化到同目录）
        let boundary = match base.get_char(base.length() - 1) {
          Some('/') => base
          _ => {
            let mut cut = 0
            for i in 0..<base.length() {
              if base.get_char(i) == Some('/') {
                cut = i + 1
              }
            }
            base[:cut].to_owned()
          }
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
/// 值 datatype 取形（排名特异性用——Value 取其 datatype；List 取**全项
/// uniform** 的 datatype（役31 typed 值对象收集项——#t0018 term4/term5、
/// #t0024 termTL1/TL2 排名位），混合/含非值项 → None；他形 None）
fn literal_datatype_of(v : ExpandedValue) -> String? {
  match v {
    ExpandedValue::Value(lit) => lit.datatype
    ExpandedValue::List(items, ..) => {
      let mut acc : String? = None
      let mut mixed = false
      for item in items {
        let known = match item {
          ExpandedValue::Value(_) => true
          _ => false
        }
        let item_dt : String? = match item {
          ExpandedValue::Value(lit) => lit.datatype
          _ => None
        }
        if !known {
          mixed = true
        } else {
          match (acc, item_dt) {
            (None, dt) => acc = dt
            (Some(a), Some(d)) => if a != d { mixed = true }
            (Some(_), None) => mixed = true
          }
        }
      }
      if mixed {
        None
      } else {
        acc
      }
    }
    _ => None
  }
}

///|
/// 标量免注判定（#t0048——number/bool raw 保形体）
fn literal_raw_is_scalar(lit : ExpandedLiteral) -> Bool {
  lit.raw is Some(_)
}

///|
/// 语言标签等值（BCP47 大小写不敏感——#tla01 oracle："eN" ≡ "en"；
/// ASCII 宽松折叠——语言子序列恒 ASCII）
fn lang_tag_eq(a : String, b : String) -> Bool {
  if a == b {
    return true
  }
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    let ca = a.get_char(i)
    let cb = b.get_char(i)
    match (ca, cb) {
      (Some(x), Some(y)) =>
        if ascii_fold_lower(x) != ascii_fold_lower(y) {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
/// ASCII 大小写折叠（lang_tag_eq 用——语言子序列恒 ASCII，A-Z ±32）
fn ascii_fold_lower(c : Char) -> Int {
  let v = c.to_int()
  if v >= 65 && v <= 90 {
    v + 32
  } else {
    v
  }
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
    ExpandedValue::List(items, index~) =>
      compact_list_bare_fit(items, index, td, active)
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
      // index 闸（§8.54——@index 值对象在无 index_mapping 的 term 下重展开
      // 丢 @index = 不安全，两形皆拒——#t0065 oracle）
      if lit.index is Some(_) &&
        td.index_mapping is None &&
        td.container is Some(_) {
        return false
      }
      // @list 容器 term 只整列吸收 List 值（标量入列即多值异质并组——
      // #t0018 oracle：v0.2/v0.3/裸标量归 plain term，不落 term2/term3 列）
      if td.container is Some(List) {
        return false
      }
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
                Some(l) => lang_tag_eq(l, lang)
                None => false
              }
            Some(Null) => lit.language is None
            None =>
              // 纯 term：语言态对齐 = 值语言 == context 缺省语言（裸形重展开
              // 带回缺省语言——失配即不安全）；标量免注（#t0048——number/bool
              // raw 保形体不受缺省语言注入）；typed 非裸串不可裸吸（裸串重
              // 展开丢 @type——#tc020 value-type；raw 标量 datatype 重展开
              // 自恢复不受此限）
              match lit.language {
                Some(lang) =>
                  lang_tag_eq(lang, active.default_language.unwrap_or(""))
                None =>
                  (
                    active.default_language is None ||
                    literal_raw_is_scalar(lit)
                  ) &&
                  (lit.datatype is None || literal_raw_is_scalar(lit))
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
    // @list 值对象恒安全（重展开保 @list 形）；带 @index 者例外
    // （#t0041 oracle——term 重展开丢 index）
    ExpandedValue::List(_, index~) => !(index is Some(_))
    // 节点值：@id 型 term（非裸引用亦安全——对象形重展开仍为节点）；无
    // datatype 的 term 对象形安全；datatype 版 term 冲突不可用
    // （#t0006 term2 oracle：裸引用对象形落回 term 键）
    ExpandedValue::Node(_) =>
      match td.datatype {
        // @none 同权（#ttn01——节点引用对象形安全，无 coercion）
        Some(dt) => dt is ("@id" | "@vocab" | "@none")
        None => true
      }
    ExpandedValue::Value(lit) => {
      // index 闸（§8.54——同 bare_fit；#t0065 oracle）
      if lit.index is Some(_) &&
        td.index_mapping is None &&
        td.container is Some(_) {
        return false
      }
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
        // @id 型 term + 字面量：值对象形不被强转（仅裸串强转）——安全；
        // @none 同权（#ttn01——值恒值对象形，object_fit 放行）
        Some("@id") | Some("@vocab") | Some("@none") => true
        // datatype 版 term 与值态失配 → 无形可用（#t0006 oracle）
        Some(_) => false
        None =>
          match td.language_mapping {
            // language 版 term 与值语言态失配 → 无形可用
            Some(_) => false
            // 纯 term：对象形可用的残域 = datatype 在场（钉 @type——
            // #t0002 term2 oracle）或 language 在场（钉 @language——
            // #t0002 term3 oracle）或 context 缺省语言在场（对象形保住
            // 无语言态，裸串重展开会被注入缺省——#t0018 v0.3 oracle）
            None =>
              lit.datatype is Some(_) ||
              lit.language is Some(_) ||
              _active.default_language is Some(_)
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
  key_active : ActiveContext,
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
      // language 吸收（串值裸形；方向态须合——§8.48 同判据；Null 臂 =
      // 显式压制吸收无语言值——#t0015 term5/#t0089 s oracle）
      match td.language_mapping {
        Some(Set(lang)) =>
          match literal.language {
            Some(l) =>
              if lang_tag_eq(l, lang) {
                let dir_ok = match td.direction_mapping {
                  Some(Set(d)) => literal.direction == Some(d)
                  Some(Null) => literal.direction is None
                  None => true
                }
                if dir_ok {
                  return match literal.raw {
                    Some(raw) => raw
                    None => JsonValue::String(literal.value)
                  }
                }
              }
            None => ()
          }
        Some(Null) =>
          if literal.language is None {
            let dir_ok = match td.direction_mapping {
              Some(Set(d)) => literal.direction == Some(d)
              Some(Null) => literal.direction is None
              None => true
            }
            if dir_ok {
              return match literal.raw {
                Some(raw) => raw
                None => JsonValue::String(literal.value)
              }
            }
          }
        _ => ()
      }
      // direction 吸收（串值裸形——§8.48 #tdi03 oracle：list 项 @direction
      // 合 td 方向映射即裸形，重展开注回同向）
      match td.direction_mapping {
        Some(Set(d)) =>
          if literal.direction == Some(d) {
            return match literal.raw {
              Some(raw) => raw
              None => JsonValue::String(literal.value)
            }
          }
        Some(Null) =>
          if literal.direction is None {
            return match literal.raw {
              Some(raw) => raw
              None => JsonValue::String(literal.value)
            }
          }
        None => ()
      }
    }
    None => ()
  }
  // @none 显式无 coercion（#ttn01——term @type @none 下值恒值对象形，
  // 裸形早退跳过；datatype None 双义的解 = keyword 形标记 Some("@none")）
  let none_no_coercion = match td_opt {
    Some(td) => td.datatype == Some("@none")
    None => false
  }
  let bare_datatype = match literal.datatype {
    Some(dt) => dt == "http://www.w3.org/2001/XMLSchema#string"
    None => true
  }
  // 语言态对齐（#t0015 v1 oracle——de 值在缺省 de 下裸形重展开带回同语言，
  // 安全；纯串无修饰且缺省在场则对象形也不安全，分选层已拒）
  let language_aligned = match literal.language {
    Some(lang) => lang_tag_eq(lang, active.default_language.unwrap_or(""))
    None => active.default_language is None
  }
  let scalar_language_immune = literal.raw is Some(_)
  if !none_no_coercion &&
    bare_datatype &&
    (scalar_language_immune || language_aligned) &&
    literal.direction is None &&
    literal.index is None {
    return match literal.raw {
      Some(raw) => raw
      None => JsonValue::String(literal.value)
    }
  }

  // @value 键走别名压缩（#tc020——type-scoped "value":"@value" 键生效）
  let value_key = compact_iri_word(
    "@value", true, false, true, key_active, options,
  )
  let pairs : Array[(String, JsonValue)] = [
    (
      value_key,
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
        let type_key = compact_iri_word(
          "@type", true, false, true, key_active, options,
        )
        pairs.push(
          (
            type_key,
            JsonValue::String(
              compact_iri_word(dt, true, true, true, key_active, options),
            ),
          ),
        )
      }
    None => ()
  }
  // @language/@direction 走别名键（#tdi02 oracle——"direction":"@direction"
  // → 键 "direction"；无别名回落关键字字面）
  // 值对象键随键选择链（#tc020——type-scoped "value":"@value" 别名生效）
  let lang_key = compact_iri_word(
    "@language", true, false, true, key_active, options,
  )
  let dir_key = compact_iri_word(
    "@direction", true, false, true, key_active, options,
  )
  match literal.language {
    Some(lang) => pairs.push((lang_key, JsonValue::String(lang)))
    None => ()
  }
  match literal.direction {
    Some(dir) => pairs.push((dir_key, JsonValue::String(dir)))
    None => ()
  }
  match literal.index {
    Some(ix) => {
      let index_key = compact_iri_word(
        "@index", true, false, true, key_active, options,
      )
      pairs.push((index_key, JsonValue::String(ix)))
    }
    None => ()
  }
  JsonValue::Object(pairs)
}

///|
/// 排名估长器（无递归——断 compact_node_jv 定义环）：id_only 节点取**本
/// term 塌缩词**长（役31——词形随候选项，最短词形排名的本职；塌缩旗标与
/// compact_value_item 串塌缩臂逐字同源，故 id_only 面即精确渲染长）+
/// 词形级别（exact 0 < vocab 后缀 1 < 前缀词 2 < base 相对 3 < 全 IRI 4
/// ——同长 tie-break，#t0044 DefinedTerm exact 胜 base 相对）；值取词长+8；
/// list 300+项*8；非裸节点 400——排名仅需相对序，精确长由选中后真渲染承担
fn compact_rank_word_len(
  v : ExpandedValue,
  td_opt : TermDefinition?,
  active : ActiveContext,
  options : JsonLdOptions,
) -> (Int, Int) {
  match v {
    ExpandedValue::Node(child) => {
      let id_only = child.types.is_empty() &&
        child.properties.is_empty() &&
        child.reverse_props.is_empty() &&
        child.graph is None &&
        child.included is None &&
        child.index is None
      let id = match child.id {
        Some(id) => id
        None => return (400, 4)
      }
      if !id_only {
        return (400, 4)
      }
      match td_opt {
        Some(td) =>
          match td.datatype {
            // @id 型：串塌缩恒行（base 相对——compact_value_item 同旗标）
            Some("@id") => {
              let word = compact_iri_word(
                id, false, false, true, active, options,
              )
              (
                word.length(),
                compact_word_rank(id, false, false, active, options),
              )
            }
            // @vocab 型：exact/vocab 命中才塌，否则前缀词步（base 禁——
            // compact_value_item 同判据）
            Some("@vocab") => {
              let exact_hit = compact_term_candidates(id, false, active).length() >
                0
              let vocab_hit = match active.vocab {
                Some(vocab) =>
                  vocab.length() < id.length() && id.has_prefix(vocab)
                None => false
              }
              let word = if exact_hit || vocab_hit {
                compact_iri_word(id, true, true, true, active, options)
              } else {
                compact_iri_word(id, false, false, false, active, options)
              }
              (
                word.length(),
                compact_word_rank(id, exact_hit, vocab_hit, active, options),
              )
            }
            // 无 @type 形态：id_only 节点走对象形（{"@id":…}），不作裸塌缩
            _ => (400, 4)
          }
        None => (400, 4)
      }
    }
    ExpandedValue::Value(lit) => (lit.value.length() + 8, 3)
    ExpandedValue::List(items, ..) => (300 + items.length() * 8, 3)
  }
}

///|
/// 词形级别（估长器同长 tie-break 用；与本 term 塌缩词配套）：exact 命中
/// 0 < vocab 后缀 1 < 前缀词 2 < base 相对 3 < 全 IRI 4——以窄旗标逐步
/// 试塌归类（每步纯串工作，无渲染递归）
fn compact_word_rank(
  id : String,
  exact_hit : Bool,
  vocab_hit : Bool,
  active : ActiveContext,
  options : JsonLdOptions,
) -> Int {
  if exact_hit {
    return 0
  }
  if vocab_hit {
    return 1
  }
  let prefix_word = compact_iri_word(id, false, false, false, active, options)
  if prefix_word != id {
    return 2
  }
  let base_word = compact_iri_word(id, false, false, true, active, options)
  if base_word != id {
    return 3
  }
  4
}

///|
/// @reverse 值级分键（役31 从 compact_node_jv 内联抽出——@reverse 定义 term
/// 与普通 term 双路复用）：逐值 bare_fit + 最短词形排名（词长→词形级别）归
/// term（#t0044 oracle——dave→knows 全词、DefinedTerm→knowsVocab exact 词；
/// 同 IRI 双 term 按值拆键）；无 fit 值落 compact_property_pair 兜底键。
/// 返回 (键, 值) 对数组——组内单值塌缩随 compactArrays
fn compact_reverse_split_pairs(
  pred : String,
  cands : Array[String],
  vals : Array[ExpandedValue],
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[Array[(String, JsonValue)], JsonLdError] {
  let rev_split : Map[String, Array[JsonValue]] = Map([])
  for v in vals {
    let mut best : (String, TermDefinition, Int, Int)? = None
    for name in cands {
      match active.terms.get(name) {
        Some(td) => {
          let fits = compact_bare_fit(v, td, active)
          if fits {
            let (word_len, word_rank) = compact_rank_word_len(
              v,
              Some(td),
              active,
              options,
            )
            let better = match best {
              Some((_, _, bl, br)) =>
                word_len < bl || (word_len == bl && word_rank < br)
              None => true
            }
            if better {
              best = Some((name, td, word_len, word_rank))
            }
          }
        }
        None => ()
      }
    }
    match best {
      Some((name, td, _, _)) => {
        let jv = match
          compact_value_item(v, Some(td), active, active, options) {
          Ok(out) => out
          Err(e) => return Err(e)
        }
        match rev_split.get(name) {
          Some(arr) => arr.push(jv)
          None => rev_split[name] = [jv]
        }
      }
      None =>
        match compact_property_pair(pred, true, [v], active, options) {
          Ok(pair_out) =>
            // 同键并值（多值同落一词形——恒追加）
            match rev_split.get(pair_out.0) {
              Some(arr) => arr.push(pair_out.1)
              None => rev_split[pair_out.0] = [pair_out.1]
            }
          Err(e) => return Err(e)
        }
    }
  }
  let out : Array[(String, JsonValue)] = []
  for name in rev_split.keys().collect() {
    match rev_split.get(name) {
      Some(arr) => {
        let rendered = if options.compact_arrays && arr.length() == 1 {
          arr[0]
        } else {
          JsonValue::Array(arr)
        }
        out.push((name, rendered))
      }
      None => ()
    }
  }
  Ok(out)
}

///|
/// 单值压缩分发（节点引用串塌缩：@id-only 子节点 + td @type @id/@vocab →
/// 压缩词串；否则子节点递归对象形）
fn compact_value_item(
  value : ExpandedValue,
  td_opt : TermDefinition?,
  active : ActiveContext,
  key_active : ActiveContext,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  // property-scoped context 套用（压缩面——tc001/tc013 族：td @context 在
  // 节点有效链之上套用，值渲染全走此链；套用失败回退——定义期已校验）。
  // key_active = 键选择链（役3 双链分立——#tc011：type-scoped 注销的别名
  // 只在键链生效，{"@id"} 对象形键随此链；property-scoped 对两链同权套用）
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
  let key_active : ActiveContext = match td_opt {
    Some(td) =>
      match td.local_context {
        Some(lc) =>
          match
            ContextProcessor::process_context(
              StandardExpander::{ },
              key_active,
              lc,
              ContextFlags::property_scoped(),
              options,
            ) {
            Ok(c) => c
            Err(_) => key_active
          }
        None => key_active
      }
    None => key_active
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
                        compact_iri_word(
                          id, false, false, true, active, options,
                        ),
                      ),
                    )
                  // @vocab 型塌缩 = exact 命中或 vocab 前缀命中才塌
                  // （#t0054 "enum" / #tc013 "buzz"）；两者皆不命中保绝对
                  // ——base 步不参与（#t0062 oracle：绝对 IRI 不因文档
                  // base 相对化）
                  Some("@vocab") => {
                    let exact_hit = compact_term_candidates(id, false, active).length() >
                      0
                    let vocab_hit = match active.vocab {
                      Some(v) => v.length() < id.length() && id.has_prefix(v)
                      None => false
                    }
                    if exact_hit || vocab_hit {
                      return Ok(
                        JsonValue::String(
                          compact_iri_word(
                            id, true, true, true, active, options,
                          ),
                        ),
                      )
                    }
                    // 前缀词步仍可（#t0063 oracle——"prefix:suffix"），
                    // base 步禁（绝对 IRI 不因文档 base 相对化）
                    let prefix_word = compact_iri_word(
                      id, false, false, false, active, options,
                    )
                    return Ok(JsonValue::String(prefix_word))
                  }
                  _ => ()
                }
              None => ()
            }
          None => ()
        }
        // 对象形：{@id键: 压缩词}；键走关键词压缩（役31——@id 别名 term
        // 生效，#t0022 oracle："id":"@id" 别名下列项节点 {id:…} 非 {@id:…}；
        // 与值对象 @language 键同款旗标）；@-词转义（#t0111 oracle——
        // "@special" 重展开会被当关键字 ⇒ "./" 前缀逃逸）
        let id_key = compact_iri_word(
          "@id", true, false, true, key_active, options,
        )
        let word = match child.id {
          Some(id) => compact_iri_word(id, false, false, true, active, options)
          None => ""
        }
        let word = if word.has_prefix("@") { "./" + word } else { word }
        return Ok(JsonValue::Object([(id_key, JsonValue::String(word))]))
      }
      compact_node_graph_value_jv(child, active, options)
    }
    ExpandedValue::Value(literal) =>
      Ok(compact_value_jv(literal, td_opt, active, key_active, options))
    ExpandedValue::List(items, index~) => {
      // @list 容器吸收（td @container @list → 裸数组——#t0015 term4 oracle）；
      // 1.0 嵌套 list = compaction to list of lists 错（#te001 oracle）；
      // 无容器 → @list 值对象形（带 @index ⇒ {@list,@index} 对象形——
      // #t0041 oracle）
      let is_list_container = match td_opt {
        Some(td) => td.container is Some(List)
        None => false
      }
      let arr : Array[JsonValue] = []
      for it in items {
        if it is ExpandedValue::List(_) && options.processing_mode is JsonLd10 {
          return Err(JsonLdError::InvalidList("compaction to list of lists"))
        }
        match compact_value_item(it, td_opt, active, key_active, options) {
          Ok(jv) => arr.push(jv)
          Err(e) => return Err(e)
        }
      }
      if is_list_container {
        return Ok(JsonValue::Array(arr))
      }
      // @list/@index 键走 term 词形（关键字别名——#t0042 oracle：
      // "listAlias"/"indexAlias" 作键；无别名回落关键字字面）
      let list_key = compact_iri_word(
        "@list", true, false, true, active, options,
      )
      let index_key = compact_iri_word(
        "@index", true, false, true, active, options,
      )
      let list_obj : Array[(String, JsonValue)] = [
        (list_key, JsonValue::Array(arr)),
      ]
      match index {
        Some(ix) => list_obj.push((index_key, JsonValue::String(ix)))
        None => ()
      }
      Ok(JsonValue::Object(list_obj))
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
            ExpandedValue::List(items, ..) => {
              let arr : Array[JsonValue] = []
              for it in items {
                if it is ExpandedValue::List(_) &&
                  options.processing_mode is JsonLd10 {
                  return Err(
                    JsonLdError::InvalidList("compaction to list of lists"),
                  )
                }
                match compact_value_item(it, td_opt, active, active, options) {
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
    match compact_value_item(v, td_opt, active, active, options) {
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
    _ => compact_iri_word(pred, true, true, true, active, options)
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
  // 值成形链）。base 轨（§8.59 第三轨）：值位词形 base 相对化随 scoped 链
  // （#tc015 oracle——typed-base 下 "#typed-id" 片段相对）
  let scoped = compact_apply_type_scoped(node.types, active, options)
  let value_chain : ActiveContext = if scoped.base != active.base {
    {
      base: scoped.base,
      vocab: active.vocab,
      terms: active.terms,
      previous: active.previous,
      default_language: active.default_language,
      default_direction: active.default_direction,
    }
  } else {
    active
  }
  let pairs : Array[(String, JsonValue)] = []
  // @id 键走 term 词形（关键字别名 term——#t0008 oracle："uri":"@id" →
  // "uri" 作键；无别名回落 "@id" 字面）
  let id_key = compact_iri_word("@id", true, false, true, scoped, options)
  match node.id {
    Some(id) =>
      // 词形走 value_chain（base 轨——type-scoped @base 传导至本节点值位，
      // §8.59/#tc015 oracle：typed-base 下 "#typed-id" 片段相对）
      pairs.push(
        (
          id_key,
          JsonValue::String(
            compact_iri_word(id, true, false, true, value_chain, options),
          ),
        ),
      )
    None => ()
  }
  if node.types.length() > 0 {
    // @type 键走 term 词形（关键字别名——#t0022 oracle："type":"@type" →
    // "type" 作键；无别名回落 "@type" 字面）
    let type_key = compact_iri_word("@type", true, false, true, scoped, options)
    let types : Array[JsonValue] = []
    for t in node.types {
      // @type 值渲染走 outer 链（#tc014 oracle——nullification 后 vocab
      // 存续；type-scoped 只管键选择，值词形随外层——双链分立同款）
      types.push(
        JsonValue::String(
          compact_iri_word(t, true, true, true, active, options),
        ),
      )
    }
    // 别名 term 带 @container @set ⇒ 恒数组（#t0105 oracle；#t0106
    // oracle——1.0 模式数组塌缩不受 @set 容器约束）
    let type_set = match scoped.terms.get(type_key) {
      Some(td) =>
        td.container is Some(Set) && options.processing_mode is JsonLd11
      None => false
    }
    if options.compact_arrays && types.length() == 1 && !type_set {
      pairs.push((type_key, types[0]))
    } else {
      pairs.push((type_key, JsonValue::Array(types)))
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
    // 多值 @set 候选偏好（§8.54——多值时 @set term 保形胜出，候选序前置；
    // #t0027 oracle——label/container 同 IRI，多值归 @set 版）
    if pair.1.length() > 1 {
      let sets : Array[(String, TermDefinition)] = []
      let rest : Array[(String, TermDefinition)] = []
      for entry in cand_tds {
        if entry.1.container is Some(Set) {
          sets.push(entry)
        } else {
          rest.push(entry)
        }
      }
      if sets.length() > 0 {
        cand_tds.clear()
        for entry in sets {
          cand_tds.push(entry)
        }
        for entry in rest {
          cand_tds.push(entry)
        }
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
    let graph_subs : Array[(String, JsonValue)] = []
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
        Some((gt_name, gtd)) =>
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
                    "@none", true, false, true, active, options,
                  )
                  // shaped（§8.52——单内容节点对象 / 多内容 @included 包裹；
                  // graph_set 载体恒数组保形——#t0082 族 oracle）
                  let shaped = if gtd.graph_set {
                    JsonValue::Array(content)
                  } else if content.length() == 1 {
                    content[0]
                  } else {
                    let included_key = compact_iri_word(
                      "@included", true, false, true, active, options,
                    )
                    JsonValue::Object(
                      [("@included", JsonValue::Array(content))].map(fn(p) {
                        if p.0 == "@included" {
                          (included_key, p.1)
                        } else {
                          p
                        }
                      }),
                    )
                  }
                  match gtd.graph_secondary {
                    Some(Id) => {
                      let subkey = match child.id {
                        Some(id) =>
                          compact_iri_word(
                            id, false, false, true, active, options,
                          )
                        None => none_key
                      }
                      graph_subs.push((subkey, shaped))
                    }
                    Some(Index) => {
                      let subkey = match child.index {
                        Some(ix) => ix
                        None => none_key
                      }
                      // 带 @id 载体 = 载体渲染入 **term 组**（不走映射
                      // 组——@index 成员自带键信息，#t0083 oracle）；无 id
                      // = shaped 入映射组（#t0081）
                      if child.id is Some(_) {
                        match
                          compact_node_graph_value_jv(child, active, options) {
                          Ok(jv) =>
                            match group_vals.get(gt_name) {
                              Some(arr) => arr.push(jv)
                              None => {
                                group_vals[gt_name] = [jv]
                                group_keys.push(gt_name)
                                group_tds[gt_name] = gtd
                                group_array[gt_name] = !options.compact_arrays
                              }
                            }
                          Err(e) => return Err(e)
                        }
                      } else {
                        graph_subs.push((subkey, shaped))
                      }
                    }
                    Some(List)
                    | Some(Set)
                    | Some(Language)
                    | Some(Type)
                    | Some(Graph) => ()
                    // 裸次级：带 @id 载体 = 载体渲染（#t0080 oracle——
                    // "@id"+"@graph" 随形）；无 id = shaped
                    None =>
                      if child.id is Some(_) {
                        match
                          compact_node_graph_value_jv(child, active, options) {
                          Ok(jv) => graph_bares.push(jv)
                          Err(e) => return Err(e)
                        }
                      } else {
                        graph_bares.push(shaped)
                      }
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
      // non-map bare-fit 前置扫描（#t0089/#t0026 双 oracle 合流判据——
      // **无语言值**归 language-null term（确定性辖域），language 图
      // @none 不抢；**有语言值**仍归语言图按语言键归组）
      let no_lang_value = match v {
        ExpandedValue::Value(lit) => lit.language is None
        _ => false
      }
      if map_tds.length() > 0 && no_lang_value {
        for entry in cand_tds {
          let is_map = match entry.1.container {
            Some(Id) | Some(Type) | Some(Index) | Some(Language) => true
            _ => false
          }
          if !is_map && compact_bare_fit(v, entry.1, active) {
            let jv = match
              compact_value_item(v, Some(entry.1), active, scoped, options) {
              Ok(out) => out
              Err(e) => return Err(e)
            }
            match group_vals.get(entry.0) {
              Some(arr) => arr.push(jv)
              None => {
                group_vals[entry.0] = [jv]
                group_keys.push(entry.0)
                group_tds[entry.0] = entry.1
                group_array[entry.0] = match entry.1.container {
                  Some(Set) | Some(List) => true
                  _ => !options.compact_arrays
                }
              }
            }
            map_done = true
            break
          }
        }
        if map_done {
          continue
        }
      }
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
      // 两遍选 term：bare_fit 优先（吸收成裸形），object_fit 次之；
      // pass-1 多候选同 fit ⇒ **最短词形**排名（#t0057/#t0061/#t0044
      // oracle——exact 词 < base 相对 < 全 IRI）
      let mut chosen : (String, TermDefinition, Bool)? = None
      for pass_bare in [true, false] {
        // 排名键 = (词长, 词形级别, 特异性位降序)：同长时 exact/vocab 塌缩
        // 胜 base/全 IRI（#t0044），再同则 Set/Null 精确映射 > None 缺省
        // 对齐（#t0018/#t0024 oracle——en 项归 termLL1 非 termLL0）
        let mut best : (String, TermDefinition, Int, Int, Int)? = None
        for entry in cand_tds {
          let fits = if pass_bare {
            compact_bare_fit(v, entry.1, active)
          } else {
            compact_object_fit(v, entry.1, active)
          }
          if fits {
            let (word_len, word_rank) = compact_rank_word_len(
              v,
              Some(entry.1),
              active,
              options,
            )
            // 特异性双维（役30 第二维 datatype）：language-mapping term
            // 不得抢 typed 值（#t0015）；td @type 与值 datatype 合 ⇒ +1
            // （#t0024 oracle——type1 项归 termTL1 非 termLL0）；列的
            // datatype 位 = 全项 uniform 才计（役31 typed 值对象收集项）
            let v_dt = literal_datatype_of(v)
            let spec_lang = match (entry.1.language_mapping, v_dt) {
              (Some(_), None) => 1
              _ => 0
            }
            let spec_type = match (entry.1.datatype, v_dt) {
              (Some(dt), Some(vdt)) => if dt == vdt { 1 } else { 0 }
              _ => 0
            }
            let specificity = spec_lang + spec_type
            let better = match best {
              Some((_, _, bl, br, bs)) =>
                word_len < bl ||
                (
                  word_len == bl &&
                  (word_rank < br || (word_rank == br && specificity > bs))
                )
              None => true
            }
            if better {
              best = Some((entry.0, entry.1, word_len, word_rank, specificity))
            }
          }
        }
        match best {
          Some((name, td, _, _, _)) => chosen = Some((name, td, pass_bare))
          None => ()
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
            Some(outer_td) =>
              // 双定义取舍（#tc007 oracle——scoped @id 压过 outer 同名：
              // type-scoped 定义对该节点就是全量定义；@vocab 型仍随 outer
              // ——tc009 不塌裁断不变）
              if td_scoped.datatype == Some("@id") {
                td_scoped
              } else {
                outer_td
              }
            None =>
              {
                datatype: if td_scoped.datatype == Some("@id") ||
                  // @vocab 型同权保（#tc026——scoped-only @vocab term 词形
                  // 塌缩；outer 同名案仍走 outer 全权臂不受此位——#tc009）
                  td_scoped.datatype == Some("@vocab") ||
                  td_scoped.local_context is Some(_) {
                  td_scoped.datatype
                } else {
                  None
                },
                container: td_scoped.container,
                container_set: td_scoped.container_set,
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
                graph_set: td_scoped.graph_set,
                iri: td_scoped.iri,
              }
          }
          // 新节点对象回退（作用域两族边界表——type-scoped 不跨新节点，
          // #tc015 nestedNode 外层 base 相对）；id-only 节点是**父词形位**
          //（对象形/串塌缩由父渲染，随 value_chain 吃本节点 type-scoped
          // base——#tc015 subjectReference "#subject-reference-id"）
          // 完整新节点：scoped.previous 缺位 = propagate:true 类型作用域
          // 存活（#tc026——子节点继承 scoped）；在 = 回退外层（#tc015
          // nestedNode 外层 base 相对）；id-only 节点是父词形位随 value_chain
          let v_ctx = match v {
            ExpandedValue::Node(child) => {
              let node_ctx = if scoped.previous is None {
                scoped
              } else {
                active
              }
              if child.types.is_empty() &&
                child.properties.is_empty() &&
                child.reverse_props.is_empty() &&
                child.graph is None &&
                child.included is None &&
                child.index is None {
                value_chain
              } else {
                node_ctx
              }
            }
            _ => value_chain
          }
          let jv = match
            compact_value_item(v, Some(td), v_ctx, scoped, options) {
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
          // 新节点对象回退同 chosen 位（id-only 子节点=父词形位随
          // value_chain；完整新节点回退 active——#tc015 同判据）
          // 完整新节点：scoped.previous 缺位 = propagate:true 类型作用域
          // 存活（#tc026——子节点继承 scoped）；在 = 回退外层（#tc015
          // nestedNode 外层 base 相对）；id-only 节点是父词形位随 value_chain
          let v_ctx = match v {
            ExpandedValue::Node(child) => {
              let node_ctx = if scoped.previous is None {
                scoped
              } else {
                active
              }
              if child.types.is_empty() &&
                child.properties.is_empty() &&
                child.reverse_props.is_empty() &&
                child.graph is None &&
                child.included is None &&
                child.index is None {
                value_chain
              } else {
                node_ctx
              }
            }
            _ => value_chain
          }
          let jv = match compact_value_item(v, None, v_ctx, scoped, options) {
            Ok(out) => out
            Err(e) => return Err(e)
          }
          leftovers.push(jv)
        }
      }
    }
    // @graph 容器出键（§8.45——次级键映射归并内容数组；裸次级数组直出）
    match graph_td {
      Some((gname, gtd)) =>
        if graph_subs.length() > 0 {
          let sub_pairs : Array[(String, JsonValue)] = []
          let sub_keys : Array[String] = []
          let sub_vals : Map[String, Array[JsonValue]] = Map([])
          for entry in graph_subs {
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
                // graph_set 组：各载体已数组——摊平恒数组（#t0082 族
                // oracle——值已数组不再包）；非 graph_set 单值塌缩随
                // compactArrays
                let out = if gtd.graph_set {
                  let flat : Array[JsonValue] = []
                  for item in arr {
                    match item {
                      JsonValue::Array(items) =>
                        for it in items {
                          flat.push(it)
                        }
                      other => flat.push(other)
                    }
                  }
                  JsonValue::Array(flat)
                } else if options.compact_arrays && arr.length() == 1 {
                  arr[0]
                } else {
                  JsonValue::Array(arr)
                }
                sub_pairs.push((sub, out))
              }
              None => ()
            }
          }
          pairs.push((gname, JsonValue::Object(sub_pairs)))
        } else if graph_bares.length() > 0 {
          // 出形分叉（§8.52 shaped 化——graph_set 数组恒列（#t0078）；
          // 裸次级单图直出 / 多图数组（#t0077/#t0096））
          let gset = gtd.graph_set
          if gset {
            // graph_set：各图内容摊平恒数组（#t0078——单图单内容 [x] 直列）
            let content : Array[JsonValue] = []
            for gv in graph_bares {
              match gv {
                JsonValue::Array(items) =>
                  for it in items {
                    content.push(it)
                  }
                other => content.push(other)
              }
            }
            pairs.push((gname, JsonValue::Array(content)))
          } else {
            let out = if graph_bares.length() == 1 {
              graph_bares[0]
            } else {
              JsonValue::Array(graph_bares)
            }
            pairs.push((gname, out))
          }
        }
      None => ()
    }
    // 容器逆形映射出键（§8.43——subkey → 值；单值塌缩随 compactArrays）
    for name in map_names {
      match map_subs.get(name) {
        Some(entries) =>
          if entries.length() > 0 {
            // @set 并容保形位（#ts002——[@id|@type|@language|@index, @set]
            // 的 map 值恒数组，单值不塌缩）
            let td_set = {
              let mut found = false
              for mtd in map_tds {
                if mtd.0 == name {
                  found = mtd.1.container_set
                }
              }
              found
            }
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
                  let out = if options.compact_arrays &&
                    arr.length() == 1 &&
                    !td_set {
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
          // @json 值直出（#tjs07 oracle——@json 原值即 JSON，容器/塌缩不包；
          // datatype 位是**关键字形** "@json"（丁批 #tjs01 同形），full IRI
          // 形在管线中不存在——役34 勘定：旧守卫查 full IRI 恒不命中）
          let td_json = match group_tds.get(name) {
            Some(td) => td.datatype is Some("@json")
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
    // 空值属性 + 容器 term ⇒ 空数组出形（#t0004 oracle——myset2 []）
    if pair.1.is_empty() {
      let key = match cand_tds {
        cs if cs.length() > 0 => cs[0].0
        _ => compact_iri_word(pair.0, false, true, true, active, options)
      }
      pairs.push((key, JsonValue::Array([])))
    }
    // 残余 → 兜底键（前缀/相对词形——#t0006 "ex:term1" oracle）；本属性
    // 已有 term 组时禁 vocab 步（#tdi07 oracle——vocab 相对词撞 term 键，
    // 落全 IRI）
    if leftovers.length() > 0 {
      let fallback_vocab = group_keys.length() == 0 && map_names.length() == 0
      // 兜底键随键选择链（#tc016——type-scoped vocab 下 com 词形塌缩）
      let fallback_key = compact_iri_word(
        pair.0,
        false,
        fallback_vocab,
        true,
        scoped,
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
        "@included", true, false, true, active, options,
      )
      // @included 单值解包为对象形（#tin02/#tin04/#tin05 oracle——与
      // @graph 关键词条恒数组分叉：REC 出形位不同）；别名 term 带
      // @container @set ⇒ 恒数组（#tin01 oracle）
      let included_set = match active.terms.get(included_key) {
        Some(itd) => itd.container is Some(Set)
        None => false
      }
      if options.compact_arrays && arr.length() == 1 && !included_set {
        pairs.push((included_key, arr[0]))
      } else {
        pairs.push((included_key, JsonValue::Array(arr)))
      }
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
      // 节点自身 @graph 关键词条 = as-array 恒真（REC 12.8.5——active
      // property = @graph 时 as array；#t0016 oracle——成员带 @id 保数组。
      // 塌缩只发生在值位渲染的数组步——compact_node_graph_value_jv）
      pairs.push(("@graph", JsonValue::Array(arr)))
    }
    None => ()
  }
  // @reverse 正向提升（#t0033/#t0050 oracle——reverse term 匹配 → 普通属性；
  // 无匹配 → "@reverse" 包裹形保真）；映射容器 reverse 走归组账
  let rev_map_names : Array[String] = []
  let rev_map_subs : Map[String, Array[(String, JsonValue)]] = Map([])
  let rev_pairs : Array[(String, JsonValue)] = []
  for pair in node.reverse_props {
    let cands = compact_term_candidates(pair.0, true, active)
    if cands.length() > 0 {
      let rev_name = cands[0]
      let rev_td : TermDefinition? = match active.terms.get(rev_name) {
        Some(t) => Some(t)
        None => None
      }
      // reverse term 带映射容器 ⇒ 反转值走映射归组（#t0036 oracle——
      // @reverse + @container @index → 键化出形）
      let rev_is_map = match rev_td {
        Some(t) =>
          match t.container {
            Some(Id) | Some(Type) | Some(Index) | Some(Language) => true
            _ => false
          }
        None => false
      }
      if rev_is_map {
        match rev_td {
          Some(t) =>
            for v in pair.1 {
              match compact_map_entry(v, t, active, options) {
                Some((subkey, rendered)) => {
                  let existed = rev_map_subs.contains(rev_name)
                  match rev_map_subs.get(rev_name) {
                    Some(arr) => arr.push((subkey, rendered))
                    None => rev_map_subs[rev_name] = [(subkey, rendered)]
                  }
                  if !existed {
                    rev_map_names.push(rev_name)
                  }
                }
                None =>
                  match
                    compact_property_pair(pair.0, true, [v], active, options) {
                    Ok(pair_out) => pairs.push(pair_out)
                    Err(e) => return Err(e)
                  }
              }
            }
          None => ()
        }
      } else {
        // 值级最短词形排名分键（#t0044 oracle——dave→knows 全词、
        // DefinedTerm→knowsVocab exact 词；同 IRI 双 term 按值拆键；
        // 役31 抽 compact_reverse_split_pairs 双路复用）
        match
          compact_reverse_split_pairs(pair.0, cands, pair.1, active, options) {
          Ok(split_pairs) =>
            for split_pair in split_pairs {
              pairs.push(split_pair)
            }
          Err(e) => return Err(e)
        }
      }
    } else {
      // 无 @reverse 定义 term：正向 term 逐值分键（役31 #t0044 第二路——
      // @type @id/@vocab 普通 term 在 @reverse 位同 IRI 双候选按值拆键，
      // 出形保 @reverse 包裹）；无正向候选落整体渲染兜底
      let fwd_cands = compact_term_candidates(pair.0, false, active)
      if fwd_cands.length() > 0 {
        match
          compact_reverse_split_pairs(
            pair.0,
            fwd_cands,
            pair.1,
            active,
            options,
          ) {
          Ok(split_pairs) =>
            for split_pair in split_pairs {
              rev_pairs.push(split_pair)
            }
          Err(e) => return Err(e)
        }
      } else {
        match compact_property_pair(pair.0, false, pair.1, active, options) {
          Ok(pair_out) => rev_pairs.push(pair_out)
          Err(e) => return Err(e)
        }
      }
    }
  }
  if rev_pairs.length() > 0 {
    pairs.push(("@reverse", JsonValue::Object(rev_pairs)))
  }
  // reverse 映射组出键（#t0036——子键归并，组内单值塌缩随 compactArrays）
  for name in rev_map_names {
    match rev_map_subs.get(name) {
      Some(entries) => {
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
  let none_key = compact_iri_word("@none", true, false, true, active, options)
  match td.container {
    Some(Id) =>
      match value {
        ExpandedValue::Node(child) => {
          let subkey = match child.id {
            Some(id) =>
              compact_iri_word(id, false, false, true, active, options)
            None => none_key
          }
          let id_key = compact_iri_word(
            "@id", true, false, true, active, options,
          )
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
          // 键化 type 的 scoped context 预套（役37/#tm007——type-map 值
          // 渲染的键链：键化 type 的 type-scoped 定义须活于值位词形；
          // variant 已剥 types[0]，内层 apply 见不到）
          let keyed_chain = match child.types.get(0) {
            Some(t0) => compact_apply_type_scoped([t0], active, options)
            None => active
          }
          if variant_bare {
            match variant.id {
              Some(id) =>
                Ok(
                  JsonValue::String(
                    compact_iri_word(
                      id,
                      false,
                      td.datatype is Some("@vocab"),
                      true,
                      keyed_chain,
                      options,
                    ),
                  ),
                )
              None => compact_node_jv(variant, keyed_chain, options)
            }
          } else {
            compact_node_jv(variant, keyed_chain, options)
          }
        }
        ExpandedValue::Value(lit) => {
          // 字面量 datatype 键化 → 值对象去 @type 对
          let rendered_lit = compact_value_jv(
            lit,
            None,
            active,
            active,
            options,
          )
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
            Some(t) => compact_iri_word(t, true, true, true, active, options)
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
          let prop_iri = match
            IriExpander::expand_iri(
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
                    let prop_cands = compact_term_candidates(
                      prop_iri, false, active,
                    )
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
                                    true,
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
                  match
                    compact_value_item(value, Some(td), active, active, options) {
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
                match
                  compact_value_item(value, Some(td), active, active, options) {
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
          Ok(compact_value_jv(bare_lit, None, active, active, options))
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
          // index 闸（#t0065 oracle——带 @index 的值不入语言图，落残余
          // 兜底键全 IRI 值对象形）
          if !dir_ok || lit.index is Some(_) {
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
  // 逆序套用（REC §6.1.2 步 12.8.1——@type 数组倒序逐个套 type-scoped
  // context，先位类型后手胜——#tc017 oracle：[Foo,Bar] Foo 的 prop 胜出）
  for i in 0..<types.length() {
    let t = types[types.length() - 1 - i]
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

///|
/// 图对象值位渲染（REC 12.8.8.4——节点渲染后，@graph 键（含别名）单内容
/// 塌缩为对象形；关键字词条 as-array 恒真不在此路——#t0092/#t0094/#t0080
/// /#t0083 oracle 值位塌缩，#t0016 关键词条保数组）
fn compact_node_graph_value_jv(
  node : ExpandedNode,
  active : ActiveContext,
  options : JsonLdOptions,
) -> Result[JsonValue, JsonLdError] {
  let jv = compact_node_jv(node, active, options)
  match jv {
    Ok(JsonValue::Object(pairs)) => {
      let graph_key = compact_iri_word(
        "@graph", true, false, true, active, options,
      )
      let out : Array[(String, JsonValue)] = []
      for p in pairs {
        if p.0 == graph_key {
          match p.1 {
            JsonValue::Array(items) =>
              if options.compact_arrays && items.length() == 1 {
                out.push((p.0, items[0]))
              } else {
                out.push(p)
              }
            _ => out.push(p)
          }
        } else {
          out.push(p)
        }
      }
      Ok(JsonValue::Object(out))
    }
    _ => jv
  }
}

///|
/// list 值 bare 适配（役30 从 bare_fit 内联链抽出——顶层具名函数规避
/// 深嵌套 match 文法坑；役31 闸形与 Value 臂对齐——datatype 分支优先，
/// 语言只属无 @type 面）：index 闸 / @list 容器闸 / 方向闸 / type 闸
/// （uniform 整列）/ 语言镜像（含标量免疫）
fn compact_list_bare_fit(
  items : Array[ExpandedValue],
  index : String?,
  td : TermDefinition,
  active : ActiveContext,
) -> Bool {
  if index is Some(_) {
    false
  } else if td.container is Some(List) {
    let dir_ok = match td.direction_mapping {
      Some(Set(d)) =>
        match items.get(0) {
          Some(ExpandedValue::Value(lit)) => lit.direction == Some(d)
          _ => true
        }
      _ => true
    }
    if !dir_ok {
      false
    } else {
      match td.datatype {
        // @type 版 term：整列 uniform datatype 才吸收（与 Value 臂同形——
        // datatype 吸收面与语言无关）；混合 typed 列不归 @type term
        Some(dt) => {
          let mut uniform = true
          for item in items {
            let item_dt : String? = match item {
              ExpandedValue::Value(lit) => lit.datatype
              _ => None
            }
            if item_dt != Some(dt) {
              uniform = false
            }
          }
          uniform
        }
        None => {
          // 无 @type：语言镜像（首项定调）+ 免注免疫（raw 标量 + typed 值
          // 对象——重展开不受缺省语言注入）；type 面恒容——typed 项以值
          // 对象形居裸数组（役27 None⇒typed 值对象形；#t0024 termTL0 混合列）
          let first_lang = match items.get(0) {
            Some(ExpandedValue::Value(lit)) => lit.language
            _ => None
          }
          let first_immune = match items.get(0) {
            Some(ExpandedValue::Value(lit)) =>
              lit.raw is Some(_) || lit.datatype is Some(_)
            _ => false
          }
          let lang_ok = match td.language_mapping {
            Some(Set(lang)) =>
              match first_lang {
                Some(fl) => lang_tag_eq(fl, lang)
                None => false
              }
            Some(Null) => first_lang is None
            None => {
              // 缺省对齐（termLL0 收缺省 de 项）；免注免疫（#t0018 [1,2]
              // 数值列、#t0024 termTL0 typed 列）
              let aligned = match first_lang {
                Some(l) => lang_tag_eq(l, active.default_language.unwrap_or(""))
                None => active.default_language is None
              }
              first_immune || aligned
            }
          }
          lang_ok
        }
      }
    }
  } else {
    false
  }
}
