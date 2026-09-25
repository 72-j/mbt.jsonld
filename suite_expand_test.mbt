///|
/// expand 官方套件前置 harness（对拍流水线 J2 前置件）。
/// 桶纪律（AGENTS.md 套件纪律）：plain（有真判据的例）/ deferred（planned）。
/// **deferred 语义**：暂不判定，**非"已知不通过"**——迁移必须逐例（进 plain 前先有
/// 真判据），禁止批量搬桶掩盖真通过/真失败。
/// **pin 常驻**：闭合断言不是一次性检查——manifest 上游更新（条目增删）即 pin 红，
/// 逼迫账本（本表 + 基线文件）同笔更新。
/// **#t0001 首例语义**：manifest 顺序首条（顺序标记），非"最小可验证用例"之选；
/// J2 首件验收 = 让 #t0001 单例端到端绿（deferred → plain）。
/// **389/385 口径**：目录内 389 个 `*-in.jsonld` 文件 / manifest 条目 385，
/// 差 4 为 option 变体件（同输入不同选项）；harness 与基线一律按 manifest 条目计。
/// 解析通道走本包 `parse_json`（官方包装层喂官方语料，J0 解析器口径的活体验证）。

///|
/// 取对象字段（键序无关；命中即返）
fn json_object_get(
  value : @jsonld.JsonValue,
  key : String,
) -> @jsonld.JsonValue? {
  match value {
    @jsonld.JsonValue::Object(pairs) =>
      for pair in pairs {
        if pair.0 == key {
          return Some(pair.1)
        }
      }
    _ => ()
  }
  None
}

///|
/// 取字符串字段
fn json_string_get(value : @jsonld.JsonValue, key : String) -> String? {
  match json_object_get(value, key) {
    Some(@jsonld.JsonValue::String(s)) => Some(s)
    _ => None
  }
}

///|
async test "expand suite harness: manifest-driven buckets, all deferred pre-J2" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/expand-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(items)) => items
    _ => fail("manifest: sequence missing")
  }
  // J0 普查钉：清单条目数 == 385
  assert_eq(sequence.length(), 385)
  // 两桶：v1 全 deferred（expansion 运行器 J2 接入）；plain 逐例迁移
  let deferred : Array[String] = []
  let plain : Array[String] = []
  let mut parsed_ok = 0
  let mut parse_err = 0
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
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
    deferred.push(id)
  }
  // pin 闭合：桶总和 == 普查数；plain v1 为空
  assert_eq(deferred.length(), 385)
  assert_eq(plain.length(), 0)
  // 解析覆盖闭合：每个有 input 的条目都走了解析通道
  assert_eq(parsed_ok + parse_err, 385)
  // 首例钉：#t0001 在册（manifest 顺序首条；J2 首件验收 = 此例端到端绿）
  assert_true(deferred.contains("#t0001"))
}
