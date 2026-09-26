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
| #t0092 vs #t0115/#t0116 | specVersion 分叉 | processingMode | @vocab 相对/空串：1.1 base raw 拼接有效 / 1.0 invalid vocab mapping（校验先于 base 解析） |
| #ter23 vs #t0029 | 位置分叉 | 展开位置（td 定义值 vs 文档值位） | td @type 相对值不落 base（invalid type mapping）；文档值位相对 IRI 落 base 解析（含 fragment/query/scheme 相对） |
| #t0026 vs #ter43 | specVersion 分叉 | td 定义 **term 名一致性检查**（非"@type 别名"黑名单） | 同输入（含顶层 @graph）：term 名 = rdf:type 长名，其自身展开 ≠ IRI 映射（@type）→ 1.1 invalid IRI mapping / 1.0 不检查（合法）。同类 1.1 负例 #ter44（compact 形 term 名映射他处） |
| #tc006/#tc016 vs #tc014/#tc018 | 位置分叉（**同一节点内**） | 展开位置：节点键（套用后的 context）vs **@type 值自身（快照）** | type-scoped context 空化/换 vocab 只影响节点键；**@type 值仍按快照展开**（#tc014：`[null]` 下 @type 仍得 http://example/Type；#tc018 同理） |
| #pr23/#pr24/#pr27/#pr41 vs #pr26/#pr28/#pr42 | 定义面分叉（**保护穿透**） | 新定义与旧定义是否**等价（除 protected 位外）** | 等价 ⇒ 允许重定义**且保留旧定义**（保护位不丢，#pr42）；不等价 ⇒ `protected term redefinition`（判据看**旧定义**是否受保护——#pr04：新定义带 `@protected:false` 也不豁免） |
| #pr06/#pr14/#pr16 vs #pr17/#pr18/#pr20/#pr21 | 调用面分叉（**同一空化形态**） | override protected 的**传导面** | property-scoped 应用与定义期 scoped 校验传 true ⇒ 空化保护 term 允许；**type-scoped 应用不传（false）**⇒ 同一 `null`/`[null]` 形态报 `invalid context nullification` |
| #tec02 vs #pr30 | 形态分叉（**关键字 term 的 td 值**） | `{"@container":"@set"}`/`{"@protected":…}` 的有无 | "only either **or both of** following entries" ⇒ 须**至少一条**：`{"@type": {}}` → `keyword redefinition`；`{"@container":"@set","@protected":true}` → 合法（关键字可保护） |
| #tc013 vs #tm003/#tm006 | 容器种类分叉（**map context 的来源**） | 容器 ∈ {@type}（用 previous）vs {@index}（用 active） | @id/@type 容器的 map context = active 的 **previous**（存在即用）；@index 容器 = **active**——#tc013 因此让内层 map 用 base 的 index 容器定义、而非外层 type-scoped 的 |
| #tm003/#tm004 vs #tm012 | 键形态分叉（**@none 与索引写入**） | 索引键是否展开为 `@none` | 普通键 ⇒ **前插** @type（已有 @type 时前插，非替换）；`@none` 及其别名 ⇒ **不写索引**（条目仍产出） |
| #tm017/#tm018/#tm019 vs #tm020 | **定义面分叉**（container @type × type mapping） | 显式 `@type` 是否 ∈ {@id,@vocab} | 容器含 `@type`：未声明 ⇒ **隐式 @id**（#tm017）；显式 `@id`（#tm018）/`@vocab`（#tm019）合法；其它值（如 `"literal"` 经 vocab 展开成 IRI）⇒ **invalid type mapping**（#tm020 负） |

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
| `@index` | ✅（容器合法性） | ⚠️ **仅最小子集**：值为 map 时"条目无 @index ⇒ 写原始键" | **部分落**（解锁 #tc013）；**td `@index` mapping（索引属性）未落** ⇒ 余挂「@index mapping + index map 校验批」 |
| `@id` | ✅（容器合法性；1.0 拒绝见 #ter21） | ❌ **@id map 应用未落** | 挂「**@id 容器 + language map 批**」（#tm001/#tm002/#tm005/#tm011） |
| `@language` | ✅（含展开期值检查 #ter35） | ❌ **language map 应用未落** | 挂「**@id 容器 + language map 批**」（#tm009/#tm010） |
| `@graph` | ✅ | ❌ **@graph 容器应用未落**（值包裹 graph object + 与 @id/@index/@set 组合） | 挂「**@graph 容器族批**」：34 例（#t0079~#t0108/#tc025/#tpr25/#tpr43 + graph index/id map #tm013~#tm016） |
| `@none` | —（**非**容器值：它是索引/映射键关键字） | ✅ type/index map 键展开为 @none ⇒ **不写索引**（本批；#tm012 含别名）；@id/graph 容器侧随各自批 | 已落（type/index map 面） |

**批归属定案（2026-09-26 用户令确认；命名统一）**：`@id` 容器与 language map **合成一批**
——**批名 =「@id 容器 + language map 批」**。理由：两者同属 REC 的**相邻映射分支**
（13.8.2 language map / 13.8.3 @id map）、**同一落点**（`expand_term_values` 壳的容器分派）、
**共享 context 面规则**（map context 来源 / from-map 语境），合并降低机制切换成本；
仍按**逐例归因**记账（@id map #tm001/#tm002/#tm005/#tm011 + language map #tm009/#tm010，
开工时按现状复勘"直接相关同族例"再定终稿）。

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
