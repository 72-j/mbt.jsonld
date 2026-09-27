///|
/// toRdf 套件 harness（J3.0——判定器就位（tordf_judge_test.mbt），管线 J3.1
/// 接线；spec §8 前置勘定）：manifest 驱动 467 例两桶 plain/deferred，pin 闭合。
/// 判定通道（J3.1 起）：正例 = expand → node_to_quads → datasets_isomorphic
/// （expected .nq 经 parse_nquads 归一——RDF Dataset Isomorphism，非 JSON
/// 对拍）；负例 = 管线任一段 Err；句法 = 全程无 Err。选项面 useJCS×23/
/// rdfDirection×4/produceGeneralizedRdf×2 随管线批接线（JCS 独立子役）。
async test "toRdf suite harness: judge ready, all deferred pre-J3.1" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  // J3.1 起迁 plain（管线落码后逐例）；J3.0 判定器自测在 tordf_judge_test.mbt
  let migrated : Array[String] = []
  let deferred : Array[String] = []
  let plain : Array[String] = []
  let mut parsed_ok = 0
  let mut parse_err = 0
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    // 解析覆盖通道：全部 467 输入过 parse_json（J0 解析器口径持续验证——
    // 与 expand harness 同款）
    match json_string_get(entry, "input") {
      Some(input_path) => {
        let text = @utf8.decode(
          @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + input_path).binary(),
        )
        match @jsonld.parse_json(text) {
          Ok(_) => parsed_ok += 1
          Err(_) => parse_err += 1
        }
      }
      None => ()
    }
    if migrated.contains(id) {
      plain.push(id)
      // J3.1 接线位：正例 = expand → node_to_quads → parse_nquads(expect) →
      // datasets_isomorphic；负例 = 管线 Err（错误码共用面——spec §8.4）；
      // 句法 = 全程无 Err
      fail("\{id}: toRdf plain 判定通道 J3.1 接线")
    } else {
      deferred.push(id)
    }
  }
  // pin 闭合：桶总和 == 普查数（467 = 345 正 + 106 负 + 16 句法——spec §8.1）
  assert_eq(deferred.length(), 467)
  assert_eq(plain.length(), 0)
  assert_eq(parsed_ok + parse_err, 467)
  assert_true(parse_err == 0)
}
