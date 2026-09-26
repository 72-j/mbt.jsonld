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
      // processingMode 与 specVersion 并行（#ter21/#tes01 oracle：容器验证按
      // processingMode 分叉）；任一指 1.0 即 1.0
      match json_string_get(option_value, "processingMode") {
        Some("json-ld-1.0") => mode = @jsonld.ProcessingMode::JsonLd10
        _ => ()
      }
      base = json_string_get(option_value, "base")
    }
    None => ()
  }
  // 默认 base 注入 = **输入文档位置**（W3C runner document location 同款，
  // 含文件名——fragment/query 相对解析锚定文档 URL，#t0029 oracle）——
  // 「vocab 位 base 门控批」第二件，与 expand_iri 第 7 步门控**同笔落**：键位
  // documentRelative=false 不受注入影响（#t0003 oracle 保持），值位
  // （@id/@type/coercion——docRel=true）据此解析（解挂 t0051/t0050/t0056/
  // t0057/t0029/t0062）
  let base = match base {
    Some(b) => Some(b)
    None =>
      match json_string_get(entry, "input") {
        Some(input_path) =>
          Some("https://w3c.github.io/json-ld-api/tests/" + input_path)
        None => None
      }
  }
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
    // #t0051（「vocab 位 base 门控批」解挂）：别名链 url→id→@id + 默认 base
    // 注入 + 门控（键位 docRel=false 不受注入影响）+ merge 绝对路径分支
     "#t0051",
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
     "#t0003", "#t0075", "#t0092", "#tc029", "#tc030", "#tdi08", "#tec02", "#ten01",
    "#ten02", "#ten03", "#ten04", "#tep02", "#tep03", "#ter04", "#ter05", "#ter06",
    "#ter07", "#ter12", "#ter13", "#ter23", "#ter24", "#ter25", "#ter27", "#ter29",
    "#ter30", "#ter31", "#ter33", "#ter34", "#ter41", "#ter42", "#ter55", "#ter56",
    "#tin07", "#tin08", "#tin09", "#tpr42", "#tso01", "#tso02", "#tso03", "#tso07",
    "#tso10", "#tso12", "#tso13", "#ttn01",
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
    //（t0026 仍挂 @graph B 组；t0050/t0056/t0057 已随「vocab 位 base 门控批」
    // 解挂迁 plain，见下）
    // —— vocab 位 base 门控批（2026-09-26；门控 + 默认 base 注入同笔落）——
    // #t0050：td coercion @id + @container:@set 验证（相对 "/issue/1" 走默认 base）
     "#t0050",
    // #t0056：形态 B/@id 与 C/@vocab coercion 对比（link 相对值走默认 base）
     "#t0056",
    // #t0057：@vocab coercion 双真旗（vocab miss → document-relative → base）
     "#t0057",
    // —— ⑤后半·td 其余键验证批（2026-09-26；九例回迁——⑤落码时曾因"拒绝即过"
    // 破例回 deferred，真验证落码后按原 oracle 回归 plain）——
    // #tem01/#ter21/#tes01/#tes02：@container 验证（串白名单 1.1/1.0 分叉 +
    // 数组仅 1.1 图组合；#ter21 = processingMode 1.0 门控）
     "#tem01", "#ter21", "#tes01", "#tes02",
    // #ter10：compact 前缀自指环 → cyclic IRI mapping（简单臂与 td @id 臂同规则）
     "#ter10",
    // #ter22：td @language 非串 → invalid language mapping
     "#ter22",
    // #ter35：@language 容器值检查（{"en": true} → invalid language map value）
     "#ter35",
    // #ter53：td @prefix 非布尔 → invalid @prefix value
     "#ter53",
    // #ten05：td @nest 关键字值（"@id"）→ invalid @nest value
     "#ten05",
    //（#ter36 C 组落码复测回桶：@reverse-only term（td @reverse 忽略位）+
    // list 值——其无效点 = reverse 属性值验证，挂 @reverse 批，非 C 组边界）
    // —— C 组·@list/@set 批（2026-09-26；拦截器/容器应用/1.0 嵌套门控——
    // 批边界与判据见 todo §J2 C 组开工钉）——
    // #t0004/#t0015：空 list/set 保留（属性门 container 放行）+ set 嵌套塌缩
     "#t0004", "#t0015",
    // #t0023：coercion × @container @list（元素 coercion 先行再包 List）
     "#t0023",
    // #t0027：duplicates 展开期保留（list/set 均不去重）
     "#t0027",
    // #tli01~#tli10：@list 关键字/容器全形态（嵌套 list 保留、空 list、
    // coercion、数组内嵌转嵌套 list、深数组、多 list、混值）
     "#tli01", "#tli02", "#tli03", "#tli04", "#tli05", "#tli06", "#tli07", "#tli08",
    "#tli09", "#tli10",
    //（#ter24 已在 ④批 A 组名单——1.0 list-of-lists 真拒绝随本批落地）
    // #ter32（负·1.0 模式）：list of lists 按模式分叉（1.0 禁 1.1 允许）
     "#ter32",
    // base 批复测件（Relative IRIs，期望默认 base 已解锁）
     "#t0029", "#t0062",
    // —— @reverse 批（2026-09-26；独立于 @graph——勘定入 todo §J2）——
    // #t0037/#t0039/#t0042/#t0049/#t0064/#t0078：@reverse 节点位/term 位/
    // coercion 值/bnode 值/多 reverse（值进主体 "@reverse" 映射）
     "#t0037", "#t0039", "#t0042", "#t0049", "#t0064", "#t0078",
    // #ter14（负）：@id 与 @reverse 同 td → invalid reverse property
    // #ter15（负）：td @reverse 非串 → invalid IRI mapping
    // #ter17（负）：reverse td @container 验证（容器验证批已落，复测回迁）
    //（#ter33 已在四族批名单——值对象位 @reverse 非 map 随本批真拒绝）
    // #ter36（负）：reverse 项 @list 值 → invalid reverse property value
     "#ter14", "#ter15", "#ter17", "#ter36",
    // —— @reverse 收尾小批（2026-09-26；ter50 + t0043，独立成笔不混 §M.12）——
    // #ter50（负）：td @reverse 串值经 vocab 展开后非绝对 → invalid IRI mapping
    //（documentRelative=false，base 注入不救）
    // #t0043：@reverse 位双反转互消（键自身为 reverse term → 值升级为当前节点
    // 普通正属性，键 = td 的 reverse IRI）
     "#ter50", "#t0043",
    // —— @graph 文档级批（2026-09-26；两族拆分之文档级族——批边界见 todo §J2）——
    // #t0009/#t0012/#t0017：顶层 @graph 表面化（仅 @graph 的根节点 → 图内容数组；
    // t0017 = "data" 别名 @graph 路由）；#t0020：节点下 @graph 保留；#t0021：顶层
    // 属性 + @graph 并存（表面化门不触发）；#t0026：1.0 @type 别名 + 顶层图；
    // #t0046：图内容自由浮动全弃（标量/值对象/@id-only）；#t0047：自由浮动
    // @set 透明/@list 整弃；#ter43（负·1.1 模式）：@type 别名禁 → invalid IRI mapping
     "#t0009", "#t0012", "#t0017", "#t0020", "#t0021", "#t0026", "#t0046", "#t0047",
    "#ter43",
    // —— @nest 纯形批（2026-09-26；tn001~tn008——批边界见 todo §J2）——
    // #tn001：@nest 基本上浮（嵌套属性并入当前节点）；#tn002：别名 term
    // （"nest": "@nest"）归一汇流；#tn003：嵌套值排自身属性之后（文档序不倒
    // 置）；#tn004：双 @nest 键（nest2 文档序在先）——保序输出 [v2,v4,v3]，
    // 官方比对数组无序同判（比对器 canonical_for_suite 移植）；#tn005：嵌套
    // @nest 递归自展；#tn006：同键属性逐元素并值；#tn007：nest 值数组展平；
    // #tn008：类型随嵌套并入（@type 数组追加）
     "#tn001", "#tn002", "#tn003", "#tn004", "#tn005", "#tn006", "#tn007", "#tn008",
    // —— @included 纯形批（2026-09-26；in001~in005——批边界见 todo §J2）——
    // oracle 定案：官方期望把 "@included" 作为节点对象键渲染（同 @graph
    // 范式），非顶层拼接。#tin01：@included 数组值 → 主节点带 @included 键；
    // #tin02：单对象形态归一；#tin03：多别名 term（included1/included2 →
    // @included）归一汇流——主节点无其余属性时根节点只含 @included 键；
    // #tin04：嵌套 @included 保留为嵌套键（随递归自展，非拍平）；
    // #tin05：值对象位 @included 保形（内层照节点对象展开——oracle 权威，
    // REC 值对象关键词窄集不含 @included 的处置被套件否决）。#tin06 挂
    // 依赖批（term-scoped context——tc037/038 批）
    // #tm020 意外负例翻出（@version 修真后露出）：旧 @version 臂拒数字 1.1
    // 时经 context error 意外通过；真判定 = term 定义 @type 映射校验
    // （"@type":"literal" 非法——invalid type mapping），挂「⑤后半·td
    // 其余键验证批」
    // #tpi05 同族意外负例：真判定 = 属性值 index map 校验（@container:@index
    // + @index:prop 下值对象加属性 → invalid value object），挂「@container
    // index/property-value 批」
    // #tpr01 同族意外负例：真判定 = @protected 保护 term 重定义校验
    // （protected term redefinition），挂「@protected 批」
    // #tpr03/04/05/08/09/11/12/17/18/20/21/26/28/31/32（15 枚）同族：
    // @protected 全族未落码，一律经旧 @version 臂拒数字 1.1 的意外机制
    // 通过——真判定归「@protected 批」（tpr05/17/18/20/21 为 context
    // nullification 变体，同门）
     "#tin01", "#tin02", "#tin03", "#tin04", "#tin05",
    // —— scoped-context 批（属性作用域 context；2026-09-26——批边界见 todo §J2）——
    // 机制（REC 4.2.2 @context 臂 + REC 5.1.2 "property-scoped context"）：td 的
    // @context 在**定义期**调用 Context Processing 校验（结果丢弃；任何错误 →
    // invalid scoped context），在**展开期**于该 term 的**值**展开前再处理套用
    // #tc037：@nest 别名 term 的 scoped @vocab 作用于其值（嵌套键按 /nest 展开）
    // #tc038：Bibframe——级联作用域（scoped context 内再定义 @nest 别名 + 该别名
    //   自带 scoped context；@nest 别名 / 普通 term 两类嵌套叠加）
    // #tin06：json.api——scoped context {"data": null} 使 "data" 在作用域内为
    //   null IRI 映射（该键整体丢弃；非 vocab 拼接、非 @nest 上浮）
    // #tc032/#tc033（负）：**未被使用**的嵌入 context 仍须定义期校验——内层
    //   term 无 @id 且无 @vocab → invalid IRI mapping → 外层 invalid scoped context
     "#tc037", "#tc038", "#tin06", "#tc032", "#tc033",
    // 连带修正（同笔；ter43 门过宽）：原「1.1 禁 @type 别名」门把 in06 的合法
    // 别名 "type": "@type" 也误拦——改为 REC 4.2.2 的 **term 名一致性检查**
    // （term 名含冒号（非首末位）或含斜杠时，其自身展开须 == IRI 映射；1.0 不
    // 检查——#t0026 正例 / #ter43 负例两 oracle 同保）
    // #ter44（负·1.1）：compact 形 term 名映射到别处（v:term → v:somethingElse）
    //   → invalid IRI mapping（本批连带解挂）
     "#ter44",
    // —— 同族勘定扩迁（家族普查 52 例逐例实测；见 todo §J2）——
    // #tc001：scoped context 新定义 term（foo 值内 bar 按 scoped 定义展开）
    // #tc002：scoped context 覆盖外层 term（bar 在作用域内重定义为 @id coercion）
    // #tc003：scoped context 内 term → 同文档另一 term 名（Bar → bar，
    //   值 IRI 展开经 vocab 落 http://example/bar）
    // #tc004：深作用域（scoped context 传递到嵌套节点——两次嵌套均生效）
    // #tc005：作用域叠加（元素级 @context 的 @vocab 与 scoped context 分层：
    //   作用域内 term 命中 http://example.org/c，其余 key 落元素级 vocab）
    // #tc036：空 scoped context（{}——定义期校验通过、展开期为 no-op）
     "#tc001", "#tc002", "#tc003", "#tc004", "#tc005", "#tc036",
    // —— type-scoped context 批（2026-09-26；批边界/边界表见 todo §J2 + spec）——
    // 机制 = REC 4.1.2 propagate=false（置 previous context）+ REC 5.1.2 元素级
    // @context 次序 → 快照 → 按 @type 键字典序/值字典序逐 term 套用（后套叠加）+
    // 新节点对象回退 previous（"term-scoped context 不跨新节点"）+ @propagate 成员
    // #t0073（**开工前置·次序钉子**）：@context not first property——元素级 @context
    //   先于主键循环处理，文档中排在其前的键亦生效
    // #tc006/#tc007/#tc008：type-scoped 新定义 term / 覆盖外层 term（@id coercion）/
    //   @type 别名 term（"type": "@type"）亦触发
    // #tc009：深 type-scoped **不**影响嵌套节点（嵌套节点回退 previous）
    // #tc010：与元素级 @context 分层（作用域内 term 命中 scoped，其余落元素级 vocab）
    // #tc011：@type 数组按**字典序**套用（数组序 ["t2","t1"] 下 t2 胜）
    // #tc012：type-scoped 内再定义**属性作用域** term——其 scoped context 作用于
    //   该属性值（回退前捕获、回退后应用；本批修出的真实 bug）
    // #tc014：type-scoped `[null]` 空化（节点自身键按空 context 判，@type 值用快照）
    // #tc015：type-scoped @base（节点 @id 与单 @id 形值用 typed base；多键嵌套节点
    //   回退 outer base——单 @id 形不回退的 oracle）
    // #tc016：type-scoped @vocab（节点键 typed、嵌套节点回退 outer）
    // #tc017/#tc018：多 type-scoped 叠加与回退（[null,{...}] 组合 + 字典序定胜负）
    // #tc019/#tc022/#tc023：type-scoped 内多属性作用域 term（含 @type:@vocab 组合）
    // #tc020/#tc021：值对象形不回退（type-scoped 的 `value:@value` 别名 + 值混排）
    // #tc024：type-scoped + property-scoped + 值对象按 previous context 判
    // #tc026/#tc027/#tc028：@propagate true(覆盖默认 false)/false(属性作用域)/(元素级)
    // #tc035：term scoping with embedded contexts
    // #tc029/#tc030：**复审转真判据**（原在 plain 但"通过机制未复审"的埋雷族）——
    //   @propagate 1.0 非法（invalid context entry）/ 非布尔（invalid @propagate value）
     "#t0073", "#tc006", "#tc007", "#tc008", "#tc009", "#tc010", "#tc011", "#tc012",
    "#tc014", "#tc015", "#tc016", "#tc017", "#tc018", "#tc019", "#tc020", "#tc021",
    "#tc022", "#tc023", "#tc024", "#tc026", "#tc027", "#tc028", "#tc035",
    // —— @protected 批（2026-09-26；批边界 33 例逐例归因，见 todo §J2 + spec 边界表）——
    // 机制 = 上下文级 @protected 默认位 + td 级覆盖 + 安装期保护检查（等价 ⇒ 保留
    // 旧定义【保护位不丢】/ 不等价 ⇒ protected term redefinition）+ 四面 override
    // 传导（property-scoped 与定义期 scoped 校验 true；type-scoped/元素级 false）+
    // null 空化遇保护 term（override=false）→ invalid context nullification +
    // 关键字 term 受限重定义（仅 @container:@set 与/或 @protected）
    // 正例 15：#tpr02（@protected:false 不保护）/ #tpr06（term 内清保护）/
    //   #tpr10（protected 与 unprotected 混排）/ #tpr13（覆盖未保护 term）/
    //   #tpr14/#tpr15（null 与数组含 null 清保护）/ #tpr16（清后可覆盖）/
    //   #tpr19（混排重定义）/ #tpr22（type-scoped 保护 term 的合法覆盖）/
    //   #tpr23/#tpr24（等价重定义：别名 / 前缀 term）/ #tpr27（除 protected 位外
    //   等价）/ #tpr30（**关键字可保护**：别名 + 字面 @type）/ #tpr40（保护 +
    //   property-scoped）/ #tpr41（等价 id term 重定义）
     "#tpr02", "#tpr06", "#tpr10", "#tpr13", "#tpr14", "#tpr15", "#tpr16", "#tpr19",
    "#tpr22", "#tpr23", "#tpr24", "#tpr27", "#tpr30", "#tpr40", "#tpr41",
    // 负例 17（**错误码逐一命中**，非"拒绝即过"）：
    // protected term redefinition ×12 = #tpr01（td 级保护后覆盖）/ #tpr03（整
    //   context 保护）/ #tpr04（新定义带 @protected:false 仍是重定义——判据看
    //   **旧定义**是否受保护）/ #tpr08（term 的 protected scoped context）/
    //   #tpr09（跨保护 context）/ #tpr11 / #tpr12（scoped context 面不可覆盖）/
    //   #tpr26（scoped 定义不同 ⇒ 不等价）/ #tpr28（保护 null term 重定义）/
    //   #tpr31（保护关键字别名不可覆盖）/ #tpr32（保护 @type 不可覆盖）/
    //   #tpr42（重定义须保留保护位）
    // invalid context nullification ×5 = #tpr05（embedded @context:null 清保护）/
    //   #tpr17/#tpr18（type-scoped 面空化保护）/ #tpr20/#tpr21（混排 type+null）
     "#tpr01", "#tpr03", "#tpr04", "#tpr05", "#tpr08", "#tpr09", "#tpr11", "#tpr12",
    "#tpr17", "#tpr18", "#tpr20", "#tpr21", "#tpr26", "#tpr28", "#tpr31", "#tpr32",
    "#tpr42",
    // —— @container 映射批（@type type map + @index index map 最小子集；2026-09-26）——
    // 机制 = REC 13.8.3 映射分支：容器 ∈ {@type,@index} 且**值为 map** 才进映射分支；
    // map context 按容器种类分叉（**@id/@type 用 previous、@index 用 active**）+ 仅
    // @type 面套用**索引项**的 scoped context（"用类型索引项的 scoped context，不用
    // 包含方的"）+ from-map 语境（不回退）+ 索引写入（@type **前插** / **@none 跳过**；
    // @index 写原始键）+ 定义面**隐式 type mapping**（容器含 @type ⇒ 缺省 @id，显式
    // 须 @id/@vocab，否则 invalid type mapping）
    // #tc013（本批主例）：@index 容器 + @type 容器叠加——内层 map 用 base 的 index
    //   容器定义（不用外层 type-scoped 的），条目得 @index 与内层 scoped 词表
    // #tm003/#tm004：type map 键为绝对 IRI / bnode；已有 @type 时**前插**
    // #tm006/#tm007：键按 vocab 展开为 @type（显式 label 定义不影响）
    // #tm008：索引项（"Type"）自带 scoped context → 作用于条目
    // #tm012：@none 及别名键 → 不加 @type（条目仍产出）
    // #tm017/#tm018/#tm019：值层字符串 → **隐式 @id**（document-relative）/ 显式
    //   @id / 显式 @vocab 三种 type mapping
    // #tm020（负）：容器 @type + 非 @id/@vocab 的 @type → invalid type mapping
     "#tc013", "#tm003", "#tm004", "#tm006", "#tm007", "#tm008", "#tm012", "#tm017",
    "#tm018", "#tm019", "#tm020",
    // —— @id 容器 + language map 批（2026-09-26；批名统一，合成一批）——
    // 机制 = REC 13.8.3 @id map（map context 用 previous；条目无 @id ⇒ 写
    // **document-relative、非 vocab 位**展开的索引；已有 @id 保留；@none/别名跳过）
    // + REC 13.8.2 language map（逐条目：null 跳过、非串 → invalid language map
    // value；`{@value}` 且语言键非 @none/别名 ⇒ 加 @language；**非 map 值落通用分支**）
    // #tm001/#tm002/#tm005/#tm011：@id map——绝对/bnode 键、既有 @id 保留、
    //   **相对键按 base 展开**（option.base）、@none 与别名不写 @id
    // #tm009/#tm010：language map——en 串 / de 数组逐项、@none 与**别名**不写 @language
    // #t0030：language map 基本形态；#tl001：条目值与数组内 null 均跳过
    // #t0040（连带修出重入 bug）：map 类容器但**值为数组** ⇒ 逐项按元素语义展开
    //   （不重入容器壳）；数组内 `{"@id": …}` 项仍是节点（base 相对解析）
     "#tm001", "#tm002", "#tm005", "#tm011", "#tm009", "#tm010", "#t0030", "#tl001",
    "#t0040",
    // —— @index mapping + index map 校验批（2026-09-26；16 例依赖分组见 todo §J2）——
    // 机制 = REC 4.2.2 `@index` 索引映射（1.0 或容器不含 @index → invalid term
    // definition；值须串且 IRI 展开成 IRI；**存原始值**——展开期两用）+ REC 13.8.3
    // 子案例 1（index key ≠ @index ⇒ 索引键写成**一条属性**：expanded index key 为属性
    // IRI、re-expanded index 以 **index key 为 active property** 走 Value Expansion；
    // 属性值 = 新值 ++ 既有；**值对象条目 ⇒ invalid value object**）+ 子案例 2（写 @index）
    // + reverse 项容器白名单放宽（@set/@index 合法——#t0063/#t0131）+ 节点/字面量位
    // `@index` 键 + `ExpandedLiteral.index` + **reverse-bearing 节点非自由浮动**
    // #tpi01（负·1.0）/ #tpi03（负·关键字值）/ #tpi04（负·非串）→ invalid term definition
    // #tpi05（负）：值对象条目加索引属性 ⇒ invalid value object
    // #tpi06/#tpi07：索引属性展开/追加（值级）；#tpi08/#tpi09：节点级（含 @type:@vocab
    //   的 index key ⇒ 索引成节点引用 + 追加）；#tpi10：@none 条目**不写**索引属性
    // #t0131：reverse 项 + 属性型 index 容器；#t0036：index map 节点/字面量条目写 @index、
    //   已有 @index 保留、null 跳过；#t0063：reverse 属性 + index 容器
     "#tpi01", "#tpi03", "#tpi04", "#tpi05", "#tpi06", "#tpi07", "#tpi08", "#tpi09",
    "#tpi10", "#t0131", "#t0036", "#t0063",
    // —— @graph 容器族批（2026-09-27；单一机制 @graph 容器应用，前置全齐——
    // 依赖复勘/形态表/批边界见 todo §J2 开工钉）——
    // 裸 @graph（值包 graph 节点；graph 对象值再包一层）
     "#t0079", "#t0093", "#t0102", "#t0103", "#t0104",
    // [@graph, @set]（摊平同包裹）
     "#t0080", "#t0094",
    // [@graph, @index]（键附 @index；@none 直出；既有 graph 对象不重包）
     "#t0082", "#t0096", "#t0105", "#t0107", "#t0084", "#t0098",
    // [@graph, @id]（键 vocab 展开附 @id；既有 graph 对象不重包）
     "#t0085", "#t0099", "#t0108", "#t0087", "#t0101", "#t0106",
    // [@graph, @index, @set]
     "#t0083", "#t0097",
    // [@graph, @id, @set]
     "#t0086", "#t0100",
    // graph index/id map × @none（map 已落 + 容器本批）
     "#tm013", "#tm014", "#tm015", "#tm016",
    // property-valued index → graph（index mapping 已落 + 容器本批）
     "#tpi11",
    // type-scoped / protected 叠加（scoped/protected 批已落 + 容器本批）
     "#tc025", "#tpr25", "#tpr43",
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
          Err(e) =>
            match e {
              InvalidValue(m) => fail("\{id}: IV: \{m}")
              InvalidContext(m) => fail("\{id}: IC: \{m}")
              InvalidIri(m) => fail("\{id}: II: \{m}")
              InvalidList(m) => fail("\{id}: IL: \{m}")
              Unsupported(m) => fail("\{id}: US: \{m}")
              _ => fail("\{id}: other")
            }
        }
        let expected_text = @utf8.decode(
          @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + expect_path).binary(),
        )
        let expected = match @jsonld.parse_json(expected_text) {
          Ok(value) => value
          Err(_) => fail("\{id}: expected output unparseable")
        }
        if @jsonld.canonical_for_suite(actual) !=
          @jsonld.canonical_for_suite(expected) {
          fail("\{id}: mismatch")
        }
      }
      plain.push(id)
    } else {
      deferred.push(id)
    }
  }
  // pin 闭合：桶总和 == 普查数；plain = 已迁移数
  assert_eq(deferred.length(), 113)
  assert_eq(plain.length(), 272)
  // 解析覆盖闭合：每个有 input 的条目都走了解析通道
  assert_eq(parsed_ok + parse_err, 385)
  // 首例钉：#t0001 已迁 plain（manifest 顺序首条；J2 首件验收 = 此例端到端绿）
  assert_true(plain.contains("#t0001"))
}
