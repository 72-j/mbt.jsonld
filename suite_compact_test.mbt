///|
/// compact 套件 harness（J6——spec §8.41）：manifest 驱动 246 例两桶
/// （229 正 + 17 负），判定 = canonical_for_suite 直比 + bnode 双射兜底
/// （isomorphic_for_suite 复用——bnode 输入面标签序差）。
/// 通道 = compact_document(输入原文, context 文件原文, options)。
async test "compact suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/compact-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  // J6 首波 + 役2 容器逆形 + 役3 scoped + 役4 @graph + 役5 gen-delim 闸
  // （2026-09-29；146/246 plain——正 131 + 负 15；缺口在册 §8.42-§8.46——
  // nullification 族/tpi 属性化索引/语言敏感 list/te002）
  let migrated : Array[String] = [
    "#t0001", "#t0002", "#t0003", "#t0005", "#t0006", "#t0008", "#t0009", "#t0010",
    "#t0011", "#t0012", "#t0013", "#t0014", "#t0016", "#t0017", "#t0019", "#t0020",
    "#t0021", "#t0025", "#t0026", "#t0028", "#t0029", "#t0030", "#t0031", "#t0032",
    "#t0033", "#t0034", "#t0035", "#t0039", "#t0040", "#t0046", "#t0047", "#t0049",
    "#t0050", "#t0051", "#t0052", "#t0053", "#t0058", "#t0060", "#t0062", "#t0063",
    "#t0064", "#t0067", "#t0068", "#t0069", "#t0071", "#t0072", "#t0074", "#t0075",
    "#t0078", "#t0082", "#t0086", "#t0087", "#t0095", "#t0099", "#t0101", "#t0102",
    "#t0103", "#t0107", "#t0108", "#ta038", "#tc001", "#tc002", "#tc003", "#tc005",
    "#tc006", "#tc009", "#tc010", "#tc013", "#tc014", "#tc019", "#tc027", "#tc028",
    "#tdi01", "#tdi04", "#tdi05", "#tdi06", "#te001", "#ten01", "#tep05", "#tep06",
    "#tep07", "#tep08", "#tep09", "#tep10", "#tep11", "#tep12", "#tep13", "#tep14",
    "#tep15", "#tin01", "#tin03", "#tjs01", "#tjs02", "#tjs03", "#tjs04", "#tjs05",
    "#tjs06", "#tjs08", "#tjs10", "#tjs11", "#tli01", "#tli02", "#tli03", "#tli04",
    "#tli05", "#tm001", "#tm002", "#tm003", "#tm004", "#tm005", "#tm006", "#tm008",
    "#tm009", "#tm010", "#tm011", "#tm012", "#tm013", "#tm014", "#tm015", "#tm016",
    "#tm017", "#tm020", "#tm021", "#tm022", "#tm023", "#tn001", "#tn002", "#tn003",
    "#tn004", "#tn005", "#tn010", "#tn011", "#tp001", "#tp002", "#tp003", "#tp004",
    "#tp005", "#tp006", "#tp007", "#tp008", "#tpi06", "#tpr01", "#tpr02", "#tpr04",
    "#tr001", "#tr002",
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
      let context_path = match json_string_get(entry, "context") {
        Some(p) => p
        None => fail("\{id}: migrated but no context")
      }
      let input_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + input_path).binary(),
      )
      let context_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + context_path).binary(),
      )
      let context_map : Map[String, String] = Map([])
      match @jsonld.parse_json(input_text) {
        Ok(parsed_input) =>
          match base_for_entry(entry) {
            Some(anchor_url) =>
              preload_contexts(anchor_url, parsed_input, context_map)
            None => ()
          }
        Err(_) => ()
      }
      let options = options_for(entry, context_map)
      match @jsonld.compact_document(input_text, context_text, options) {
        Err(_) => if !is_neg { fail("\{id}: 正例 compact 报错") }
        Ok(compacted) =>
          if is_neg {
            fail("\{id}: 负例意外全绿")
          } else {
            let expect_path = match json_string_get(entry, "expect") {
              Some(ep) => ep
              None => fail("\{id}: 正例无 expect")
            }
            let expect_text = @utf8.decode(
              @fs.read_file(
                "./src/jsonld/.rdf-tests/json-ld-api/" + expect_path,
              ).binary(),
            )
            let expected_value = match @jsonld.parse_json(expect_text) {
              Ok(v) => v
              Err(_) => fail("\{id}: expected 解析失败")
            }
            let ours = diag_json_str(@jsonld.canonical_for_suite(compacted))
            let expected = diag_json_str(
              @jsonld.canonical_for_suite(expected_value),
            )
            if ours != expected {
              if !@jsonld.isomorphic_for_suite(compacted, expected_value) {
                fail(
                  "\{id}: compact 对拍不一致\n  ours=\{ours}\n  expect=\{expected}",
                )
              }
            }
          }
      }
    } else {
      deferred.push(id)
    }
  }
  assert_eq(deferred.length(), 100)
  assert_eq(plain.length(), 146)
}
