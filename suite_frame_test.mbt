///|
/// framing 套件 harness（J5——spec §8.93 勘定 / §8.94 开工第一笔）：官方
/// json-ld-framing 套件 @ `3bf782ba` manifest 驱动 92 例两桶（正 89 +
/// 负 3）。判定 = canonical_for_suite 直比 + isomorphic_for_suite bnode
/// 双射兜底。通道 = frame_document(输入原文, frame 原文, options)。
/// 开工第一笔立桩：92 例全 deferred（framing 面未落码，Unsupported 挂账
/// ——§8.93 勘 4 簇表为逐簇解释）——首役起逐役迁移清桶（#t0001 冒烟起）。
async test "framing suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file(
      "./src/jsonld/.rdf-tests/json-ld-framing/frame-manifest.jsonld",
    ).binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  // 已迁移例（plain 桶）——首役 #t0001 起逐役增长；deferred = 未落码例
  // （逐簇解释见 spec §8.93 勘 4 簇表 + 各役落账）
  // 役49 匹配语法批（spec §8.98）：match-none/wildcard/@id-@type pattern/
  // requireAll/default-only/value pattern 十簇 + 帧旗批 + 冒烟
  let migrated : Array[String] = [
    "#t0001", "#t0002", "#t0003", "#t0004", "#t0005", "#t0009", "#t0023", "#t0024",
    "#t0025", "#t0026", "#t0027", "#t0029", "#t0031", "#t0032", "#t0033", "#t0034",
    "#t0035", "#t0036", "#t0037", "#t0038", "#t0039", "#t0040", "#t0041", "#t0042",
    "#t0043", "#t0044", "#t0045", "#t0046", "#t0047", "#t0011", "#t0013", "#t0014",
    "#t0019", "#t0028", "#t0055", "#t0056", "#t0030", "#t0059", "#t0060", "#tg001",
    "#tg002", "#tg003", "#tg004", "#tg005", "#tg006", "#tg007", "#tg008", "#tg009",
    "#tp020", "#tp050",
  ]
  let deferred : Array[String] = []
  let plain : Array[String] = []
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    let is_neg = match json_object_get(entry, "@type") {
      Some(@jsonld.JsonValue::Array(kinds)) => {
        let mut neg = false
        for k in kinds {
          match k {
            @jsonld.JsonValue::String(kind) =>
              if kind == "jld:NegativeEvaluationTest" {
                neg = true
              }
            _ => ()
          }
        }
        neg
      }
      _ => false
    }
    if migrated.contains(id) {
      plain.push(id)
      let input_path = match json_string_get(entry, "input") {
        Some(p) => p
        None => fail("\{id}: migrated but no input")
      }
      let frame_path = match json_string_get(entry, "frame") {
        Some(p) => p
        None => fail("\{id}: migrated but no frame")
      }
      let input_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-framing/" + input_path).binary(),
      )
      let frame_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-framing/" + frame_path).binary(),
      )
      let context_map : Map[String, String] = Map([])
      match @jsonld.parse_json(input_text) {
        Ok(parsed_input) =>
          match frame_base_for_entry(entry) {
            Some(anchor_url) =>
              preload_contexts(anchor_url, parsed_input, context_map)
            None => ()
          }
        Err(_) => ()
      }
      let options = frame_options_for(entry, context_map)
      match @jsonld.frame_document(input_text, frame_text, options) {
        Err(_) => if !is_neg { fail("\{id}: 正例 frame 报错") }
        Ok(framed) =>
          if is_neg {
            fail("\{id}: 负例意外全绿")
          } else {
            let expect_path = match json_string_get(entry, "expect") {
              Some(ep) => ep
              None => fail("\{id}: 正例无 expect")
            }
            let expect_text = @utf8.decode(
              @fs.read_file(
                "./src/jsonld/.rdf-tests/json-ld-framing/" + expect_path,
              ).binary(),
            )
            let expected_value = match @jsonld.parse_json(expect_text) {
              Ok(v) => v
              Err(_) => fail("\{id}: expected 解析失败")
            }
            let ours = diag_json_str(@jsonld.canonical_for_suite(framed))
            let expected = diag_json_str(
              @jsonld.canonical_for_suite(expected_value),
            )
            if ours != expected {
              if !@jsonld.isomorphic_for_suite(framed, expected_value) {
                fail(
                  "\{id}: frame 对拍不一致\n  ours=\{ours}\n  expect=\{expected}",
                )
              }
            }
          }
      }
    } else {
      deferred.push(id)
    }
  }
  assert_eq(deferred.length(), 45)
  assert_eq(plain.length(), 47)
}

///|
/// framing 锚（base 缺省 = 输入文档 URL 含文件名；option.base 覆盖优先
/// ——与 api 套件 base_for_entry 同款两步；域不同故本地面，不扰共用件）
fn frame_base_for_entry(entry : @jsonld.JsonValue) -> String? {
  match json_object_get(entry, "option") {
    Some(option_value) =>
      match json_string_get(option_value, "base") {
        Some(b) => Some(b)
        None => frame_base_from_input(entry)
      }
    None => frame_base_from_input(entry)
  }
}

///|
fn frame_base_from_input(entry : @jsonld.JsonValue) -> String? {
  match json_string_get(entry, "input") {
    Some(input_path) =>
      Some("https://w3c.github.io/json-ld-framing/tests/" + input_path)
    None => None
  }
}

///|
/// framing per-case options：options_for 同源（specVersion/processingMode
/// 并行、任一指 1.0 即 1.0）+ base 覆写为 framing 锚。omitGraph / ordered
/// 选项随面落码批进 JsonLdOptions（deferred 期无判定路径，落码役同笔带）
fn frame_options_for(
  entry : @jsonld.JsonValue,
  map : Map[String, String],
) -> @jsonld.JsonLdOptions {
  let opts = options_for(entry, map)
  {
    base: frame_base_for_entry(entry),
    expand_context: opts.expand_context,
    processing_mode: opts.processing_mode,
    load_context: opts.load_context,
    rdf_direction: opts.rdf_direction,
    produce_generalized_rdf: opts.produce_generalized_rdf,
    compact_arrays: opts.compact_arrays,
    compact_to_relative: opts.compact_to_relative,
    frame_expansion: false,
    omit_graph: false,
  }
}
