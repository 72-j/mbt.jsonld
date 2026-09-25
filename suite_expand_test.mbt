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

///|
/// per-case options：manifest option.specVersion → processing_mode
/// （③细化勘定：@vocab 判定模式分叉——#t0092[1.1] vs #t0115/#t0116[1.0]）
fn options_for(entry : @jsonld.JsonValue) -> @jsonld.JsonLdOptions {
  let mut mode = @jsonld.ProcessingMode::JsonLd11
  match json_object_get(entry, "option") {
    Some(option_value) =>
      match json_string_get(option_value, "specVersion") {
        Some("json-ld-1.0") => mode = @jsonld.ProcessingMode::JsonLd10
        _ => ()
      }
    None => ()
  }
  @jsonld.JsonLdOptions::{
    base: None,
    expand_context: None,
    processing_mode: mode,
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
  // 已迁移 plain 的条目（逐例；每例附"为什么能迁"——覆盖/未覆盖关键字）
  let migrated : Array[String] = [
    // #t0001：覆盖 @id + free-floating drop + 顶层形态（[]）；未覆盖 @context /
    // term 展开 / @value 值对象 / 数组滤 null——仍在 deferred
    "#t0001",
    // #t0045（值对象族第一批 · @value+@language 批）：覆盖顶层值对象丢弃
    // （{"@value":…} → []）+ @value 词形保留（string/number/bool）+ @language 键序无关
    // 合并 + postprocess 归一（空语言清除）；未覆盖 @context（默认语言/别名）、
    // coercion（@type datatype 派生挂①批——显式 @type；B/C 挂 term/IRI 批后）、
    // 嵌套位置值对象（挂 @context 批后）
     "#t0045",
    // —— harness per-case options 批（specVersion 注入解锁 1.0 负例）——
    // #t0115（负·1.0 模式）：@vocab 空串 → invalid vocab mapping（vocab 1.0 校验③细化已落）
     "#t0115",
    // #t0116（负·1.0 模式）：@vocab 相对值 → invalid vocab mapping
     "#t0116",
    // —— ①批 coercion（形态 A：显式 @type → datatype）——
    // #t0013：已展开文档再展开——@type 节点侧数组、属性累加（多值）、number 保形、
    // 值对象 @type/@language/@value 合成
     "#t0013",
    // #t0123（负）：datatype 含空白 IRI → invalid typed value
     "#t0123",
    // #tdi09（负）：@direction 与 @type 互斥 → invalid value object
     "#tdi09",
    // #ter28（负）：@type 非串（bool）→ invalid type value
     "#ter28",
    // #ter38（负）：@value + @language + @type 同现 → invalid value object
     "#ter38",
    // #ter54（负）：值对象 @type 多值 → invalid typed value
     "#ter54",
    // —— ④批 A 组（依赖分组勘定 + 探针实测 74/101 通过；逐例端到端对拍由本 harness 执行）——
    // A 组 = 只依赖已落语义（@context 简单声明 + term 字符串定义 + 值对象 + coercion 形态 A）
    // 27 例挂账留 deferred：mismatch ×10 / unexpected-error ×9 / should-error ×7（详见 todo §J2 ④批）
     "#t0003", "#t0075", "#t0092", "#tc029", "#tc030", "#tc032", "#tc033", "#tdi08",
    "#tec02", "#tem01", "#ten01", "#ten02", "#ten03", "#ten04", "#ten05", "#tep02",
    "#tep03", "#ter04", "#ter05", "#ter06", "#ter07", "#ter10", "#ter12", "#ter13",
    "#ter21", "#ter22", "#ter23", "#ter24", "#ter25", "#ter27", "#ter29", "#ter30",
    "#ter31", "#ter33", "#ter34", "#ter35", "#ter36", "#ter41", "#ter42", "#ter53",
    "#ter55", "#ter56", "#tes01", "#tes02", "#tin07", "#tin08", "#tin09", "#tm020",
    "#tpi05", "#tpr01", "#tpr03", "#tpr04", "#tpr05", "#tpr08", "#tpr09", "#tpr11",
    "#tpr12", "#tpr17", "#tpr18", "#tpr20", "#tpr21", "#tpr26", "#tpr28", "#tpr31",
    "#tpr32", "#tpr42", "#tso01", "#tso02", "#tso03", "#tso07", "#tso10", "#tso12",
    "#tso13", "#ttn01",
  ]
  // 两桶：迁移例走端到端对拍（输入 → expansion → 对 expected）；其余 deferred
  let deferred : Array[String] = []
  let plain : Array[String] = []
  let mut parsed_ok = 0
  let mut parse_err = 0
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    // 解析覆盖通道：全部有 input 的条目都过 parse_json（J0 解析器口径持续验证）
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
    // 负性判定：manifest @type 含 jld:NegativeEvaluationTest
    let is_negative = match json_object_get(entry, "@type") {
      Some(@jsonld.JsonValue::Array(kinds)) => {
        let mut neg = false
        for kind in kinds {
          match kind {
            @jsonld.JsonValue::String(k) =>
              if k == "jld:NegativeEvaluationTest" {
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
      // plain：端到端真判据——正例对拍 expected（键序归一）；负例必须报错
      // （任意 Err 即负例通过；错误码细分挂账）
      let input_path = match json_string_get(entry, "input") {
        Some(path) => path
        None => fail("\{id}: migrated but no input")
      }
      let input_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + input_path).binary(),
      )
      if is_negative {
        match @jsonld.expand_document(input_text, options_for(entry)) {
          Err(_) => ()
          Ok(_) => fail("\{id}: negative case unexpectedly expanded")
        }
      } else {
        let expect_path = match json_string_get(entry, "expect") {
          Some(path) => path
          None => fail("\{id}: migrated positive but no expect")
        }
        let actual = match
          @jsonld.expand_document(input_text, options_for(entry)) {
          Ok(value) => value
          Err(_) => fail("\{id}: expansion error (hook 未落码?)")
        }
        let expected_text = @utf8.decode(
          @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + expect_path).binary(),
        )
        let expected = match @jsonld.parse_json(expected_text) {
          Ok(value) => value
          Err(_) => fail("\{id}: expected output unparseable")
        }
        assert_eq(
          @jsonld.json_canonical(actual),
          @jsonld.json_canonical(expected),
        )
      }
      plain.push(id)
    } else {
      deferred.push(id)
    }
  }
  // pin 闭合：桶总和 == 普查数；plain = 已迁移数
  assert_eq(deferred.length(), 301)
  assert_eq(plain.length(), 84)
  // 解析覆盖闭合：每个有 input 的条目都走了解析通道
  assert_eq(parsed_ok + parse_err, 385)
  // 首例钉：#t0001 已迁 plain（manifest 顺序首条；J2 首件验收 = 此例端到端绿）
  assert_true(plain.contains("#t0001"))
}
