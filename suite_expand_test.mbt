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
  let mut base : String? = None
  match json_object_get(entry, "option") {
    Some(option_value) => {
      match json_string_get(option_value, "specVersion") {
        Some("json-ld-1.0") => mode = @jsonld.ProcessingMode::JsonLd10
        _ => ()
      }
      base = json_string_get(option_value, "base")
    }
    None => ()
  }
  // 默认 base 注入（document location 约定，#t0051 需要）**不可全局开**：
  // vocab 位键展开（无 @vocab）规范语义 = 原样返回、不落 base merge（#t0003
  // oracle：未映射 term 必须丢弃——全局 base 会把它解析成绝对而保留）。
  // 挂账：expand_iri vocab 位 base 门控勘定批 + 本注入同批落
  { base, expand_context: None, processing_mode: mode, }
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
    // —— RFC 3986 5.2.3 merge 批（base 无尾斜杠：截最后段 + 相对引用；t0129/t0130）——
     "#t0129", "#t0130",
    // #t0072（③细化）：term 重定义为自身 + @vocab → anotherVocab#term
     "#t0072",
    //（#t0051 挂账：别名链已通，还差 harness 默认 base + vocab 位 base 门控——
    // 见 options_for 注记；merge 绝对路径分支已落码，wbtest 对拍在案）
    // —— base 解析批（resolve_base_value：合并 + ".." 弹段 + "." 保留，oracle #t0090/#t0091）——
    // #t0076：base option 覆盖文档位置（option.base 接线）
     "#t0076",
    // #t0089：空 @base = 保留 option base（相对解析合并且无 ".." 弹出）
     "#t0089",
    // #t0090：相对 @base ".." 弹段（/base/.. → /）
     "#t0090",
    // #t0091：绝对 @base 原样 + 相对叠加触发 RFC 5.2.4 点段消除（期望 baz/ 前无点段）
     "#t0091",
    // #t0118（空 scheme 修正）：":fish" 非绝对 → vocab 拼接（"foo:bar" colon 非
    // 首位仍为绝对原样）——is_valid_absolute_iri 首位冒号排除
     "#t0118",
    // —— should-error 负例验证批（校验落码后转 plain 负例）——
    // #ter26（负）：关键字别名冲突 → colliding keywords
     "#ter26",
    // #ter37（负）：值对象内 @id → invalid value object
     "#ter37",
    // #ter39（负）：@language + 非串 @value → invalid language-tagged value
     "#ter39",
    // #ter40（负）：@type bnode → invalid typed value
     "#ter40",
    // #ter51（负）：值别名键 + 数组值 → invalid value object value
     "#ter51",
    //（#ter30 已在四族批 @language 位迁移，此处不重复）
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
    // #ter48（负·③二轮修正）：@id 位相对 IRI 不可用 → invalid IRI mapping
    // （term 查表按 vocab 位门控 + @id 位绝对/bnode 校验——与②批边界表同源）
     "#ter48",
    // —— ④批 A 组（依赖分组勘定 + 探针实测 74/101 通过；逐例端到端对拍由本 harness 执行）——
    // A 组 = 只依赖已落语义（@context 简单声明 + term 字符串定义 + 值对象 + coercion 形态 A）
    // 27 例挂账留 deferred：mismatch ×10 / unexpected-error ×9 / should-error ×7（详见 todo §J2 ④批）
    // ⑤批落码复测回桶（2026-09-26）：tem01/ten05/ter10/ter21/ter22/ter35/ter53/
    // tes01/tes02 九例原靠 td 对象 stub 拒绝"拒绝即过"——⑤真码落地后露真容，
    // 其无效点（td 的 @container/@language/@prefix/@nest/@context 键验证）在
    // 批边界外，回 deferred 挂「⑤后半·td 其余键验证批」（详见 todo §J2 ⑤批）
     "#t0003", "#t0075", "#t0092", "#tc029", "#tc030", "#tc032", "#tc033", "#tdi08",
    "#tec02", "#ten01", "#ten02", "#ten03", "#ten04", "#tep02", "#tep03", "#ter04",
    "#ter05", "#ter06", "#ter07", "#ter12", "#ter13", "#ter23", "#ter24", "#ter25",
    "#ter27", "#ter29", "#ter30", "#ter31", "#ter33", "#ter34", "#ter36", "#ter41",
    "#ter42", "#ter55", "#ter56", "#tin07", "#tin08", "#tin09", "#tm020", "#tpi05",
    "#tpr01", "#tpr03", "#tpr04", "#tpr05", "#tpr08", "#tpr09", "#tpr11", "#tpr12",
    "#tpr17", "#tpr18", "#tpr20", "#tpr21", "#tpr26", "#tpr28", "#tpr31", "#tpr32",
    "#tpr42", "#tso01", "#tso02", "#tso03", "#tso07", "#tso10", "#tso12", "#tso13",
    "#ttn01",
    // —— ⑤批 A 组（td 对象形态 + coercion——2026-09-26；批边界/判据/对拍点见 todo §J2 ⑤批）——
    // #t0007：形态 D（td @type 显式 datatype）+ 两遍 context 处理（后置 prefix
    // 定义——简单 term——对对象形态 td 可用）
     "#t0007",
    // #t0011：形态 B（td @type "@id"）+ @id-less td（term 名自身 vocab 展开）
     "#t0011",
    // #t0033：形态 D × @vocab
     "#t0033",
    // #t0053/t0054/t0055/t0058：形态 C（td @type "@vocab"——绝对/term/vocab 相对/compact 值）
     "#t0053", "#t0054", "#t0055", "#t0058",
    // #t0069：compact IRI 形 term 名 + type mapping（term 查表先于 compact 分解）
     "#t0069",
    // #t0071：td @id 自映射排除（compact 形 term 名重定义；简单臂同规则泛化）
     "#t0071",
    // #t0088：coercion 负向钉——number/bool 不转 @id；属性位 bool 保留为 @value
    // 字面量（本批修正：原误丢弃）
     "#t0088",
    // #t0117：冒号起始 term + type mapping
     "#t0117",
    //（⑤批挂账 4 例：t0026 = @graph B 组叠加件；t0050/t0056/t0057 = 期望含相对
    // 引用 base 解析，挂「vocab 位 base 门控批」——见 options_for 注记）
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
  assert_eq(deferred.length(), 285)
  assert_eq(plain.length(), 100)
  // 解析覆盖闭合：每个有 input 的条目都走了解析通道
  assert_eq(parsed_ok + parse_err, 385)
  // 首例钉：#t0001 已迁 plain（manifest 顺序首条；J2 首件验收 = 此例端到端绿）
  assert_true(plain.contains("#t0001"))
}
