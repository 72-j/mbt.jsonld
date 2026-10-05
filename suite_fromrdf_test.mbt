///|
/// fromRDF 套件 harness（役57——spec §8.130 钉）：官方 fromRdf 套件 54 例
/// （正 52 + 负 2）全 plain。判定 = canonical_for_suite 直比 + bnode 双射
/// 兜底。通道 = from_rdf_document(输入 N-Quads 原文, options)。
async test "fromRDF suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./.rdf-tests/json-ld-api/fromRdf-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
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
    plain.push(id)
    let input_text = @utf8.decode(
      @fs.read_file(
        "./.rdf-tests/json-ld-api/" + json_string_get(entry, "input").unwrap(),
      ).binary(),
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
    match @jsonld.from_rdf_document(input_text, options) {
      Err(_) => if !is_neg { fail("\{id}: 正例 fromRDF 报错") }
      Ok(converted) =>
        if is_neg {
          fail("\{id}: 负例意外全绿")
        } else {
          let expect_path = match json_string_get(entry, "expect") {
            Some(ep) => ep
            None => fail("\{id}: 正例无 expect")
          }
          let expect_text = @utf8.decode(
            @fs.read_file("./.rdf-tests/json-ld-api/" + expect_path).binary(),
          )
          let expected_value = match @jsonld.parse_json(expect_text) {
            Ok(v) => v
            Err(_) => fail("\{id}: expected 解析失败")
          }
          let ours = diag_json_str(@jsonld.canonical_for_suite(converted))
          let expected = diag_json_str(
            @jsonld.canonical_for_suite(expected_value),
          )
          if ours != expected {
            if !@jsonld.isomorphic_for_suite(converted, expected_value) {
              fail(
                "\{id}: fromRDF 对拍不一致\n  ours=\{ours}\n  expect=\{expected}",
              )
            }
          }
        }
    }
  }
  assert_eq(deferred.length(), 0)
  assert_eq(plain.length(), 54)
  // 复核面自报行（J4；suite-review.txt 抽取源——勿改格式）
  println(
    "[fromRdf] entries=\{sequence.length()} plain=\{plain.length()} deferred=\{deferred.length()}",
  )
}
