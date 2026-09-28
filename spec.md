# JSON-LD 子项目 · spec.md（规格）

## 1 范围
### 做
- JSON-LD 1.1 的 expansion（展开）
- JSON-LD 1.1 的 toRDF（转 RDF 四元组）
- context 处理（作用域、term definition、@id/@type/@reverse/@nest）
- IRI 展开（相对/绝对/compact/vocab 相对/blank node）
- datatype coercion
- @value/@list/@set/@graph/@included/@reverse/@nest 的语义

### 暂不做（看擂台是否考）
- framing
- canonicalization（URDNA2015/RDFC-1.0）
- compaction（除非擂台考）

## 2 不做什么（红线级）
- 不建 AST 供 FSM 消费（JSON-LD 不走 FSM）
- 不做词法层 gen（JSON 解析用现成库）
- 不做搜索/剪枝（JSON-LD 是确定性算法）
- 不复用 TrigActions 的方法集（新 trait JsonLdActions）

## 3 输入/输出
### gen 输入
- jsonld_gen.toml（三份表：步骤表/分派表/IRI 规则表）

### gen 输出
- 骨架代码：步骤调度框架 + 关键字分派框架 + IRI 规则框架

### 运行时输入
- JSON-LD 文档（JSON 文本）→ MoonBit 现成解析器 → JSON 树

### 运行时输出
- 展开后的节点对象图（expansion）
- RDF 四元组集合（toRDF）

## 4 表结构（`jsonld_gen.toml`；字段形制承 src/fsm TOML 2.0，schema 独立）
口径绑定器 = `src/fsm/jsonld_toml_gen.mbt`（`parse_jsonld_gen` / `validate_jsonld_gen` /
`emit_jsonld_gen`；统一入口落 src/fsm，低耦合只依赖通用 `hnlyxiaobing/toml` 库，不碰 FsmIR）。
词表封闭、引用完整、步骤图无环（递归红线钉子）、规则顺序连续、handler_hook 须为
`Trait::method` 形——均由 validate 把关（drift = 红）。
### [[steps]] 步骤表
- id, name, phase（expansion/toRDF）, order, next（单值；缺省 = 本阶段终点）,
  dispatch（可选：形态 → 步骤 映射，骨架生成 match 分派）, handler_hook（手写 trait 方法；
  无手写的行不得带此键）

### [[keyword_dispatch]] 关键字分派表
- keyword, condition（可枚举形态判断词表）, action, result（展开形态词表）,
  args（可选，封闭旗标）, handler_hook（可选）

### [[iri_rules]] IRI 规则表
- order（求值顺序）, kind（keyword/absolute/bnode/compact/vocab/relative/term）,
  condition（可枚举形态判断词表）, action, handler_hook（可选）

### IRI 解析实现边界（2026-09-26 定案；三者皆 RFC 3986 实现边界）
- **merge_base_reference（5.2.3 merge，authority-only）**：相对引用 = base 截最后
  "/"（含）+ 引用；base 仅到 authority（无路径 "/"）→ 补根 "/"（#t0129/#t0130
  oracle）。**绝对路径引用（"/" 开头）= authority 保留、path 整体替换**
  （#t0051 oracle：/issue/1 → https://w3c.github.io/issue/1；authority_root
  助手截 scheme://authority，无 authority 形态落回相对合并）。
- **resolve_base_value（5.2.4 点段消除，窄化）**：".." 弹前段并补根段、"." 丢弃，
  **只作用于合并结果**——绝对 base 置位时原样保留（/./ 可暂存；#t0091 oracle：
  base1 绝对原样、base2 合并后 /./ 消除）；value 绝对 → 原样返回不做归一
  （#t0092 oracle：raw 拼接即预期，完整 5.2.4 挂后续）。
- **is_valid_absolute_iri（scheme 文法）**：scheme 冒号须在非首位（":fish" 空方案
  非绝对 → 走 vocab 拼接，#t0118 oracle）+ **scheme 首字符须 ALPHA**（RFC 3986
  `scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`，JSON-LD 规范 IRI 正则
  同款）——"_:dt" 的 scheme "_" 非法 ⇒ 非绝对（#ter40 oracle：bnode 不得作
  datatype）。波及面：expand_iri 第 5 步绝对判定 / 值对象 @type datatype 合法性 /
  属性门（bnode 键在此**显式放行**——规范允许 blank node predicate）。
- **vocab 位 base 门控（已落地定案，2026-09-26）**：expand_iri
  `document_relative` 旗启用——第 7 步 base merge 仅 document-relative 位执行。
  **旗位语义表（11 调用点实证）**：键归一位 = 唯一 false（vocab 位键不落 base，
  #t0003 oracle：未映射 term 丢弃）；@id/@type 节点位 + coercion 值位 = true
  （#t0051/#t0050/#t0056/#t0057 oracle）；**td 定义值（简单臂/td @id/td @type/
  @id-less 回退）= false**（#ter23 oracle：term 定义值纯 vocab 位，相对 @type
  不得被 base 补成绝对）。harness 默认 base 注入（document location 约定，
  option.base 优先）与门控**同笔落地**。

### 同形异判实例（J2 语义分叉地图；2026-09-26 立节，持续收录）
「输入相似/相同而判定不同」的 oracle 对——**禁止单一规则覆盖整族**，逐对勘定
分叉轴后再落码；新增分叉对入本表：
| 实例对 | 分叉维度 | 分叉轴 | 判定差异 |
| #t0003 vs #t0004 | 形态分叉 | 值形态（null vs 空数组字面值） | null 值属性整体丢弃；空数组字面值属性保留（"set1": []——同文档两组键并存） |
| #tli01 vs #ter24/#ter32 | specVersion 分叉 | processingMode/specVersion | 同输入（@list 嵌套）：1.1 允许保留 / 1.0 list of lists 禁止 |
| **@vocab 分叉族**（三对归组） | | |
| #t0092 vs #t0115/#t0116 | specVersion 分叉 | processingMode | @vocab 相对/空串：1.1 base raw 拼接有效 / 1.0 invalid vocab mapping（校验先于 base 解析） |
| #t0110 vs #t0111 | @vocab 相对值两形态（**前导字符分叉**） | "/relative"（前导 /）= authority 路径替换 → http://example.com/relative；"./rel2#"（前导 .）= **拼接现有 vocab**（prev + 值）——两者均不消点段 |
| #ter23 vs #t0029 | 位置分叉 | 展开位置（td 定义值 vs 文档值位） | td @type 相对值不落 base（invalid type mapping）；文档值位相对 IRI 落 base 解析（含 fragment/query/scheme 相对） |
| #t0026 vs #ter43 | specVersion 分叉 | td 定义 **term 名一致性检查**（非"@type 别名"黑名单） | 同输入（含顶层 @graph）：term 名 = rdf:type 长名，其自身展开 ≠ IRI 映射（@type）→ 1.1 invalid IRI mapping / 1.0 不检查（合法）。同类 1.1 负例 #ter44（compact 形 term 名映射他处） |
| #tc006/#tc016 vs #tc014/#tc018 | 位置分叉（**同一节点内**） | 展开位置：节点键（套用后的 context）vs **@type 值自身（快照）** | type-scoped context 空化/换 vocab 只影响节点键；**@type 值仍按快照展开**（#tc014：`[null]` 下 @type 仍得 http://example/Type；#tc018 同理） |
| #pr23/#pr24/#pr27/#pr41 vs #pr26/#pr28/#pr42 | 定义面分叉（**保护穿透**） | 新定义与旧定义是否**等价（除 protected 位外）** | 等价 ⇒ 允许重定义**且保留旧定义**（保护位不丢，#pr42）；不等价 ⇒ `protected term redefinition`（判据看**旧定义**是否受保护——#pr04：新定义带 `@protected:false` 也不豁免） |
| #pr06/#pr14/#pr16 vs #pr17/#pr18/#pr20/#pr21 | 调用面分叉（**同一空化形态**） | override protected 的**传导面** | property-scoped 应用与定义期 scoped 校验传 true ⇒ 空化保护 term 允许；**type-scoped 应用不传（false）**⇒ 同一 `null`/`[null]` 形态报 `invalid context nullification` |
| #tec02 vs #pr30 | 形态分叉（**关键字 term 的 td 值**） | `{"@container":"@set"}`/`{"@protected":…}` 的有无 | "only either **or both of** following entries" ⇒ 须**至少一条**：`{"@type": {}}` → `keyword redefinition`；`{"@container":"@set","@protected":true}` → 合法（关键字可保护） |
| #t0003 vs #tjs18/#tjs22 | **@json term 豁免**（形态+成员分叉） | `@value: null`——普通属性整体丢弃；**@json term** 的 null = JSON null 字面量保留（第三组同形异判） |
| #ter01 vs #t0005/#tpr34~#tpr39 | **@ 前缀 ≠ 关键字**分叉 | "@iri": "@id"（keyword 形态**非真关键字**）定义**忽略不报错**、节点键随之丢弃；"@type": "@id"（**真关键字**映射异关键字）→ keyword redefinition。同族判据：@ 前缀 + 非关键字形态的键 → 忽略不产出属性（#t0119/#tpr34/#tpr36） |
| **@value:null 分叉族**（三对归组；2026-09-28 并入 #t0014 辖域行） | | | |
| #t0019 vs #t0004 | 值形态（**@value:null 值对象** vs 空数组字面值） | @value:null 值对象 ⇒ 属性**整体丢弃**（预扫描）；空数组字面值属性保留（"set3": []）——同文档两形态并存（t0019/t0004 oracle） |
| #t0008 vs #t0022 系 | 值对象成员完备性 | 仅 @language/@direction 无 @value ⇒ 值对象**丢弃**（language-only 不产出）；有 @value ⇒ 正常展开 |
| #tjs18/#tjs22 vs #t0019 | **@json term 豁免** | @type:@json 值对象的 null = JSON null 字面量**保留**（预扫描豁免）；无 @json 语义的 null 值对象丢弃 |
| #tc013 vs #tm003/#tm006 | 容器种类分叉（**map context 的来源**） | 容器 ∈ {@type}（用 previous）vs {@index}（用 active） | @id/@type 容器的 map context = active 的 **previous**（存在即用）；@index 容器 = **active**——#tc013 因此让内层 map 用 base 的 index 容器定义、而非外层 type-scoped 的 |
| #tm003/#tm004 vs #tm012 | 键形态分叉（**@none 与索引写入**） | 索引键是否展开为 `@none` | 普通键 ⇒ **前插** @type（已有 @type 时前插，非替换）；`@none` 及其别名 ⇒ **不写索引**（条目仍产出） |
| #tm017/#tm018/#tm019 vs #tm020 | **定义面分叉**（container @type × type mapping） | 显式 `@type` 是否 ∈ {@id,@vocab} | 容器含 `@type`：未声明 ⇒ **隐式 @id**（#tm017）；显式 `@id`（#tm018）/`@vocab`（#tm019）合法；其它值（如 `"literal"` 经 vocab 展开成 IRI）⇒ **invalid type mapping**（#tm020 负） |
| #tm003/#tm006 vs #tm001/#tm005 | 容器种类分叉（**索引键的展开旗位**） | 容器 ∈ {@type} vs {@id} | **@type map 索引键 = 键位旗**（`vocab=true` / `document_relative=false`；#tm006 "Foo" → http://example/Foo）；**@id map 索引键 = @id 值位旗**（`vocab=false` / `document_relative=true`，REC 明文"using true for document relative and false for vocab"；#tm005 相对键 "foo" 经 base → http://example.org/foo；#tm001 绝对/bnode 原样）。**对照**：`@id` 值位（节点身份）与 `@type` 值位旗位见 §4 旗位语义表——@id map 索引键复用的正是**@id 值位**那一行 |
| #tl001 vs #ter35 | 形态分叉（**language map 条目值**） | 条目值 null vs 非串标量 | null ⇒ **跳过**（#tl001，数组内 null 同）；非串（如 `true`）⇒ **invalid language map value**（#ter35 负） |
| #t0036 vs #tpi05 | 形态分叉（**index map 条目为字面量**） | 索引映射**有无**（缺省写 @index / 映射写属性） | 缺省：**值对象条目可写 @index**（#t0036）；有索引映射：值对象条目**不得再带属性** ⇒ **invalid value object**（#tpi05 负） |
| #tpi10 vs #tpi06 | 键形态分叉（**@none 与索引属性**） | 索引（map 键）是否展开为 `@none` | 普通键 ⇒ 索引写成属性；`@none` 及其别名 ⇒ **不写属性**（条目仍产出——#tpi10） |
| #t0040 vs #tm003 | 形态分叉（**值是否 map**） | 容器为 map 类时值形态 | 值为 map ⇒ 走映射分支（#tm003）；值**非 map** ⇒ 落通用分支逐项按元素语义展开——数组内 `{"@id":…}` 项仍是节点（#t0040；重入容器壳会把它误当索引条目，实测即此红） |
| #tso08/#tso11 vs 同 context 同名覆盖 | **@import 替换 vs 并存覆盖**（同名 term 条目） | imported 定义是"被替换不处理"还是"安装后覆盖" | @import = "replacing common entries" ⇒ imported 定义**不参与处理**（不受本 context `@protected` 追溯保护——#tso11 合法覆盖）；同 context 两道定义（非 @import）= 安装后覆盖 ⇒ 前者已按当时保护位生效 |
| #t0122 vs #t0119/#tpr34 | **@ 形同位异判**（`@1*ALPHA` keyword 形非关键字） | 值位 vs 键位 | @id **值**位：REC §5.2 IRI 展开返回 null ⇒ 节点保留、id 位**字面 `{"@id": null}`**（#t0122）；**键**位：忽略不产出属性（#t0119/#tpr34/#tpr36） |
| #t0060 vs #ter48 | **相对 IRI 位置分叉** | term 名位 vs @id 值位 | term 名相对路径（`.` 开头）⇒ context 处理期 invalid IRI mapping（#ter48）；@id **值**位无绝对性校验——base 无时**原样保留相对**（#t0060 `@base:null` 后 "../document-relative" 保相对） |
| #t0014 vs #t0019 | 辖域分叉（**@set 数组元素级**，别名键形态） | null 值对象的挂载层级 | 直挂属性值 ⇒ 属性**整体丢弃**（#t0019 预扫描辖域）；@set（含别名 "set"）数组元素级 ⇒ 属性**保空数组**（预扫描不误伤——#t0014）；副产品：别名键归一先于 set/list 对象形态判定（vs #t0004 裸键同路） |

### term 名一致性检查（REC 4.2.2 @id 臂 "must be consistent"；2026-09-26 修正）
- 判据：term 名含冒号（**非**首位、**非**末位）或含斜杠时，**term 名自身的 IRI
  展开必须等于该 term 的 IRI 映射**；1.1 不符 → invalid IRI mapping；
  **1.0 模式不做此检查**。
- oracle：#t0026（1.0 正例）/ #ter43（1.1 负例，**同一输入**）/ #ter44（1.1 负例，
  compact 形 term 名 v:term → v:somethingElse）。
- **勘误（scoped-context 批连带）**：先前实现为「1.1 禁 @type 关键字别名」的**过宽
  门**——它把合法别名（#tin06 的 `"type": "@type"`）一并误拦；替换为上述结构判据后
  #t0026/#ter43/#ter44/#tin06 四例同保。教训入 const §5（判据须照录 spec 的结构
  条件与适用前提，不得以关键字/值黑名单近似）。

### 属性作用域 context（property-scoped context；2026-09-26 定案）
- **两阶段**（REC 4.2.2 @context 臂 + 该臂注记）：
  ① **定义期**：td 的 @context（1.0 模式禁 → invalid term definition）调用 Context
     Processing **只为校验**，结果丢弃；任何错误 → invalid scoped context
     （#tc032/#tc033 oracle：**从未被使用**的嵌入 context 仍须检查）。
  ② **展开期**：该 term 的**值**展开前再处理并套用（REC 5.1.2 "property-scoped
     context"）。
- 作用域传播：随该属性值进入嵌套节点（#tc004 深嵌套两跳生效）；与元素级 @context
  **分层叠加**（#tc005：作用域内 term 命中 scoped 定义，其余键落元素级 @vocab）；
  空 scoped context = no-op（#tc036）。
- **@nest 别名 term 同样适用**（#tc037/#tc038）：别名 term 的 @context 作用于其值；
  scoped context 内可再定义 @nest 别名并自带 scoped context（级联，同一机制递归）。
- **null IRI 映射**（`"term": null` / `{"@id": null}`；REC 4.2.2：value 为 null 视作
  `{"@id": null}`）：term **保留**在 context 中、IRI 展开返回 **null** ⇒ 该键
  **整体丢弃**（#tin06 oracle：scoped context `{"data": null}` 下 `data` 键丢弃）。
  实现注：以"移除定义"实现会退回 vocab 拼成属性，属误判。
- **实现边界（挂账，各自随依赖批）**：type-scoped context（@type 值位 +
  propagate=false + previous context 回退）、@propagate、@import、@protected、
  远程 context。家族普查（52 例带 td 级 @context）逐例归因见 todo §J2。

### 作用域 context 两族边界表（type-scoped 批开工钉；2026-09-26 定）
两族**定义处相同**（td 的 `@context`，同一 REC 4.2.2 臂），**触发点不同**——
**禁复用同一应用入口**（机制互咬先例：C 组容器壳/内层重入曾致 SIGSEGV）：

| 维度 | property-scoped（已落） | type-scoped（下一役） |
|---|---|---|
| 触发点 | active property 的 td：展开该属性的**值**前 | **@type 值位**：展开**当前节点**前 |
| 作用对象 | 该属性的值（含其嵌套节点——作用域**随值**传播） | 该节点自身（**不跨新节点**：展开新节点对象时回退 previous context——#tc009） |
| Context Processing 参数 | propagate 默认 true / override protected true | **propagate=false**（并置 previous context） |
| REC 5.1.2 次序 | 值/映射两分支各一处，**在元素级 @context 之前** | 元素级 @context **之后**：先取快照 type-scoped context = 当时 active，再按 @type 键字典序、值数组序**逐个套用**（后套叠加于前——#tc018） |
| 多值叠加 | 单属性 = 单作用域 | @type 数组按序累加 |
| 空/重置 | `null` = 重置初始 context（保原 base URL） | 同左（`[null, {...}]` = 先重置再叠加——#tc014） |
| previous context | 不设（不参与回退） | 设；**新节点对象**回退（"term-scoped context 不跨新节点"） |
| 实现入口 | `apply_property_scoped_context`（值路径） | **另立** `apply_type_scoped_context`（节点路径）；禁共用入口 |
| oracle | #tc001~#tc005 / #tc036 / #tc037 / #tc038 / #tin06 | #tc006~#tc025（MISMATCH 族）+ #tc009（空过）+ #tc026/#tc027（@propagate 面） |

**开工前置·元素级 @context 次序钉子**：REC 5.1.2 要求元素级 `@context` 在**主键循环
之前**处理；现实现把它内联在键循环里、按**文档序**生效——文档中排在 `@context` 之前的
键会漏掉该 context。oracle = **#t0073**（"@context not first property"，**正例**，
当前 mismatch；manifest 全量扫描：节点级 @context 非首位的例仅此 1 例 / 2 处）。
type-scoped 快照必须以"元素 @context 已生效"的 active context 为底，故此项须先落。

### @protected 机制边界表（@protected 批开工钉；2026-09-26 定，照录 REC）
**保护面仅一处 = 重定义（覆盖）**；豁免靠调用面的 `override protected` 参数传导。

| 面 | 规则（REC 出处照录） | oracle |
|---|---|---|
| 声明 | ① 上下文级 `@protected` 成员 = 该 context 内每个 td 的**默认**保护位（4.1.2 步 5 调用句："the value of the `@protected` entry from context, if any, for `protected`"）；② td 级 `@protected` 覆盖之（4.2.2："Create a new term definition … protected to protected" + "If value has an @protected entry, set the protected flag …；**非布尔 → invalid @protected value**；1.0 模式 → invalid term definition"） | #pr03（整 context 保护）/ #pr04（`@protected:false` 不保护）/ #pr01、#pr11（td 级）/ #pr30（关键字 td 可保护） |
| 保护什么 | **重定义/覆盖**：`override protected = false` 且 `previous definition` 存在且 protected ⇒ 新定义与旧定义**不等价（除 `protected` 值外）**→ **protected term redefinition**；**等价 ⇒ 允许，且 "Set definition to previous definition to retain the value of protected"**（保护位不丢） | 负：#pr26/#pr28/#pr31/#pr32/#pr42；等价允许：#pr23/#pr24/#pr25/#pr27/#pr41 |
| 豁免（解除）面 | ① **property-scoped 应用**：REC 5.1.2 明文"and **true for override protected**"；② **td 定义期 scoped 校验**：REC 4.2.2 `@context` 臂明文"true for override protected"；③ **type-scoped 应用不传**（默认 false）⇒ type-scoped 内空化保护 term 即错 | 正：#pr06/#pr14/#pr15/#pr16；负：#pr17/#pr18/#pr20/#pr21 |
| 空化交互 | `null` 清空时：`override protected = false` 而 active context 含任何保护 term ⇒ **invalid context nullification** | #pr05（embedded）/ #pr17~#pr21 |
| 关键字面 | 关键字 term 可被保护——td 值 MUST 仅 `@container:@set` 和/或 `@protected`；保护后其别名与自身不可被覆盖 | 正：#pr30；负：#pr31/#pr32 |
| td 键白名单 | "If value contains any entry other than @id, @reverse, @container, @context, @direction, @index, @language, @nest, @prefix, @protected, or @type → **invalid term definition**"（本批连带：td 未知键**禁静默忽略**；`@index`/`@direction` 未落码 → Unsupported 活账） | #ter56（未知键） |

**批边界（按批归因，不按族；2026-09-26 用户令）**：@protected 批 = **33 例** =
原 15 例名单改挂后的 14 例（#pr06/#pr14~#pr22/#pr25/#pr26/#pr40）+ 直接相关同族例 19 例
（#pr01~#pr05/#pr09~#pr13/#pr23/#pr24/#pr27/#pr28/#pr30~#pr32/#pr41/#pr42）；
改挂/排除：#pr43（需 `@container: @graph` → @graph 容器批）、#tso07/#tso10/#tso11
（`@import` 面）、#pr29/#pr33~#pr39（compact-IRI 非前缀 term / 关键字形 term，各归其批）。
**真缺口 3 枚**（#pr01/#pr08/#pr11，属本批）——当前"负例却展开成功"的直接机制 = td 级
`@protected` 被未知键 catch-all 静默吞掉（机制缺席，非校验缺口）。

### @container 完整状态表（2026-09-26 立；**逐值列状态，账里不留模糊表述**）
| `@container` 值 | 定义期校验 | 展开期应用 | 状态与归属批 |
|---|---|---|---|
| `@list` | ✅ 白名单（1.1/1.0 分叉） | ✅ 元素展开 + List 包裹 | **已落**（C 组批：#t0004/#t0023/#tli01~#tli10/#ter24/#ter32） |
| `@set` | ✅ | ✅ 摊平即塌缩（no-op） | **已落**（C 组批：#t0015） |
| `@type` | ✅ + **隐式 type mapping 规则**（本批：容器含 @type ⇒ 缺省 @id、显式须 @id/@vocab） | ✅ type map（REC 13.8.3；键前插 @type、@none 跳过） | **已落**（@container 映射批：11 例）；**数组形态**含 @type 未落（无 oracle，挂账） |
| `@index` | ✅（容器合法性 + `@index` **索引映射**校验：1.0/容器不含 @index/非串/展开非 IRI → invalid term definition） | ✅ index map：缺省 ⇒ 写 `@index`（条目已有则保留；值对象位亦可写——#t0036）；**索引映射 ≠ @index ⇒ 索引键写成一条属性**（属性 IRI = 展开 index key；值 = 以 index key 为 active property 的 Value Expansion；**追加在既有值之前**；`@none` 条目跳过——#tpi06~#tpi10） | **已落**（#tc013 + #t0036/#t0063/#t0131 + #tpi01/#tpi03~#tpi10）；**graph 组合**（#tpi11/#tm013/#tm014）挂 @graph 容器族批 |
| `@id` | ✅（容器合法性；1.0 拒绝见 #ter21） | ✅ @id map（REC 13.8.3：条目无 @id ⇒ 写 **document-relative、非 vocab 位**展开的索引；已有 @id 保留；@none/别名跳过） | **已落**（@id 容器 + language map 批：#tm001/#tm002/#tm005/#tm011） |
| `@language` | ✅（含条目值检查：null 跳过 / 非串 → invalid language map value） | ✅ language map（REC 13.8.2：`{@value}` + 语言键；@none/别名不加 @language；direction 面挂 @direction 批） | **已落**（同批：#tm009/#tm010/#t0030/#tl001；#t0040 为"值非 map ⇒ 落通用分支"对照） |
| `@graph` | ⚠️ **验证过窄**（3 元素组合 ["@graph","@index","@set"] 等被误拒——REC 允许 "@graph + either @id or @index optionally including @set"+ 挂「[@set,…] 任意组合」；实测 5 例现红：#t0083/#t0086/#t0097/#t0100） | ❌ **@graph 容器应用未落**（值包裹 graph object + 与 @id/@index/@set 组合；实测 25 例 MISMATCH + 4 例 @none 键 ERR-US） | 挂「**@graph 容器族批**」：33 deferred + #tpr26（plain 负例）= 34 例（#t0079~#t0108/#tc025/#tpr25/#tpr43/#tpi11 + graph index/id map #tm013~#tm016）；**依赖分层**：①验证放宽 ②应用 ③graph map（index/id map 基础已落） |
| `@none` | —（**非**容器值：它是索引/映射键关键字） | ✅ type/index map 键展开为 @none ⇒ **不写索引**（本批；#tm012 含别名）；@id/graph 容器侧随各自批 | 已落（type/index map 面） |

**批归属定案（2026-09-26 用户令确认；命名统一）**：`@id` 容器与 language map **合成一批**
——**批名 =「@id 容器 + language map 批」**。理由：两者同属 REC 的**相邻映射分支**
（13.8.2 language map / 13.8.3 @id map）、**同一落点**（`expand_term_values` 壳的容器分派）、
**共享 context 面规则**（map context 来源 / from-map 语境），合并降低机制切换成本；
仍按**逐例归因**记账（@id map #tm001/#tm002/#tm005/#tm011 + language map #tm009/#tm010，
开工时按现状复勘"直接相关同族例"再定终稿）。

### keyword 形态与 @ 键面已落实现注记（戊批 + 回归修，2026-09-27）
- **keyword 形态**（REC 3.1：`"@"` 后接 ≥1 个纯 ALPHA）**≠ 真关键字**（形态 + 关键字表
  成员）：`"@"`/`"@foo.bar"` 非形态 ⇒ 可作普通 term（#t0119 oracle）；`"@ignoreMe"` 是
  形态但非表成员。
- **td 值（@id / @reverse 两臂）为 keyword 形态非真关键字** ⇒ **照录 REC 的 `return`：
  整个定义放弃**（不安装、不落映射、**不再走无 @id 兜底**）——#t0120（键回落 vocab
  拼接）/ #tpr38/#tpr39（反向映射不落）。
- **真关键字互斥**：term 与展开值同为关键字且不同 ⇒ keyword redefinition（#ter01）；
  **@context 别名禁**（invalid keyword alias，#ter19）；**空 term 名** ⇒ invalid term
  definition（#ter52）。
- **节点位 `@` 前缀非关键字键** ⇒ 忽略、不产出属性（#t0119/#tpr34/#tpr36）。
- **无 @id 兜底门保持严判**（REC 4.2.2 末路：无 vocab 可拼的相对 term 名 ⇒ invalid IRI
  mapping）⇒ **未被使用的嵌入 context 亦须在定义期报错**（invalid scoped context，
  #tc032/#tc033 oracle）。**回归修（2026-09-27）**：曾为让 #tpr38 通过而把此门软化为
  "None 忽略" ⇒ #tc032/#tc033 的拒绝链断掉（2 红）；正解 = 两臂照录 `return`（上游）
  + 兜底门恢复严判。

### @index mapping + index map 校验批已落实现注记（2026-09-26）
- **td `@index` 索引映射**（REC 4.2.2）：仅 1.1 模式且容器含 `@index` 时合法；值须为串
  且 IRI 展开结果须为 **IRI**（关键字/非绝对 → invalid term definition——#tpi01 1.0 /
  #tpi03 关键字值 / #tpi04 非串）。**存原始值**（term 名，如 `"prop"`）：展开期两用
  ——① **re-expanded index** 以 index key 为 **active property** 走 Value Expansion
  （故 `@index:"prop"` 且 `prop` 有 `@type:@vocab` ⇒ 索引成**节点引用**——#tpi08/#tpi10）；
  ② **expanded index key** = 用时期 IRI 展开得属性 IRI。
- **索引属性（REC 13.8.3 子案例 1）**：index key ≠ `@index` 且 expanded index ≠ `@none`
  ⇒ 索引键写成**一条属性**，其值 = `[re-expanded index] ++ 既有同 IRI 值`（追加在前——
  #tpi06/#tpi07/#tpi08/#tpi09）；`@none` 条目跳过（#tpi10）。**值对象条目 ⇒ invalid
  value object**（#tpi05）。
- **子案例 2（缺省）**：条目无 `@index` ⇒ 写 `@index` = 原始索引键；**节点与值对象
  （字面量）位均可写**（#t0036：`ExpandedLiteral.index` 新字段 + 序列化；已有 @index
  保留、null 条目跳过）。
- **reverse 项容器白名单放宽**（REC 4.2.2 明文：reverse 只支持 `@set`/`@index`/null）——
  原实现把任何容器与 reverse 同 td 一律判错 ⇒ 放宽（#t0063 reverse+index 容器 / #t0131
  属性型 index 容器 + 反向）。
- **连带修复：reverse-bearing 节点非自由浮动**（#t0131 oracle）——@reverse 项落在
  `reverse_props` 而非 `properties`，原 free-floating 门只看 properties/types/graph/
  included ⇒ 仅 @reverse 的根节点被误弃；补 `reverse_props.is_empty()`（free-floating 门
  豁免清单第三次扩展：@graph → @included → @reverse）。
- **迁移**：**12 例**（A 亚类 10：#tpi01/#tpi03/#tpi04/#tpi05 + #tpi06~#tpi10 + #t0131；
  B 亚类 1：#t0036；C 亚类 1：#t0063）。**挂账**：D 亚类 #t0044（依赖 td language
  mapping → 「默认语言批」）、E 亚类 #tpi11/#tm013/#tm014（依赖 @graph 容器族批）。

### @id 容器 + language map 批已落实现注记（2026-09-26）
- **@id map（REC 13.8.3，与 @type/@index 同分支）**：容器 `@id` 且**值为 map**；
  map context = active 的 **previous**（存在即用；同 @type）；**仅 @type 面**套索引项
  scoped context（@id 面无）；条目展开传 from-map（不回退）；索引写入 = 条目**无 @id** 时
  置 `@id` 为 **document-relative、vocab=false** 展开的索引（#tm005 相对键经 base；
  #tm001 绝对/bnode 原样；#tm002 已有 @id 保留；#tm011 @none 与别名跳过）。
  **实现连带**：`ExpandedNode.id` 转 `mut`（索引写入需就地改；mbti 同步）。
- **language map（REC 13.8.2）**：容器 `@language` 且**值为 map**；逐条目、条目值非数组则
  归一数组，**null 跳过**、**非串 → invalid language map value**；产出 `{@value: item}`
  并在语言键**非 @none 或展开为 @none 的别名**时加 `@language`（**用原始键**——#tm009
  @none / #tm010 别名 / #t0030 基本 / #tl001 null 跳过）。`direction` 面恒 null（本引擎
  尚无默认 base direction 与 td direction mapping ⇒ 不产出 @direction；#tdi04~#tdi07 挂
  「@direction 批」）。
- **连带修出的重入 bug（#t0040 oracle）**：容器逻辑只作用于**键的值一次**；值的数组项须
  按**元素语义**逐项展开——原实现在内层数组分支重入容器壳，导致 `indexes: [{"@id": …}]`
  的项被当作 index map 条目（产出值对象而非节点，base 也未解析）。修法 = 内层数组分支改
  递归 `expand_term_values_inner`（本批）。
- **迁移**：**9 例**（@id map 4：#tm001/#tm002/#tm005/#tm011；language map 5：#tm009/
  #tm010/#t0030/#tl001 + 对照 #t0040）。
- **挂账（各归其批）**：`@language` **默认语言/td language mapping**（#t0035——@language
  上下文键未落）、`@direction`（#tdi04~#tdi07）、`@graph` 容器族（含 graph id/index map：
  #t0085~#t0108/#tm013~#tm016/#tc025/#tpr25/#tpr43）。

### @container 映射批已落实现注记（@type type map + @index index map 最小子集；2026-09-26）
- **触发**：REC 13.8.3——词条容器 ∈ {@index,@type,@id} **且值为 map** 才进映射分支；
  非 map 值落通用分支（字符串经定义面**隐式 @id type mapping** 成节点引用——#tm017）。
- **定义面（隐式 type mapping）**：容器含 `@type` ⇒ 未声明 `@type` 时置 `@id`；已声明
  则须为 `@id`/`@vocab`，否则 `invalid type mapping`（#tm017/#tm018/#tm019 正 / #tm020 负）。
- **map context 按容器种类分叉**：`@id`/`@type` ⇒ active 的 **previous**（存在即用）；
  `@index` ⇒ **active**（REC 原文两分支）。**仅 @type 面**再套用**索引项**的 scoped
  context（在 map context 中查 td；#tm008），故"type map 用类型索引项的 scoped context、
  不用包含方的"（#tc013）。
- **from map 语境**：条目展开传 `true for from map`（不回退 previous）——本引擎以
  "previous 已清空的等价 context"表达（省一维参数；语义等价，机制面记入 const §5）。
- **索引写入**：`@type` ⇒ `types = [expanded index] ++ 既有`（**前插**，非替换——#tm004；
  键按 vocab 位 IRI 展开）且 `@none`/别名跳过（#tm012；条目仍产出）；`@index` ⇒ 条目无
  `@index` 时写**原始索引键**（`ExpandedNode.index` 新字段 + 序列化 `@index`）。
- **迁移**：**11 例**（#tc013 + #tm003/#tm004/#tm006/#tm007/#tm008/#tm012/#tm017/
  #tm018/#tm019 + 负 #tm020）。
- **挂账（各归其批）**：`@id` 容器（#tm001/#tm002/#tm005/#tm011）、language map 应用
  （#tm009/#tm010）、`@index` **mapping**（td `@index` → 索引属性）与 index map 校验
  （#tpi01~#tpi11 + #t0036/#t0040/#t0044/#t0063/#t0131）、`@graph` 容器族 34 例 +
  graph index/id map（#tm013~#tm016；index/id map 语义须随该批立项）。

### @protected 已落实现注记（2026-09-26 收口）
- **落码面**：`TermDefinition.is_protected`（字段名避开保留字 `protected`）+ 上下文级
  `@protected` 默认位（1.0 → invalid context entry、非布尔 → invalid @protected value，
  先验）+ td 级覆盖（非布尔 → invalid @protected value、1.0 → invalid term definition）
  + **安装期保护检查**（`install_term_definition` 唯一入口，简单臂/td 对象臂/关键字臂
  三处同源：等价 ⇒ 保留旧定义【保护位不丢】/ 不等价 ⇒ protected term redefinition）
  + **调用面旗标 `ContextFlags`**（结构体而非相邻两个裸 bool——`type_scoped()` =
  {propagate:false, override:false} / `property_scoped()` = {true,true} / `element()` =
  {true,false} / `scoped_validation()` = {true,true}）+ null 空化门（override=false 且
  含保护 term → invalid context nullification）+ 关键字 term 受限重定义（仅
  `@container:@set` 与/或 `@protected`；空 map 不满足——#tec02）。
- **连带修正**：td 未知键**不再静默忽略**——`@index`/`@direction` → Unsupported
  （落码活账），其余键按 REC 键白名单报 invalid term definition。
- **迁移口径**：**32 例**（正 15 + 负 17，负例错误码逐一命中）；#tpr42 由"埋雷族
  通过机制未复审"转**真判据**（第三个复审件）。
- **挂账（各归其批）**：#tpr25（等价重定义**允许**但 oracle 需 `@container:@graph`
  的包裹输出——随 @graph 容器批；保护面本身已对）、#tpr43（同上，@graph 容器）、
  #tso07/#tso10/#tso11（@import 面）、#tpr29/#tpr33~#tpr39（compact-IRI 非前缀 term /
  关键字形 term 忽略面——各自批）。

### type-scoped context 已落实现注记（2026-09-26 收口；边界表见上）
- **次序照录**（REC 5.1.2 映射分支）：previous 回退 → property-scoped 应用 → **元素级
  @context** → type-scoped 快照/套用 → 主键循环。**元素级 @context 必须先于主键循环**
  （#t0073 oracle，已收敛——原实现按文档序内联）。
- **快照 vs 累积**：td 查询用**快照**（type-scoped context），应用**累积**到 current
  （#tc018 oracle）；**@type 值自身用快照展开**（#tc014：type-scoped `[null]` 空化后
  @type 仍得外层 vocab 的 http://example/Type；#tc018 同理）。
- **回退门**（active 带 previous 时）：值**既非**"含键展开为 @value"**也非**"单条展开
  为 @id" 才回退；两形判定都以**回退前** context 做——#tc015（单 @id 形保 type-scoped
  @base）/ #tc020（值对象形保 `value:@value` 别名）/ #tc009（多键嵌套节点回退 ⇒ 不跨
  新节点）/ #tc016（回退 ⇒ 嵌套节点落 outer vocab）。
- **@propagate 成员**（REC 4.1.2 步 2 + 步 5.x 校验）：type-scoped 默认 propagate=false，
  成员可覆盖（#tc026 `true` = 传播到嵌套节点）；1.0 模式 → invalid context entry
  （#tc029）、非布尔 → invalid @propagate value（#tc030）。
- **属性作用域捕获点**（#tc012 oracle）：property-scoped context 必须在**回退前**从
  active 的 td 捕获、在**回退后**的 context 上应用——回退后重查 td 会丢 scoped 定义
  （本批首跑即红，次序坑）。
- **@included / @graph 递归调用**（REC 13.4.6.x，from map 未传）同受回退门约束。
- 迁移口径：#t0073 + #tc006~#tc011/#tc012/#tc014~#tc024/#tc026~#tc028/#tc035 = **23 例**；
  #tc029/#tc030 从"通过机制未复审"的埋雷族**转真判据**（非新增迁移）。
  挂账：type map（#tc013/#tm008，需 @container @type）、#tc025（@graph 容器）、
  #tc031/#tc034（远程 context）、#tpr08（@protected）。

### 套件比对语义（canonical_for_suite，2026-09-26 tn004 谜底定案）
- 官方 README「JSON-LD Object comparison」移植：对象键序不敏感；**数组默认
  无序**——唯一例外 = `@list` 键下的数组保序；标量严格相等。语言标签大小写
  不敏感项未采（现役从严，从严不违官方）。
- 勘定依据：expand manifest 385 例 **0 件 `ordered:true`**——expected 文件的
  数组序只是合法置换之一（#tn004 双 @nest：文档序保序输出 [v2,v4,v3] 与
  expected [v2,v3,v4] 互为合法置换，官方同判；探针实证后删）。
- 落码：engine.mbt `canonical_for_suite`（suite 比对通道唯一入口）；
  `json_canonical`（数组保序）保留供他用，**禁止再用于套件对拍**。

### 红线与判据（2026-09-25 定）
- 递归策略、搜索剪枝、工程权衡一律不进表；condition 只收可枚举的形态判断；
  handler_hook 只指向手写 trait 方法。
- 判据：表里能 grep 出"递归/深度/策略"的行级编码，就是设计错误。

### 8. specVersion 依赖（模式分叉，勘定 2026-09-25）
- 结构事实：@vocab 相对值/空串的判定**依赖 processing_mode**——
  json-ld-1.1 模式 = 对 base raw 拼接有效（#t0092 oracle：空串 → base 本身、
  `../` 原样不消点段）；json-ld-1.0 模式 = invalid vocab mapping
  （#t0115/#t0116 oracle）。
- 勘定结论（expand 套件全量 grep）：**无同输入多版本分叉对（0 对）**；真分叉仅
  @vocab 相对值一条语义（2 例），其余 1.0 负例（ter02/03 递归包含、ter24 list of
  lists）在 1.1 同判错误——窄依赖，已一次性勘清。
- 实现纪律：模式分叉必须经 `options.processing_mode` 显式条件化
  （expand_standard.mbt process_context @vocab 臂），禁止以单一模式行为充当全模式。
- **第一实证（1.0 校验时序，2026-09-25）**：@vocab 非绝对的 invalid 判定必须在
  base 解析**前**对原始值做——1.0 语义不做 base 补全，先解析后校验会把空串补成
  绝对而漏拦（实测：#t0115 首轮误过）。后续模式分叉差异均记入本节。
- **第二实证（list-of-lists 模式分叉，2026-09-26）**：@list 嵌套——1.1 允许
  （#tli01 正例：嵌套 list 对象保留）/ 1.0 禁止（#ter24/#ter32 负例：list of
  lists）；**输入相同，按 processingMode/specVersion 分叉**（实现：
  expand_list_item 数组臂 1.0 短路 + 拦截器/容器 @list 臂 1.0 元素扫描）。
- 挂账清账（2026-09-26）：harness per-case options **已落**（specVersion +
  processingMode + document-location base 注入）；RFC3986 IRI 解析**部分落地**
  （点段消除已入 resolve_base_value / merge；@vocab raw 拼接语义保留——
  #t0092 oracle 不变）。

### 表的层级归属（2026-09-25 定案）
三表只收 **element expansion 层**的分派；context 处理层键（`@vocab` / `@base` / `@container` /
`@prefix` / `@protected` / `@propagate` / `@import`）**不进三表**，走手写
`ContextProcessor::process_context`（keyword_dispatch 的 `@context` 行只是 element 层入口，
指向该手写方法）。J2 不存在「context 处理没表可依」——它本来就不该有表。
复核条件：J1 schema 定稿时，若 context 键分派实测为「机械枚举且多处复用」，再议第四表
（`[[context_keyword_dispatch]]`）——须同笔走绑定器词表与黄金门，禁止手改生成物。

## 5 对账
- 骨架：从 TOML 生成的接口与调度
- 手写：在骨架钩子里实现递归
- 对账门：接口一致 + 步骤覆盖 + 值级对拍

## 6 与现有体系的关系
- 共享库：TOML 读、代码 emit、测试 harness
- 不共享：schema 语义、生成器框架、FSM 形状
- 复核面：新增 "JSON-LD 一致性面"
- 套件：W3C json-ld-api @ `ffdb326` 自包含于本目录 `.rdf-tests/json-ld-api/`
  （`.rdf-tests/SHA256SUMS` 钉版 2626 件；路径以本目录为仓根——将来独立出项目整目录随迁）；
  一致性基线 = `consistency-baseline.txt`（统计中未设阈值）

## 7 与调研卷（bangto/jsonld）的差异对照（勘定 2026-09-25）

调研卷（`bangto/jsonld/` 五份，2026-09-14）是立项前的调研产物；本目录四卷为实施权威。
分歧不散写正文，统一收此表——调研卷 ADR-JL-001~008 描述的是调研期"四层编译式架构"，
凡与本表冲突处以本表为准。

| 事项 | 调研卷口径 | 实施卷口径（权威） | 处置 |
|---|---|---|---|
| JSON 词法/语法层 | 自建四层（惰性 Lexer→Parser，GB 级流式；ADR-JL-001/003） | 不做（§2 红线）；用 core `@json.parse` | 已定案；core 语义勘定见 ctx.md §2 |
| 键序/重复键 | ADR-JL-002 红线：`Array[(String, RawValue)]` 全量保留 | core `Object(Map)` 无序，重复键 last-wins 折叠 | J0 实证：可容（1.1 算法按属性排序 + JS 等价折叠）；J2 对拍收口 |
| 数词形 | `RawNumber(Double, String)` 保留词形 | core 常见路径仅 Double；超 2^53-1 / strconv 回退时 `repr~` 留原文 | J0 实证注记；J3 toRDF 对拍收口 |
| compaction | 核心层（Expander 的逆操作） | 暂不做（§1，看擂台） | 立案不排期；套件 compact 246 例规模在册 |
| N3 互操作（@graph↔Formula） | 规格 + ADR 在册 | 不在本子项目范围 | 两面各自收口后另立 |
| Datalog / GraphDB Sink | 物化层规格在册 | 不做 | 同上 |
| 性能底线（1μs/token 等） | 宪法量化条款 | 缓打（todo：先测后优化） | 性能优化立案不排期 |


## 8 J3 前置勘定（toRdf 467 例；2026-09-28 勘定，开工前钉）
### 8.1 套件结构（manifest 实测）
- **构成**：467 = 正例 **345**（全部带 `.nq` expect）+ 负例 **106**（无 expect，
  must-error）+ 正句法 **16**（无 expect，must-not-error）。输入全为本地 `.jsonld`
  （467/467），**无网络面**（remote-doc 仅 expand 套件）。
- **选项面**：specVersion 276（1.1×265 / 1.0×11）；`useJCS` **23**（tjs01~23 全数）；
  `rdfDirection` 4（tdi09/10 = i18n-datatype、tdi11/12 = compound-literal）；
  `produceGeneralizedRdf` 2（#t0118/#te075）；`base` 8（#te076 系）；expandContext 1
  （#te077）；processingMode 8。expand 套件的预载/loader 垫片直接复用。
- **判定方式（与 expand 本质不同）**：expected = **N-Quads 文本**，README 判据 =
  **RDF Dataset Isomorphism**（bnode 双射），非 JSON 对拍——`canonical_for_suite`
  不适用，harness 须开**第二判定通道**。参考实现用 `_:b0` 顺序标签（README 允许
  同标签法实现走字面对比），但**双射比较更稳**（不追参考实现标签序）。

### 8.2 ExpandedNode → RDF 映射规则（REC §6 对应物；词形已套件实证）
- **主体**：节点 `@id` 须绝对 IRI 或 `_:bnode`（bnode 标签**保留原样**）；相对/
  被忽略的 @id ⇒ **三元组弃**（与己三批"相对保留/EXPLICIT_NULL_ID"语义衔接——
  expand 层合法 ≠ 可序列化）；无 @id 节点 ⇒ 新生 bnode；**同 subject emit-once**
  （环安全，bnode 引用共享 id）。
- **谓词**：展开后属性 IRI 即谓词；非绝对 ⇒ 弃（负例面：invalid literal datatype
  IRI rejected 同族）。
- **值对象 → 字面量**（词形地雷全录）：
  - 串无语言 ⇒ 简单字面量（N-Quads 无 `^^`，RDF 1.1 隐含 xsd:string）；有语言 ⇒
    语言标签字面量；`@direction` 缺省**不进 RDF**（rdfDirection 选项面才进，见下）。
  - 显式 datatype ⇒ `^^<IRI>`（套件面：xsd:date/custom IRI 等）。
  - **数值 ⇒ XSD 典范词形转换**（ExpandedLiteral.raw 保形正是为此役铺垫）：
    integer = `7000000`（无分隔/无前导零）；double = **E 记法典范形**
    `"1.0E0"`/`"1.2345E2"`/`"1.0E21"`（套件实测 6 枚）；boolean = `true/false`。
  - **@json ⇒ rdf:JSON 字面量**（套件 23 枚，全挂 useJCS）——词形 = **JCS
    （RFC 8785）典范化 JSON**。
- **@list ⇒ rdf:first/rdf:rest 链**，终结 `rdf:nil`；嵌套 list ⇒ 嵌套链；空 list ⇒
  仅 `rdf:nil`。（@set 展开期已塌缩，toRdf 不可见。）
- **@graph**：节点位 ⇒ 具名图（图名 = 节点 @id / 新生 bnode——套件四段行实证
  `<s> <p> <o> <g> .`）；顶层 @graph 数组 ⇒ **默认图**。
- **rdfDirection 选项**：`i18n-datatype` ⇒ datatype
  `https://www.w3.org/ns/i18n#{lang}_{dir}`（空语言 = `_rtl`，套件实证两形）；
  `compound-literal` ⇒ 重化 bnode（rdf:language/rdf:direction 附加三元组）。
- **produceGeneralizedRdf**：放行广义三元组（仅 #t0118/#te075 两例）。

### 8.3 与现有 trig/nquads 机器的关系（src/ttl 子仓）
- **方向相反**：gen_trig/gen_nquads = RDF 文本 → 四元组（FSM 生成链）；jsonld
  toRdf = JSON 树 → 四元组（手写 `ToRdfProcessor::node_to_quads`，J1 契约面 +
  `JsonLdQuad{subject,predicate,object,graph}` 串模型已立）。共享的只是**四元组
  概念与 RDF 词形规则**，无代码复用面（架构异源，禁硬套表源——const §5 首条）。
- **gen_nquads 词法扫描器**（is_numeric_span/is_boolean_word/banned langstring）
  = RDF 词形规则的**参考实现**，J3 判定器可概念镜像；黄金门 G9（n3gen）正交，
  提交前必跑口径不变。
- **expected .nq 的读入**：判定器在 jsonld 测试面**自建 N-Quads 迷你解析** +
  bnode 双射（行式状态机 12 态 + canonical 转义双端同用）。**够用性全量实测
  （2026-09-28，345/345 expected 全过）**：1502 四元组 / 单文件最多 42 / 223
  文件含 bnode / 自同构全绿（修出两枚：自指 `_:b0 _:b0 _:b0` 的**同源同靶**
  绑定一致性 + generalized 谓词位 bnode 纳入 bucket/标签收集）。**ttl 依赖
  挂起（用户令 2026-09-28）**：主仓 moon.mod 已声明 `thy1016/moonttl@0.2.2`
  （本地 src/ttl 为 0.3.0-dev），待 0.3.0 发版后升引——gen_nquads 可作
  differential oracle（桥接件挂账不排期）；判定器规范形转义双端同用保证
  判定与词形解耦。**升级触发条件（任一即启，防「够用」变「永不升级」）**：
  ① moonttl 0.3.0 发版 ⇒ 升引版本行 + 差分对照探针一枚（迷你判定器 ×
  gen_nquads 对拍全部 expected，结论入账）；② 迷你判定器发现**自同构覆盖
  不到的边界**（受限子集外的词形/需要规范化面）⇒ 当批评估切换或加固。

### 8.4 范围重估（改变 J3 范围的四点）
1. **JCS 是新机制子役**：23 例挂它，RFC 8785（ECMAScript 数值词形 + 串转义 +
   键序）需独立落码——**tjs01~23 单独成桶**，JCS 未落前不入 plain 判定。
2. **数值典范形转换是新码**：expand 侧 raw 保形（J0 勘定）到 toRdf 侧 XSD 典范
   词形（double E 记法）是**转换关系**非透传——types.mbt「xsd 词形挂 toRDF 役」
   兑现面。
3. **判定器本身是机制面**：迷你 N-Quads 解析 + isomorphism 双射 = harness 新件
   （J3.0 先行独立批，判定器不绿则正例全不可判）。
4. **负例 106 + 句法 16 近乎零码**：toRdf 管线 = expand → quads，负例多为 expand
   期错误穿管复现（错误码共用面），随 J3.1 逐例验证传播即收。
- **批次切分提案**：J3.0 判定器 → J3.1 核心映射（串/语言/datatype/bnode/list 链/
  具名图/emit-once，正例主力）→ J3.2 数值典范形 → J3.3 JCS → J3.4
  rdfDirection+generalized（6 例）；负例/句法随 J3.1 验收。
