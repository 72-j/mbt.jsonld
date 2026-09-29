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

### IRI 规则的 expand/toRdf 共享面（2026-09-28 钉）
两面 IRI 规则 = **同一套函数单点实现**（expand_iri 五分类、merge_base_reference/
resolve_base_value、colon_index、is_valid_absolute_iri）——to_rdf_document 走
expand_top_values 全链，修正单点落共享函数，385+416 两面同批受测。唯一有意
分叉：**发射期绝对性**（nq_iri_term——expand 期允许的相对保留值 [t0060 oracle]
在发射面弃 [te122/t0016 oracle]），由分层保证。IRI 规则批（A/B/C 三组）勘定
表见 todo 同日账。

### IRI 解析实现边界（2026-09-26 定案；三者皆 RFC 3986 实现边界）
- **merge_base_reference（5.2.3 merge，authority-only）**：相对引用 = base 截最后
  "/"（含）+ 引用；base 仅到 authority（无路径 "/"）→ 补根 "/"（#t0129/#t0130
  oracle）。**绝对路径引用（"/" 开头）= authority 保留、path 整体替换**
  （#t0051 oracle：/issue/1 → https://w3c.github.io/issue/1；authority_root
  助手截 scheme://authority，无 authority 形态落回相对合并）。
- **resolve_base_value（5.2.4 点段消除；A组终版 2026-09-28——段模型统一）**：
  **豁免面唯一 = R.path 未定义**（引用拆 = 路径部分〔首个 ?/# 前〕+ 尾巴；
  **路径部分为空 ⇒ merge 原样、T.path = Base.path 词面**——s091 `?y`：base
  `/./` 保留。判据从早期"含 ?/# 即豁免"收窄至此——#t0091 实测修正：「消除
  只作用于引用贡献段」命题只在 R.path 未定义与根/授权替换两形成立，相对形
  消除域 = merge 后**整条路径**，base 贡献段一并消除）。非空 ⇒ 段算法：段源
  = full_path **去首段**（首段恒为根标记 ""，seeds=[""] 承担；斜杠开形 merge
  已换根故 full_path 即引用自身路径；`//g` ⇒ 段空 ⇒ 裸 authority，s006
  oracle）。pop 守卫 >1 护根标记（**超根截停**，#t0029 still-root oracle）；
  **内部空段保真**（RFC 不折叠 "//"——#t0128 base `ab//de` oracle；s303
  `../xyz` 弹掉的正是空段）；段尾 "." / ".." / "" ⇒ 尾斜杠（s117/s100
  oracle）；尾巴（query/fragment）渲染尾接挂（s296 族 `.?a=b` →
  `http://abc/def/?a=b`）。value 绝对 → 原样返回不做归一（#t0092 oracle：
  raw 拼接即预期）。
- **nq_iri_chars_legal（发射面字符门，B组② 2026-09-28）**：RFC 3986/3987
  文法外字符（`<`/`>`/空格/`"`/`{}`/`\`/`^`/`` ` ``/`|`）⇒ nq 层弃发
  （#tli12 oracle：`http://invalid/<>/test` 三元组不产出）。接线三发射位
  （nq_iri_term / nq_node_subject 绝对臂 / datatype 臂）。**expand 面不受扰**
  （分层归因——expand 保留原样是正解；与 is_valid_absolute_iri 的 scheme
  文法正交，仅 nq 发射层合用）。
- **merge_base_reference 三形臂位边界（B组核 2026-09-28；authority 感知，
  取代 idx>6 魔数）**：相对合并 rev_find("/") 的 idx 判位——
  ① **全串无 `/`**（`tag:example`/`ex:`）→ colon_index 截 scheme、引用替换
  整段路径（#t0130/#tli11 oracle：`tag:a`/`ex:test`）；
  ② **有 `/` 无 `//`**（scheme-only 带 path：`tag:example/foo`）→ 截最后
  `/`（含）+ 引用 = 目录替换（#t0131/#t0132 oracle：`tag:example/a`/
  `tag:example/foo/a`）；
  ③ **有 `//`**（authority 形）→ idx 落在 `//` 尾内（`http://a` idx=6）⇒
  path 空 ⇒ 补根 `/`（#t0129 oracle）；idx 越过 `//` 尾 ⇒ 目录截段
  （#t0128 family：`http://ab//de//ghi`）。
  短 scheme 角（`a://b/c` idx=5 曾 ≤6 误走补根臂）套件不可达，wbtest
  oracle 钉（B组边界钉）。契约外退化形（无 scheme base）输出形状随边界
  更新（`a/b` + `/c` → `a//c`，wbtest 注明 contract-外）。
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
| **oracle > 规范字面 分叉族**（三例归组；2026-09-29 收录两例） | | | |
| #tjs13 vs RFC 8785 §3.2.3 字面 | 键序定义分叉 | JCS 键序：套件 oracle = **Unicode 码点序**（U+F8DF < U+1F602）vs RFC 字面「UTF-16 码元序」（D83D < F8DF） | 码点序胜出——nq_key_compare 逐码点自实现（const §5 String::compare 假序同日禁用） |
| toRdf @reverse vs REC §6.3 反转形 | 展开词形分叉 | 引擎 = **t0042 保形**（@reverse 映射保留）vs REC 字面反转形（node 获反向属性） | 保形胜出——reverse 批 oracle 沿袭；J4 fixture 首写按 REC 记忆错一处实证 |
| flatten te001 vs free-floating 字面弃置 | 弃置位分叉 | free-floating（@id-only 弃）是否豁免 **@index**：oracle 要求 @id+@index 裸节点**必达合并面**（te001「Conflicting indexes」负例——弃则冲突不可见，负例永不可红） | **@index 豁免胜出**——is_free_floating 增 `index is None` 位；expand/toRdf 套件无此形在册案例（零回归面实测） |
| **scoped 来源分叉族**（2026-09-29 役3 收录） | | | |
| #tc009 vs #tc013 | **scoped 来源分叉**（同形异判对——同一定义 `baz:{"@type":"@vocab"}` 分置 type-scoped / property-scoped） | type-scoped 定义的 term **只作键名**、datatype/container/language 不参与值成形（#tc009 值保 `{@id}` 对象形）；property-scoped 全参与值成形（#tc013 @vocab 型塌缩 vocab 相对词 "buzz"） | 双 oracle 各自成立——scoped context 双链分立的实证（机制账 §8.44） |
| **族判据** | | | **规范字面与套件 oracle 冲突时，套件 oracle 为权威**——规范是解释起点，套件是判定终点；分叉必须在账（两例皆入册），禁静默择一 |

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

### 5.1 J4 对账三件套（2026-09-29 开工钉；J2/J3 全 plain ≠ 收官）
**J4 的比较对象 = 骨架 vs 手写**（gen 产物 jsonld_gen.toml 声明面 ↔
expand_standard/to_rdf 手写钩子），**不是模型 vs 引擎**——J2/J3 的套件对拍
是后者（引擎行为 vs W3C oracle），两者互补不可互替：
1. **接口一致**：gen 产物接口（.mbti / 调度表行）与手写钩子签名逐一对照
   （interface_gate_test 既有门——复核覆盖面是否含 J3 新增 to_rdf_document/
   node_to_quads 臂）。
2. **步骤覆盖**：gen 表每行 handler/None 裁定 vs 手写实现落点——None = 已裁定
   无需手写（ctx §3 口诀），非空 hook 必有落点；缺行/多行皆红。
3. **值级对拍**：同一输入过 gen 调度面与手写链各一次，产物逐值对拍
   （黄金门形态——G9 同款；J4 新增面 = expand/toRdf 两调度路径）。

### 5.2 J4 对账产出（2026-09-29 首轮）
- **骨架 vs 手写分叉账**：keyword_dispatch 的 9 行 handler_hook
  （set_language/set_direction/expand_list/expand_set/expand_graph/
  expand_reverse/expand_nest/expand_included/set_index）指向 **pending 桩**——
  真落点 = expand_object 内联臂（J2 各批实装处）。表行 = 声明的语义归属
  （j4_reconcile_test 分叉账钉钉住声明面）；桩由 expand_standard_wbtest 的
  Unsupported 常驻活账管辖。**非红判据三条（全满足方可判非红，任一破即红）**：
  ① 语义经内联臂**全数兑现**（件 2 fixture 逐行值级证明——断链即红）；
  ② 表行 = 声明的语义归属（分叉账钉钉住声明面，**漂移即红**）；
  ③ 桩由 Unsupported **常驻活账管辖**（误调即红——桩被实调说明路由错位）。
- **两处词形 oracle 勘定**（fixture 首写凭 REC 记忆写错、实跑纠正）：
  @reverse = t0042 保形（@reverse 映射保留，非反转）；@included = in01 保形
  （键渲染）。@id 独节点/free-floating 弃、值对象顶层弃、reverse 串值拒
  ——fixture 编写必须从既有 oracle/实跑取形，禁凭记忆。
- **载件**：j4_reconcile_test.mbt——14 路由 + 7 步骤 + 7 iri_rules + 分叉账钉
  + torf 值级件，61 测试全绿。

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

### 8.35 J3.3 JCS 批已落注记（2026-09-29）
- **JCS 键序 = Unicode 码点序**（套件 oracle：#tjs13 U+F8DF < U+1F602）——
  RFC 8785 §3.2.3 字面为「UTF-16 码元序」，两者在**星形面（BMP-PUA × 星形
  代理对）分叉**；以套件 oracle 为准，`nq_key_compare` 逐码点自实现。
  **`String::compare` 禁用**——长度优先假序（const §5 同日入册）。
- **数值词形职责分离（独立实现，不混用）**：
  `nq_canonical_number`（J3.2，XSD 典范词形——`5.3E0`/整形无分隔，toRdf
  字面量发射臂）≠ `nq_jcs`（J3.3，ECMAScript Number::toString 词形——
  `1e+30`/`0.002`，rdf:JSON 词形）。MoonBit Double 显示 = ECMAScript 形
  （探针实证），JCS 数值零转换直用；两词形服务两 oracle 族，**禁互相借调**。

### 8.36 J3.4 开工钉（rdfDirection + produceGeneralizedRdf；2026-09-29 实证定案）
- **rdfDirection 值域**：`"i18n-datatype"` | `"compound-literal"`（缺省 None =
  @direction 弃——方向本就非 RDF 可序列化面）。与 @direction 关系：@direction
  是展开期值对象成员；无选项时仅语言进 langtag（方向弃）；**有选项且值对象带
  方向**时方向决定字面量的 RDF 形态；无方向 + 有语言 ⇒ 常规 langtag（选项不
  触发——四例 input 全带方向，无此反例面，照 REC 落）。
- **tdi×4 覆盖（全部实证）**：
  - tdi09 = i18n-datatype × 仅方向 ⇒ `"no language"^^<https://www.w3.org/ns/i18n#_rtl>`
    （**空语言段 = "_"**）
  - tdi10 = i18n-datatype × 语言+方向 ⇒ `"en-US"^^<i18n#en-us_rtl>`（语言
    **小写化**入 datatype；值原样）
  - tdi11 = compound-literal × 仅方向 ⇒ 对象换新 bnode + `(b, rdf:value,
    简单字面量)` + `(b, rdf:direction, "rtl")`
  - tdi12 = compound-literal × 语言+方向 ⇒ 上形 + `(b, rdf:language, "en-us")`
    （**小写**）；rdf:value **恒简单字面量**（语言不进 value——di12 实证）
  - 二值互斥（单选项）；compound 的 bnode 不带 rdf:type。
- **produceGeneralizedRdf**：谓词位放行 bnode（t0118：term→`_:term` bnode 映射
  经谓词位；te075：`@vocab: "_:"` + 属性名 ⇒ `_:b1/_:b2` 谓词）。其余不变：
  相对 IRI 仍按 base 消解（0118 `relativeIri` → 文档 URL 全形实证）；bnode 型
  @type 照 tm003 臂发射。
- **图位是作用域键的一部分（个案收官定案，2026-09-29）**：同 id 节点预合并
  （F2）与 emit-once 同一原则——**作用域键 = graph_key|id**：默认图与各具名
  图是不同作用域，跨图不并。#t0027（Paris#this 两图各发其属性）与 #te108
  （@graph+@id map 同键双图对象 graph 内容并集）是同一原则的两面：图内
  合并、跨图隔离。

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


### 8.37 J5 立案（复核面/一致性面——立案不排期，2026-09-29）
照 §6「复核面：JSON-LD 一致性面」六步走。**复现命令钉（第三方可执行口径）**：
- **套件版本**：W3C json-ld-api @ `ffdb326`（`.rdf-tests/SHA256SUMS` 钉版
  2626 件；自包含于 `src/jsonld/.rdf-tests/json-ld-api/`，路径以本目录为仓根）
- **前置**：clone 本仓到任意路径（仓根 = 含 moon.mod 的目录）
- **命令**：`moon clean && moon test src/jsonld --deny-warn`（仓根执行）
- **target**：**显式 `--target native`**（不跟随 moon.mod preferred_target
  ——preferred_target 变更不得静默改复核面口径；moon.mod 当前值 = native 仅
  为注记非依据）
- **冷缓存**：moon clean 后首跑（含 registry 依赖解析面）
- **通过口径**：expand 套件 pin `plain 385 / deferred 0` + toRdf 套件 pin
  `plain 467 / deferred 0` + flatten 套件 pin `plain 56 / deferred 2` +
  对账三件套（interface_gate/gen_gate/j4_reconcile）
  + 全目 64 测试绿（2026-09-29 flatten 收官批实测；62 = J5 首役基线 →
  +1 flatten harness → +1 双射判定器自检）
- **变更敏感性**：套件文件/引脚数/表行任一变更 ⇒ 本钉作废须重钉（版本钉的
  维护义务随 J5 归复核面）。
- **缺口解释表三分类钉（J5 开工前置）**：复核面的缺口逐条归三类，**禁止
  无类缺口**——「设计如此」（范围/兼容性裁决，注裁决出处：§1 范围/套件
  oracle/分叉账）/「未实现」（应终于落码的面，注立案去向）/「依赖外」
  （超出本仓可达面，注依赖物）。**零 deferred ≠ 零缺口**——deferred 只数
  套件内未迁例；套件外的面（compact/flatten/frame/remote-doc 等）与本实现
  的边界缺口全走本表。


### 8.38 复核表（JSON-LD 一致性面；2026-09-29 基线 = §8.37 钉版本）
| 面 | 套件规模 | 状态 | 判定通道 |
|---|---|---|---|
| expansion | 385（正 276 / 负 109） | ✅ **385/385 全 plain** | suite_expand_test pin（deferred=0）+ 值级对拍 |
| toRDF | 467（正 345 / 负 106 / 句法 16） | ✅ **467/467 全 plain** | suite_tordf_test pin + 判定器（迷你 N-Quads 解析 + 集合同构） |
| compact | 246（正 229 / 负 17） | 🚧 **145/246 plain**（正 130 + 负 15）/ deferred 101 在册 | suite_compact_test pin（deferred=101）+ canonical_for_suite 直比 + bnode 双射兜底 |
| flatten | 58（正 57 / 负 1） | ✅ **56/58 plain**（正 55 + 负 1）/ deferred 2 在册 | suite_flatten_test pin（deferred=2）+ canonical_for_suite 直比 + bnode 双射兜底（isomorphic_for_suite——判定器自检四钉） |
| fromRdf | 54 | ❌ 未实现 | ——（§8.39） |
| html | 50 | ❌ 未实现 | ——（§8.39） |
| remote-doc | 18 | ⭕ 依赖外 | ——（§8.39：HTTP fetch 面） |
| framing | —— | ⭕ 依赖外 | ffdb326 快照**不含** frame-manifest（快照边界，非本实现缺口） |
| 对账三件套 | —— | ✅ 62/62 | interface_gate（表 handler↔mock）+ gen_gate（重生成逐字节）+ j4_reconcile（路由/步骤/iri_rules 行为+值级） |
| 判定器自检 | —— | ✅ 7 件 | tordf_judge_test（转义/解析/同构语义正反例 + 套件文件自同构） |
| 预载通道 | —— | ✅ | loader_preload_test（BFS 预载 + join 键一致） |

基线复核命令见 §8.37（clone 任意路径 / moon clean / --target native / deny-warn）。

### 8.39 缺口解释表（三分类钉——零 deferred ≠ 零缺口；2026-09-29）
**「设计如此」**（范围/兼容性裁决，注出处）：
1. compact 246 例——**已立案已开工**（2026-09-29 首波 98/246 plain——
   开工前置钉 §8.41 + 首波实录 §8.42；deferred 148 缺口三分类在册）
2. @reverse 展开保形（非 REC 反转）——t0042 套件 oracle（同形异判表
   「oracle > 规范字面」族）
3. JCS 键序码点序（非 RFC 字面 UTF-16 码元序）——#tjs13 套件 oracle（同族）
4. 语言标签大小写从严——canonical_for_suite 不做大小写归一（现役从严注记）
5. keyword_dispatch 9 行 handler 指向 pending 桩（真落点 = expand_object
   内联臂）——J4 分叉账非红判据三条管辖（spec §5.2）

**「未实现」**（应终于落码的面，**逐条立案**——禁止无立案缺口；
  优先序（用户令 2026-09-29）：flatten → compaction → framing →
  canonicalization，性能优化缓打——flatten 已收官（§8.40）、compaction
  已开工（§8.41））：
6. flatten 58 例——**已立案已收官**（2026-09-29：56/58 plain——正 55 +
   负 1；deferred 2 在册：t0044 = compact 前置随 compaction 面解、
   tin06 = @nest 深研；落成实录见 §8.40）
7. fromRdf 54 例——**已立案不排期**（RDF → JSON-LD 反向；可借力 src/ttl
   解析面，跨仓复用见 §8.3 边界）
8. html 50 例——**已立案不排期**（依赖 HTML 解析面，本仓无此依赖，需引
   解析依赖后再议）

**「依赖外」**（超出本仓可达面，注依赖物）：
9. remote-doc 18 例——HTTP fetch 语义/状态码/重定向/Content-Type 协商
   （套件 README 明示依赖 HTTP 行为；本仓无网络面）
10. framing 面——**勘定修正（2026-09-29）**：json-ld-api 套件（ffdb326
    快照 + README 全文）**设计上不含 framing 测试面**（目录/清单全无，README
    仅保留 flattening/framing 的比对注记）——framing 上游另立 REC 与套件。
    非拉取范围问题；若做 framing 须另引 json-ld-framing 独立套件（依赖外
    新增，立案不排期）
11. **依赖外·复现环境三锚勘定（2026-09-29 拆分，三者漂移理由不同）**：
    ① **套件语料锚**——ffdb326 + SHA256SUMS 2626 件（语料变 = 判定语料变，
    单独钉于本节头）；② **mooncakes 依赖钉**——moon.mod import 版本行
    （本实现面实际 import：moonbitlang/async@0.21.0 + core（工具链捆绑）+
    bitbang/fsm 本仓包；thy1016/moonttl@0.2.2 等其余 import 行与本实现面
    无关——src/jsonld 未引用）；依赖 API 变 = 行为面变；③ **工具链锚**——
    moon 0.1.20260920 (914d7da) + 捆绑 core：**JCS 数值词形/行为语义随
    core**（Double 显示即 ECMAScript 形的实证面），工具链升级须重跑复核面
    全量（§8.37 复现命令）


### 8.40 flatten 开工钉（2026-09-29 实证定案；已立案已开工）
- **输入/输出**：输入 = 原文档（含 @context 原文形）；输出 = **展开形节点
  数组** `[{node},...]`——**无 @context 保留、无压缩**（#flatten-0002-out
  实证：全 IRI 键/`@type` 数组/值对象形）
- **与 expansion 的关系** = expansion **全链**（context 处理 → 展开）→
  节点字典（同 id 合并——F2 预合并语义同源复用）→ 枚举。**引擎三机制
  已就绪**：自由浮动弃（#flatten-0001 oracle：@id-only 未引用节点 → `[]`）、
  同 id 合并（F2）、数组逐项值对象（term5: [50,51] → 两个独立值对象——
  非 @list，实证）
- **词形细节**（样本实证）：数值/布尔 raw 保形进 `@value`；`@index`/
  `@type` 照展开形
- **选项**：specVersion ×13（mode 门）；compactArrays=false ×1（#t0044——
  context 保留+压缩形 = compact 前置实证，deferred 在册 §8.39）；base ×1
- **负例**：te001（1.1 面「Conflicting indexes」）——**已检出转正**
  （2026-09-29 收官批）：双件合力——F2 合并面 @index 冲突检测（同 id 双
  @index 不等 = colliding indexes 错，nq_merge_same_id Result 化）+
  free-floating 豁免 @index（弃则冲突不可见——oracle 定案，expand/toRdf
  套件均无此形在册案例，零回归面）

#### 8.40.1 flatten 收官批（2026-09-29——52/57 → 56/58 plain，deferred 2）
- **转正四件·机制各一**：
  1. **t0038/t0045 = 判定器双射兜底件**：`isomorphic_for_suite`——直比
     不过时 bnode 词面升为存在变量，存在标签双射 f 使 relabel 后规范形
     逐字节相等 ⇒ 同构。词面位三钉（flatten 输出形）：谓词键位 / "@id"
     值位 / "@type" 数组串值位；**"@value" 字面量串不重标**。标签数 > 8
     直接 false——**8 是排列数工作界，非经验值**：回溯最坏 = n! 次全文档
     重标规范渲染，8! = 40320 次为可接受上界；套件实测最大 4 标签（#t0038，
     24 排列），8 留 4 倍标签余量。自检四钉：对调同构 ✓ /
     @type+谓词键位 ✓ / 字面量不重标（异文即异构）✓ / 结构异构否 ✓
     （suite_flatten_test 判定器自检件）
  2. **t0046 = 相对 IRI 保形**：flatten_term 有词面恒保留（@base null 下
     "0"/"" 恒词面——base 解析已在 expansion 全链完成，此处无第二次解析
     面）；无 id 方生新 bnode
  3. **te001 = colliding indexes 检出**（见上负例条）
- **维持 deferred 2（在册 §8.39）**：t0044 = compact 前置（compactArrays
  触发 context 保留+压缩形）；tin06 = @nest 深研（author 包装节点被 data
  值吸收——base/9 合并面，非双射可解的结构差）
- **判定口径**：canonical_for_suite 直比 → isomorphic_for_suite 双射兜底
  （harness 接线；直比差异保留报错文）

### 8.41 compaction 开工前置钉（2026-09-29 两钉定案；已立案开工——优先序第二环随 flatten 收官解锁）

**钉一 · 输入/输出/关系**：
- **输入** = 原文档原文形（可含 @context 压缩形——先过 expansion 全链）+
  **active context**（套件经 manifest `context` 字段供给——246/246 全本地
  文件零远程；API 调用面 = 显式入参）
- **输出** = 压缩形 JSON：`@context` 键（active context 发射——223/246 例
  期望形带此键）+ term 键（inverse context 词选择）+ 值塌缩形
  （compactArrays 数组塌缩 / 值对象压缩 / @type 压缩）
- **与 expansion 的关系** = **逆面**（同 ctx 下 expand∘compact 保形对拍
  面）；**与 flatten 的关系 = 无前置依赖**——REC compaction 逐值递归、
  无节点字典面；**F2 禁复用**（12 例重复 @id 输入按不合并保真——勘定
  在册，flatten 的合并语义在此反而错）
- **判定通道** = canonical_for_suite 直比 + isomorphic_for_suite 双射兜底
  复用（bnode 输入面标签序差）

**钉二 · 246 例分组勘定**（manifest @ ffdb326 逐例实测，2026-09-29）：
- **总构成**：229 正 + 17 负；specVersion 1.1 ×164 / 显式 1.0 ×13
  （t0038/t0075/t0106/te001/tep05-07/tep10-15/tp001）；compactArrays ×3 /
  base ×3 / compactToRelative ×1；context 引用 246/246 全本地
- **依赖 framing：0**（全套件无 @frame 面——与 §8.39 条 10 上游分立一致）
- **依赖 flatten：12 例警示位**（输入递归重复 @id——按 REC compaction 不
  合并，compaction 通道须保真不复用 F2；顶层裸重复 0）
- **纯 compaction：234 例**——增量面 = 压缩序列化器（inverse context /
  term 选择 / 容器逆形 / 数组塌缩 / @nest / 值压缩）；expand + context
  处理面均已就绪（385/467 全绿）
- **面内特征分布**（施工面宽度）：容器逆形 117 例次（@graph 27 / @index 26 /
  @set 23 / @list 20 / @id 19 / @type 12 / @language 11）；@nest 13；
  expect 带 @graph 键 40；输入已展开形 168 例
- **负例 17**：16 例 = context 处理面错误码复用（invalid term definition
  ×4 / invalid container mapping ×4 / protected term redefinition ×2 /
  invalid @prefix value / invalid @nest value / invalid @version value /
  invalid context nullification / IRI confused with prefix / processing
  mode conflict）+ 1 例 compaction 特有（"compaction to list of lists"）

### 8.42 compaction 首波实录（2026-09-29 开工批；98/246 plain——正 83 + 负 15）
- **落码面**（compact_standard.mbt + engine 入口 `compact_document`）：
  输入原文（expansion 全链）+ context 文本（process_context）→ 压缩序列化。
  顶层形三钉（0 → {} / 1 → 单对象 / n → @graph 包裹）；@context 键 = 原文
  逐字发射（223/223 实证）、context 空不发射（6 例 = ctx {} 族实证）
- **compaction 机制**（J6 首波定案——后续批次引用锚；逐族 oracle）：
  1. **值感知 term 分选**（两遍 = bare_fit 吸收形优先、object_fit 值对象形
     次之、残余落前缀/相对词兜底键）——同 IRI 多 term 按值拆键：#t0015 五
     term 归组 / #t0006 datatype 失配 term 弃用 / #t0002 纯 term 容
     datatype·language 值对象（重展开安全 = 钉死在对象内）
  2. **语言态对齐裸形**：值语言 == context 缺省语言 → 裸值（重展开带回同
     语言安全）；纯串无修饰且缺省在场 → 对象形也不安全（分选层拒）
  3. **IRI 压缩四步**：精确 term → 最长前缀 compact IRI（前缀资格 = @prefix
     显式 true 或**简单 string 形**缺省——map 形缺省 false，#tp001 oracle，
     新增 `simple_form` 位）→ @vocab 相对词（仅谓词/类型位——@id 值位禁，
     #t0021 oracle）→ base 相对化（段界对齐，compactToRelative 门）
  4. **@id 值位词表门**：exact-term 塌缩禁（值位重展开不走词表——#t0060
     oracle："Bar" 保全 IRI）
  5. **@reverse 正向提升**：reverse term 匹配（td.reverse 判定不论 iri）→
     普通属性；无匹配 → "@reverse" 包裹保形（#t0033/#t0050 oracle）
  6. **@nest 重嵌**（TermDefinition 新增 `nest` 承接位）：td.nest 组账出
     "@nest" 键（#tn001 oracle）；别名校验（非关键字值须在册 term 且
     iri=@nest——#ten01 oracle）+ 1.0 门（@prefix/@nest 系 1.1 特性 =
     invalid term definition——#tep07/#tep09/#tep10 oracle；带 ":" 的
     term 名 + @prefix:true 同禁）
  7. **@list 吸收 + @set 保形 + 数组塌缩**（compactArrays 门）+ 值去重；
     1.0 嵌套 list = compaction to list of lists 错（#te001 oracle）
  8. **关键字别名键**：@id/@graph 键走 term 词形（#t0008 "uri" / #t0014
     "data" / #t0052 "graph" oracle）；**@included 出键**（#tin01 oracle）；
     **@json 值直出**（#tjs07 oracle——容器/塌缩不包 JSON 原值）
  9. **容器逆形映射归组**（役2——详钉 §8.43）：compact_map_entry（fit+子键+
     键化成员剥离一体，四类差异表见 §8.43）；@none 兜底别名感知（#tm012）
  10. **scoped 双链分立 + shaping td 裁量**（役3——详钉 §8.44）：type-scoped
     只作键名 / property-scoped 全参与（#tc009 vs #tc013 同形异判对，入
     同形异判表「scoped 来源分叉族」）；outer 同名全权、scoped-only 剥成形
     属性保 local_context；@vocab 型塌缩 vocab 旗
- **选项面**：JsonLdOptions 新增 `compact_arrays` / `compact_to_relative`
  （REC 缺省均 true；36 构造点编译器驱动同笔补）
- **负例 15/17**：16 例 context 处理面复用检出（其中 tep07/09/10、ten01 为
  本批新增校验）+ LoL 1 例；余 2 = te002（IRI confused with prefix——歧义
  判定细研，涉共享展开面风险）、tpr03（type-scoped 保护重定义——scoped
  保护面随 scoped context 压缩面同批）
- **deferred 148 缺口三分类**（§8.39 管辖）：
  - **未实现·已立案**：容器逆形分组 68 例次（@index 26 / @id 19 / @type 12 /
    @language 11——tc/tm/tpi/tla 族）；scoped context 压缩面（type-scoped /
    property-scoped term 选择——tc001-028 族）；@nest 链式/别名细化（tn002-011）；
    方向面（tdi01-07）；@graph 容器次级形（tp002-007）；@included 容器形；
    t0007（@id-term 串塌缩键面——重展开安全判定细研）
  - **依赖外**：0
  - **设计如此**：0

### 8.43 容器逆形四类钉（2026-09-29 役2 开工前置——成批机制，禁逐类修）

**共性**（四类同归一机制 = 分选层的「映射归组出形」扩展）：
- **路由位**：属性值分选时，候选 term 带**单映射容器**（@container 恰为
  @index / @id / @type / @language 之一——@set/@list 已在保形/吸收面、
  @graph 次级容器与复合容器 ["@graph","@index","@set"] 族不在本批）⇒
  该值不入「数组+塌缩」通道，入**映射归组**通道。
- **fit 门复用**：值仍须过 bare_fit/object_fit 判定才可归入该 term 的映射；
  不适值照旧落残余兜底键（分选语义零分叉）。
- **子键来源 = 值自身**：四类差异仅在「从值取什么作子键 + 剥什么」；
  归组、出形（Object）、@none 兜底、组内多值数组化（compactArrays 门——
  #tm012 单语言值裸形）全为共机制。
- **@none 兜底 = 别名感知**：无键化成员的值落 @none 键；@none 键词形 =
  别名 term 名（#tm012 oracle："none":"@none" → 键 "none"）、无别名落
  "@none" 字面（#tm017 oracle）。
- **子键词形旗**（与 IRI 四步的关系）：@id 键 = @id 值位旗（exact 禁 /
  vocab 禁 / 前缀+base 可——#tm005 "ex:foo"）；@type 键 = 类型位旗
  （vocab 可）；@index 键 = 原文位；@language 键 = 原文位。

**差异**（四类还原规则，逐类 oracle）：
| 容器 | 子键来源 | 值剥离 | oracle |
|---|---|---|---|
| @id | 值节点的 @id（压缩词形） | **@id 整剥**（键即身份——tm001/002 值无 @id） | #tm001/#tm002/#tm005 |
| @type | 值的**首个** @type（压缩词形） | **首 type 剥、残余留**（tm004 值仍带 @type bar） | #tm003/#tm004 |
| @index | 值的 @index 原文 | **@index 剥**；无 @index → @none | #tm006 族 |
| @language | 值语言原文 | **语言剥 → 裸串**；无语言 → @none | #tm012/#tla01 |

**与既有机制的关系**：
- 分选层：映射容器 term 与普通 term **同候选序竞争**（值 fit 映射容器即
  归组——一个属性可同时出映射组与普通组/兜底组）。
- 值渲染：映射值内部复用 compact_value_jv / 节点递归，仅追加「键化成员
  剥离」后处理（@type 残余 = types[1:] 浅拷贝出形）。
- @set/@list 保形/吸收面不动；复合容器（@graph 次级 + @set 组合——
  #tm017 虽 @none 形可部分对拍，仍整族 deferred 待 @graph 容器批）。
- **@index mapping 面（#tpi01-06，td "@index":"prop" 属性化索引）不在本
  批**——还原 = 按属性值归组且值保 prop 属性（#tpi02 实证），与四类子键
  来源不同源，单独立批。

#### 8.43.1 容器逆形批落成（2026-09-29 役2；98 → 123/246 plain，+10 正例）
- **成批机制**（一机制四类——compact_map_entry：fit + 子键 + 键化成员剥离
  一体；分选层映射归组路由 + 映射出键）：§8.43 钉全数兑现
- **转正 10 例**：tm001-005（@id/@type map——子键词形旗/剥形/残余留）、
  tm006-009（@index map——含 @none 兜底与 index 清除副本裸形）、
  tm012（@language map + @none 别名键）族
- **维持 deferred**：@graph 次级容器/复合容器族（tm013-023 整族）、
  @index mapping 面tpi01-06（属性化索引——子键来源不同源，单独立批）、
  tla01（语言敏感 list 分选——list 值的语言态适配细研）、scoped 压缩面
  （tc 族）、te002/tpr03（前账）

### 8.44 scoped context 压缩面（2026-09-29 役3；123 → 132/246 plain，+9 零回退）
- **机制**（双链分立——#tc009 vs #tc013 同形异判对定案）：
  1. **type-scoped 链**（`compact_apply_type_scoped`）：节点 types 依次命中
     带 local_context 的 term（词表候选序）套用（type_scoped 旗）——产出的
     term **只作键名选择**；datatype/container/language **不参与值成形**
     （#tc009 oracle：type-scoped @vocab term 的值保持 {@id} 对象形）
  2. **property-scoped 链**（compact_value_item 头部）：选中 term 的
     local_context 在**节点有效链之上**套用（property_scoped 旗）——值渲染
     全走此链（#tc001 oracle：foo 子节点 bar term 可选；#tc013 oracle：
     bar 内 baz @vocab 型塌缩）
  3. **shaping td 裁量**（分选层）：outer 同名 term 全权；scoped-only term
     剥 datatype/container/language（不作值成形）、保 local_context
     （property-scoped 链照走——#tc013 bar 即 scoped-only + 链）
  4. **@vocab 型塌缩词形旗**：@id 型 = vocab 禁、@vocab 型 = vocab 可
     （#tc013 oracle："buzz"——vocab 拼回重展开同形）
- **转正 9 例**：tc001/002/003/005/006/010/013/019 + **tpr04**（property-
  scoped 保护重定义——套用面落地后自然闭合）
- **维持 deferred（114 在册）**：
  - **nullification 族 tc014/tc018——定性 = 影响（非分叉）**：compact
    oracle（tc014-out 键 "p" vocab 相对词 + @type "Type"）实证引用实现
    [null] 空化后 **@vocab 存续**（term 存续未证——"Type" 可由 vocab 相对
    得）；本实现 process_context [null] 清 vocab（expand 385 绿面下无在册
    oracle 钉 vocab 存续——**共享面潜在缺口**，影响面 = process_context 的
    [null] 臂）。修法须 REC 字面核对 [null] 语义后动共享臂（涉 expand 全绿
    面，禁顺手修），单独立批
  - 其余：@graph 次级容器/复合容器族、@index mapping（tpi）、tla01（语言
    敏感 list 分选）、te002/tpr03

### 8.45 @graph 容器批开工钉（2026-09-29 役4 前置——与役2 的关系界定）

**关系 = 役2 的共机制延续 + 独立出形面**（非混批）：
- **延续面（共机制直接复用）**：映射归组账/出键/组内塌缩（compactArrays 门）/
  @none 别名感知兜底/子键词形旗——全沿 §8.43 共性；路由位同在属性值分选层。
- **独立面（出形不同源，故单独立批）**：
  1. **值形态不同**：役2 四类的值 = 节点/字面量（单值出形）；@graph 容器的
     值 = **图载体节点**（`node.graph` 在场）——出形 = **图内容数组**（内容
     节点逐个压缩成数组，非单值）。
  2. **键化对象不同**：役2 子键从值本身取（@id/@type/@index/language 成员）；
     本批键化对象在**图载体**上（node.id / node.index），且由**次级**决定。
- **「次级」定义**（存储形 = 展开侧同款，expand_standard 3651-3666 行）：
  组合容器 `[@graph, X]` 中 @graph 定**值形态**（图载体）、X 定**归组键**——
  X ∈ {@id, @index} 为次级；**@set 不占次级**（只定保形——数组恒保，#t0080
  展开侧同款裁断）；裸 @graph = 次级 None（值 = 图内容数组直出）。
  TermDefinition 存储形：container = Some(Graph) + graph_secondary =
  Some(Id|Index)|None。
- **oracle 形钉**：#tm017（[@graph,@index,@set]——无索引 → "@none" 键、值 =
  内容数组恒保形）；#tm020/#tm022（**type map 串塌缩**——属役2 机制补丁随本
  批：Type map 值剥首 type 后 id-only ⇒ 串塌缩**无条件**（不要求 td @type；
  vocab 旗仍随 td——tm020 base 相对 / tm022 vocab 相对））
- **deferred 底账**：tpi 属性化索引、tla01 语言敏感 list、nullification 族
  （§8.44 定性 = 影响）、te002 不在本批。

#### 8.45.1 @graph 容器批落成（2026-09-29 役4；132 → 145/246 plain，+13 零回退）
- **落码**（§8.45 钉兑现）：graph 容器路由（图载体值 → 内容数组出形）+ 次级
  键化（Id = node.id @id 位旗词形 / Index = node.index 原文 / None = 数组
  直出）+ @none 兜底（#tm017）+ **type map 串塌缩**（役2 机制补丁随批——
  剥首 type 后 id-only 无条件串塌缩、vocab 旗随 td：#tm020 base 相对 /
  #tm022 vocab 相对）
- **转正 13 例**：tm013/015（@id/@type map @none 兜底——役2 机制现成即过）、
  tm017/021/022/023（graph 容器/串塌缩）+ t0078/0082/0086/0087/0099/0101/
  0102/0103（graph 容器 t 系族——路由位落地后随批闭合）
- **维持 deferred（101 在册）**：tp003（前缀 gen-delim 边界——term 名尾冒号
  的 compact IRI 资格，IRI 压缩面细化）、tpi 属性化索引、tla01 语言敏感
  list、nullification 族（§8.44 定性 = 影响）、te002/tpr03
