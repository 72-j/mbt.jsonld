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
`emit_jsonld_gen`；统一入口落 src/fsm，低耦合只依赖通用 `moonbit-community/toml` 库，不碰 FsmIR）。
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
分叉轴后再落码；新增分叉对入本表。**族的归族维度统一入册**（每族一轴——
族头括注；行级「分叉维度」列 = 轴内的具体分叉点）。**轴的选择依据** = 对内
最小差异属性：逐对勘定「输入保持同形时**唯一翻转判定的属性**」，该属性即
轴——@vocab 族对内唯一翻转属性 = processingMode/specVersion（#t0092[1.1]
vs #t0115/#t0116[1.0] 同 vocab 输入异判定）；@value:null 族 = 值对象形态与
挂载辖域；scoped 族 = 上下文来源位；权威位族 = 判定依据层（规范字面 vs
套件 oracle）。禁按主题归类定轴（主题相近判定同向者不成族）：
| 实例对 | 分叉维度 | 分叉轴 | 判定差异 |
| #t0003 vs #t0004 | 形态分叉 | 值形态（null vs 空数组字面值） | null 值属性整体丢弃；空数组字面值属性保留（"set1": []——同文档两组键并存） |
| #tli01 vs #ter24/#ter32 | specVersion 分叉 | processingMode/specVersion | 同输入（@list 嵌套）：1.1 允许保留 / 1.0 list of lists 禁止 |
| **@vocab 分叉族**（三对归组；族维度 = **specVersion/处理模式**） | | |
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
| **@value:null 分叉族**（三对归组；族维度 = **值形态/辖域**；2026-09-28 并入 #t0014 辖域行） | | | |
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
| **oracle > 规范字面 分叉族**（三例归组；族维度 = **权威位**——规范字面 vs 套件 oracle；2026-09-29 收录两例） | | | |
| #tjs13 vs RFC 8785 §3.2.3 字面 | 键序定义分叉 | JCS 键序：套件 oracle = **Unicode 码点序**（U+F8DF < U+1F602）vs RFC 字面「UTF-16 码元序」（D83D < F8DF） | 码点序胜出——nq_key_compare 逐码点自实现（const §5 String::compare 假序同日禁用） |
| toRdf @reverse vs REC §6.3 反转形 | 展开词形分叉 | 引擎 = **t0042 保形**（@reverse 映射保留）vs REC 字面反转形（node 获反向属性） | 保形胜出——reverse 批 oracle 沿袭；J4 fixture 首写按 REC 记忆错一处实证 |
| flatten te001 vs free-floating 字面弃置 | 弃置位分叉 | free-floating（@id-only 弃）是否豁免 **@index**：oracle 要求 @id+@index 裸节点**必达合并面**（te001「Conflicting indexes」负例——弃则冲突不可见，负例永不可红） | **@index 豁免胜出**——is_free_floating 增 `index is None` 位；expand/toRdf 套件无此形在册案例（零回归面实测） |
| framing wrap 三分 vs REC frame() 字面 | 展开包裹分叉（**processingMode × 匹配数**；2026-10-01 役49 收录） | 1.0 恒 `@graph` 包裹（t0001-09）；1.1：空⇒`@graph:[]`（t0003）/ **单⇒解包直出**（t0023/26/31/32/34/35）/ 多⇒包裹（t0033） | oracle 胜出——1.1 单解包 = compaction compactArrays 单节点解包行为经 frame() 管线的显形。**同判两修史**：役47「恒包裹（空亦包）」与 §8.96「恒包裹修正」皆被判错再修——**前判错根因 = 版本没分**（前两批判定面只进 1.0 oracle：t0001/03/04/05/09 全 1.0），表症 = 「单匹配」情况未单独成例进面；役49 1.1 oracle 进面才定三分 |
| **scoped 来源分叉族**（族维度 = **scoped 来源**——type-scoped vs property-scoped；2026-09-29 役3 收录） | | | |
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
| compact | 246（正 229 / 负 17） | 🚧 **245/246 plain**（正 228 + 负 17 全负例入 plain）/ deferred 1 在册 | suite_compact_test pin（deferred=1）+ canonical_for_suite 直比 + bnode 双射兜底 |
| flatten | 58（正 57 / 负 1） | ✅ **56/58 plain**（正 55 + 负 1）/ deferred 2 在册 | suite_flatten_test pin（deferred=2）+ canonical_for_suite 直比 + bnode 双射兜底（isomorphic_for_suite——判定器自检四钉） |
| fromRdf | 54 | ❌ 未实现 | ——（§8.39） |
| html | 50 | ❌ 未实现 | ——（§8.39） |
| remote-doc | 18 | ⭕ 依赖外 | ——（§8.39：HTTP fetch 面） |
| framing | 92（正 89 / 负 3，官方套件在仓 @ 3bf782ba） | 🚧 **55/92 plain**（役52 收割：graph 族 + 别名 reverse + 哨兵修；deferred 37 逐簇在册 §8.102-108 系） | suite_frame_test pin（43+49=92 闭合）+ canonical 直比 + bnode 兜底 |
| 对账三件套 | —— | ✅ 62/62 | interface_gate（表 handler↔mock）+ gen_gate（重生成逐字节）+ j4_reconcile（路由/步骤/iri_rules 行为+值级） |
| 判定器自检 | —— | ✅ 7 件 | tordf_judge_test（转义/解析/同构语义正反例 + 套件文件自同构） |
| 预载通道 | —— | ✅ | loader_preload_test（BFS 预载 + join 键一致） |

基线复核命令见 §8.37（clone 任意路径 / moon clean / --target native / deny-warn）。

### 8.39 缺口解释表（三分类钉——零 deferred ≠ 零缺口；2026-09-29）
**「设计如此」**（范围/兼容性裁决，注出处）：
1. compact 246 例——**已立案开工中**（2026-09-29 廿一役 215/246 plain——
   开工钉 §8.41 + 首波 §8.42 + 役2-23 实录 §8.43-§8.62；收官清点 §8.51
   后 graph 簇 + scoped 边界 + 分选精化续批清空 46 例；deferred 31 逐簇在册）
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
    新增，立案不排期）。**勘定更新（2026-10-01 §8.93 前置勘定）**：官方
    w3c/json-ld-framing 套件实网可达（92 例、W3C S&DL 许可、三查全过）——
    **依赖外立案解除，改「已勘可开工」**（判定面 = 官方 92 例对拍）；
    排期/开工待用户令
11. **依赖外·canonicalization 套件**（2026-09-29 役10 勘定，同 framing
    款条 10 前例）：ffdb326 快照无 RDF Dataset Canonicalization 测试面
    （README 仅 JCS 注记，toRdf 面 nq_jcs 已落）——上游 W3C rdf-canon
    REC 与套件另立。**双路线判据（2026-09-29 定案，防「留案」滑向
    无限期拖延）**：**路线 A（引依赖）**——判据 = 依赖物可得（rdf-canon
    套件引入境测可跑：manifest + SHA256SUMS 齐全、许可兼容）⇒ 套件
    判定面即立，算法实现直接对拍；**路线 B（自建）**——判据 = 路线 A
    不可得时的规范驱动自落码，判定面 = **自建对拍双件**（① URDNA2015
    规范附录验证向量逐例 ② 与已知实现（ruby json-ld/ietf 实现）交叉
    抽样对拍）——**无自建判定面不得开工**（判据 = 无对拍即无通过口径，
    违反 J5 缺口三分类「零 deferred ≠ 零缺口」的对账前提）。触发 = 用户
    令或 VC 需求（优先序原判）。**择一流程（2026-09-29 役11 定案）**：
    第一步 **勘依赖可得性**（rdf-canon 套件可引入境测：manifest +
    SHA256SUMS + 许可三查）——可得 ⇒ 走路线 A；不可得 ⇒ 走路线 B，且
    **先建自建判定面再写算法**（对拍双件先行，禁「先写算法后补判定」
    ——无判定面的落码 = 无通过口径的黑箱）。「双路线」是**决策树**
    不是「两条都可选的并列项」——不做勘测就落码 = 违反本判据
12. **依赖外·复现环境三锚勘定（2026-09-29 拆分，三者漂移理由不同）**：
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
  11. **type-scoped 逆序套用**（役15——详录 §8.56；scoped 双链分立同族，
     §8.44）：@type 数组**倒序**逐个套 type-scoped context，先位类型后手
     胜（REC §6.1.2 步 12.8.1；#tc017 [Foo,Bar] Foo 胜 oracle）
  12. **shaping 取舍序**（役24——详录 §8.63；双链分立同族 §8.44）：同 IRI
     双定义（outer + type-scoped）时，scoped 定义 **datatype=@id ⇒ scoped
     全权**（type-scoped 定义对该节点就是全量定义——#tc007 oracle）；
     @vocab 型仍随 outer（tc009 不塌裁断——@vocab 传导需 @propagate，
     tc026 前置面）
  13. **数值/布尔语言免注**（役8——#t0015/#t0018 oracle）：raw 保形体
     （number/bool）不受缺省语言/方向注入——裸形判据只对串值做语言态/方向
     态对齐（串重展开会被注回，数值原样往返）；language 吸收 Null 臂
     render 侧同批补齐（bare_fit 有 render 无——判定树 Q1 钉不完整）
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
| @type | 值的**首个** @type（压缩词形） | **首 type 剥、残余留**（tm004 值仍带 @type bar）；**剥后 id-only ⇒ 串塌缩无条件**（vocab 旗随 td——tm020 base 相对 / tm022 vocab 相对）【役4 补全沿革：役2 钉未列此形——非漏实现已钉行为，系钉本身不完整，役4 随批补钉】 | #tm003/#tm004/#tm020/#tm022 |
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
  - **nullification 族——【役8 更正】tc014 除名**（根因勘定 = @type 值
    渲染链选择，非 [null] 臂：@type 值走 outer 链后 tc014 转正，未动
    process_context——役3「nullification 族含 tc014」定类有误，现更正；
    双链分立「type-scoped 只管键选择」的直接推论，见 §8.49 条 8）。残余
    tc018 定性改判**待证**：[null] vocab 存续问题在 tc014 转正后失去
    test-backed 证据（键渲染本就走 outer 链）——[null] 臂是否与引用有差，
    无在册 oracle 可判，降为「未证潜在」，非影响类实锤；修法纪律不变
    （动共享臂仍须 REC 字面核对 + 单独立批）
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

### 8.46 前缀 gen-delim 边界钉（2026-09-29 役5 前置——与 simple_form 的关系）

**定性 = 两条独立规则、同闸位串联**（非同一条规则的两种形态）：
- **simple_form 资格闸**（役1——定义形态轴）：哪个 term 可作 prefix **候选**
  ——简单 string 形缺省可、map 形缺省不可、@prefix 显式定夺。判据对象 =
  **term 的定义形态**。
- **gen-delim 词尾闸**（本批——映射词尾轴）：候选 term 的 **IRI mapping 尾
  字符**须 ∈ gen-delim（`:` `/` `?` `#` `[` `]` `@`，RFC 3986）方可出
  compact IRI。判据对象 = **mapping 的词尾形态**，与定义形态正交。
- **证据三件**（#tp003/#tp005/#tp006——首稿「串联」表述经探针精化，沿革
  如实）：tp003 简单 term mapping 尾 `'-'` → 不压缩（词尾闸约束**简单形
  隐式资格**）；tp005/tp006 **@prefix:true + mapping 尾 `'-'` → 照压缩**
  ——@prefix:true 是**显式豁免位**（两闸齐抬）。终版规则：@prefix:true 恒
  候选；简单形候选受词尾闸；map 形无 @prefix 不候选（#tp001）。
- **作用面 = 压缩侧 prefix 步**（compact_iri_word），**不动展开侧**
  expand_compact（compact IRI 解析是另一族规则——te002 挂账另涉）。

#### 8.46.1 gen-delim 闸落成（2026-09-29 役5；145 → 146/246 plain，+1 零回退）
- **落码**：compact_iri_word 前缀候选加映射词尾闸（mapping 尾 ∈ `: / ? # [ ] @`
  方可出 compact IRI；@prefix:true 显式豁免——规则终版见 §8.46 证据三件）
- **转正 3 例**：tp003（简单形落闸）+ tp005/tp006（@prefix:true 豁免——探针
  首跑回退此二例暴露首稿「串联」表述之误，精化为豁免位后全过）
- **过程**：match 作 `&&` 操作数须括号化（[3002] 第三度现形）；fmt 重排锚
  漂移两度——补丁全带 assert 锚 + grep 复核

### 8.47 tpi 属性化索引批开工钉（2026-09-29 役6 前置——与役2 @index 容器的关系）

**关系 = 役2 映射归组共机制的延续 + 独立子键来源**（同 arm 分叉，非混批）：
- **延续面**：出形（映射容器归组 + 组内塌缩 + @none 兜底）全沿 §8.43 共
  机制；路由位同在 compact_map_entry 的 Index arm。
- **分叉面（子键来源不同源——§8.43 已预注「单独立批」）**：
  - 役2 @index 容器（`td.index_mapping = None`）：子键 = 值的 **@index 成员**
    （展开期容器应用写入）——已落，本批不动。
  - 本批 tpi（`td.index_mapping = Some(prop_iri)`）：子键 = **属性位取键**——
    展开期索引被写成属性（index_mapping），值**不带 @index**。
- **oracle 形钉**（tpi01-06 逐例勘定）：
  1. **首值键化、残余留**（同 @type map 首键化同构——#tpi01/#tpi02）：子键 =
     index 属性**首个值**（字面量直取串；节点引用须可串塌缩——按 prop 自己
     的 term 定夺，#tpi03 @type:@id → base 相对词）；**残余值留**为 prop 属性
     （#tpi02 "prop":"foo" / #tpi04 节点引用残串）
  2. **不对称出形**（#tpi01 vs #tpi05）：**键化值** = 节点对象形（剥首索引值
     后纯 node 渲染，即便 id-only 不塌缩——#tpi01 `{@id:person/1}`）；
     **@none 组值** = 常规值压缩链（compact_value_item + 容器 term 的 td——
     id-only 串塌缩 #tpi05 数组串 / 带属态对象形 #tpi06）
  3. **不可串塌缩的索引值 → @none**（#tpi06 oracle——prop 无 term 定义时
     节点引用不塌缩 = 无键，prop 保 {@id} 对象形随值落 @none 组）
  4. **无 index 属性 → @none**（#tpi05）

#### 8.47.1 tpi 批落成（2026-09-29 役6；146 → 153/246 plain，+7 零回退）
- **落码**（§8.47 钉兑现）：compact_map_entry Index arm 分叉——
  `td.index_mapping` Some → 属性化索引分支（index_mapping 存**原始 term
  名**——用时期 expand_iri(vocab=false/docRel=true) 得属性 IRI，与展开侧
  同参；首值键化（字面量直取串 / 节点引用按 prop 自己的 term 定塌缩）、
  残余值留、无键全形落 @none、无属性 @none 走常规值压缩）
- **转正 7 例**：tpi01-06 全族 + t0112/0113（随批闭合）
- **deferred 93 在册**：nullification 族（tc014/tc018——影响定性 §8.44）、
  tla01（语言敏感 list 分选）、te002/tpr03、t 系杂族

### 8.48 tdi 方向批开工钉（2026-09-29 役7 前置——与丙批 @direction 的关系）

**定性 = 丙批方向机制在压缩面的逆用**（既非 compaction 的逆、也非 J3.4）：
- **与丙批的关系**：丙批（J2 系——ActiveContext default_direction /
  TermDefinition direction_mapping 三态）= **展开期方向注入**（context 方向
  态注入值对象 `@direction`）；本批 = **压缩期方向吸收**（值对象 `@direction`
  被 td/缺省方向态吸收成裸形——重展开注回同向即安全，同语言态对齐判据）。
  机制同源（direction_mapping 三态语义同一份）、方向相反（注入 vs 吸收）。
- **与 J3.4 rdfDirection 的关系 = 无**：那是 toRDF 序列化面（i18n-datatype /
  compound-literal 出账形），tdi 全族无一涉 RDF。
- **落码位四处**（compaction 机制节族）：
  1. bare_fit 增方向态臂（Set(d) 吸同向 / Null 吸无向 / None 吸缺省对齐——
     #tdi01 oracle：term5 @direction:null 吸无向值成裸串）
  2. compact_value_jv 裸形臂增方向对齐 + **@direction 别名键**（#tdi02
     oracle："direction":"@direction" → 键 "direction"）
  3. **List 方向选择**（#tdi03 oracle——同 IRI 双 list term 按首项方向分选
     foo_ltr/foo_rtl）
  4. **Language map 方向过滤**（#tdi04/#tdi07 oracle——方向合者入语言图成
     裸串、不合者落残余兜底键 vocab:label 值对象数组）
- **deferred 底账不变**：nullification 族 / te002 / t 系杂族。

#### 8.48.1 tdi 批落成（2026-09-29 役7；153 → 156/246 plain，+3 零回退）
- **落码**（§8.48 四落码位兑现 + 探针两轮精修）：
  1. bare_fit/object_fit **方向态总闸**（Set 吸同向 / Null 吸无向 / None 吸
     缺省对齐——方向不合者任何形不入 term，#tdi07 oracle：不合值落残余
     兜底键 vocab:label 值对象数组）
  2. compact_value_jv **direction 吸收臂** + 裸形臂语言/方向双对齐
     （#tdi01 oracle：term5 @direction:null 吸无向值）
  3. **List 方向选择**（#tdi03 oracle：同 IRI 双 list term 按首项方向分选）
  4. **Language map 方向过滤**（#tdi04/#tdi05/#tdi06 随方向闸闭合）+
     **@language/@direction 别名键**（#tdi02 oracle）
  5. **残余兜底 vocab 守门**（本属性有 term 组/映射组时禁 vocab 步——
     #tdi07 oracle：vocab 相对词撞 term 键）
- **转正 3 例**：tdi02/03/07（tdi01/04/05/06 随方向闸早批已过）
- **过程**：object_fit 缺方向闸一度让不适值成组（探针打点实证 fallback 未
  触发即组内出形——「打点定位 + 撤点收尾」标准动作复用）

### 8.49 杂族清点批落成（2026-09-29 役8；156 → 169/246 plain，+13 零回退）
- **七系统性点清点落码**（剩余 90 deferred 逐例 diff 勘定）：
  1. **数值/布尔语言免注**（#t0015/#t0018 oracle——raw 保形体不受缺省
     语言/方向注入，探针打点定位：JV-NOBARE 数值撞 @language 缺省）
  2. **language 吸收 Null 臂补 render 侧**（#t0015 term5——bare_fit 有
     render 无，「钉不完整」判定树 Q1 定类补齐）
  3. **@type 键别名路由 + @set 容器旗**（#t0022 "type" 键 / #t0105 恒数组）
  4. **@vocab 型塌缩 exact 开**（#t0054——"enum" 词表命中；@vocab 值位
     词表门开）
  5. **Language map index 闸**（#t0065——带 @index 值不入语言图落残余）
  6. **reverse 映射容器**（#t0036——@reverse + @container @index 键化出形）
  7. **@graph_set 保形位**（判定树 Q1 定类：[@graph,@set] 数组恒保 #t0078
     vs 裸 @graph @included 包裹 #t0109——展开侧「@set 不占次级」丢位，
     TermDefinition +graph_set 增量字段展开不读零行为面）
  8. **@type 值渲染走 outer 链**（#tc014——nullification 后 vocab 存续；
     type-scoped 只管键选择——双链分立同款；tc014 因此收复转正）
- **转正 13 例**：t0036/0054/0055/0056/0059/0073/0078/0104/0105/0109/0114/
  tc008/tc014/tc021（含两回退件收复）
- **deferred 77 在册**：nullification 族（tc014 已收复；tc018 等残余）/
  te002/tpr03/t0093（多顶层节点分裂面）/t 系杂族残余

### 8.50 三分类判定判据钉（2026-09-29 役9 收官清点前置——§8.39 三分类的判定判据成文）

**判据**（逐例定性须引判据 + 证据，禁凭感觉分类）：
- **设计如此**：判定依据 = **在册裁定文**（「oracle > 规范字面」族 /
  同形异判对 / §1 范围裁决）——本实现与规范字面或引用实现的偏离**已裁**
  且裁定在册；不修。反证义务 = 找不到在册裁定即不得入此类。
- **未实现**：判定依据 = **钉文 + oracle 要求成立**——行为在套件 oracle
  要求范围内且钉文在册（或钉不完整已补钉），实现未落；修法 = 落码
  （排期或立案注去向）。反证义务 = 钉文与 oracle 双双在册才入此类。
- **依赖外**：判定依据 = **依赖物清单**——行为所需面超出本仓可达
  （网络面 / HTML 解析依赖 / 上游分立套件）；不修（需引依赖再议）。
  反证义务 = 依赖物具名才入此类。
- 三类皆引不出判据 ⇒ 回判定树（const §6.2）重新定性（Q1 钉文 / Q2 已裁
  偏离 / Q3 共享面波及面），禁「其余归未实现」的兜底倾泻。

### 8.51 compaction 收官清点终账（2026-09-29 役9；169/246 plain——余 77 例逐簇三分类）

**三分类判定**（判据见 §8.50；逐簇引判据 + 证据）：**77 例全部 = 未实现**
（钉文 + oracle 要求成立、实现未落——逐簇机制注如下）；设计如此 0
（无在册裁定偏离）；依赖外 0（无依赖物缺口）。

| 簇 | 例数 | 构成 | 机制注（落码去向） |
|---|---|---|---|
| @graph 容器复合形 | 18 | t0076-0100 系（@id/@index 次级组合、图对象嵌图、@none 交叉） | graph 容器续批（§8.45 钉的次级组合全谱） |
| t 系值分选/键形细族 | 24 | t0004（@set 空数组）/t0007（id-term 键面）/t0015-0024（语言敏感 list 分选）/t0027（@set 多候选偏好）/t0037-0048（@reverse 残余+值分选）/t0057/0061（塌缩词形偏好排序——@vocab exact 优先）/t0065（@index×@language 交叉）/t0066/0110（base 文档位相对化）/t0106/0110（type-alias 容器异形）/t0111（@-形 @id 相对化） | 分选精化批 |
| tc scoped 残余 | 14 | tc004-026（嵌套 scoped 链、nullification tc018、保护面交叉） | scoped 面续批（tc014 已收复除名——§8.44 更正） |
| tn nest×容器交叉 | 4 | tn006-009（@nest + @index/@language 容器组账交叉） | nest 续批 |
| tm type map 变体 | 3 | tm007（键化值内层走键位 type-scoped 链）/018/019 | 容器续批 |
| tin @included 出形 | 3 | tin02（单值对象形）/04/05 | graph 容器续批 |
| tjs @json 判定 | 2 | tjs07/09（@type:@json 的 td datatype 存储形与直出闸对齐） | 容器续批细研 |
| ts/ttn 交叉 | 5 | ts001/002（@set 语义变体）/ttn01-03（type-scoped 值成形交叉——值对象形判定与 type-scoped 适配序） | 分选精化批 |
| 影响类纪律注 | 3 | te002（IRI 歧义——涉共享展开面）/tpr03（scoped 保护）/tpr05 | 判定树 Q3：动共享面须单独立批（const §6.2），非本套件批内可解 |

**账面闭环**：246 = 169 plain（正 154 + 负 15）+ 77 deferred（全部未实现、
逐簇在册）——零无类缺口、零凭感觉分类（§8.50 判据管辖）。

### 8.52 graph shaped 续批落成 + canonicalization 立案（2026-09-29 役10；169 → 195/246 plain，+26 零回退）
- **REC 判据入钉**（规范字面取证：JSON-LD 1.1 API §6.1.2 步 12.8.5/12.8.8 +
  §9.1 步 9.2——用户令 webReader 全文取回勘定）：
  1. **节点自身 @graph 关键词条 = as-array 恒真**（active property = @graph
     路不塌缩——#t0016 oracle 守卫；首版「单内容解包」误钉回退）
  2. **塌缩只在值位数组步**（single + compactArrays + 属性非 @graph/@set）——
     值位薄包装件 compact_node_graph_value_jv（#t0092/#t0094/#t0080/#t0083）
  3. **顶层级**：compact 输出数组（compactArrays=false 未塌）→ 包 @graph 键
     （§9.1 步 9.2——#t0091 oracle；首版空 {} 根因 = 分支缺口）
  4. **graph shaped 出形**：单内容节点对象 / 多内容 @included 包裹（容器直出
     简形——12.8.8.3，#t0077/#t0096/#t0109）；映射值路多内容保数组
  5. **graph_set 键化/裸出形恒数组**（#t0078/#t0082/86/87/99/101/tm017——
     @set 组合载体值已数组不再包，键化摊平）
  6. **@included 单值解包**（#tin02/04/05）+ 别名 @set 保形（#tin01）
  7. **allow_base 旗三剖**（IRI 压缩第四旗）：@vocab 型塌缩 = exact/vocab
     命中塌 + 前缀词步可 + **base 步禁**（#t0062/#t0063 oracle——绝对 IRI
     不因文档 base 相对化、"prefix:suffix" 前缀词可用）；@id 位 base 可
     （#t0066/#t0076——base 目录位边界）
- **转正 26 例**（零回退）：graph 簇 18 例全谱（t0076-0100 系）+ t0037/
  t0070/tc004/tc025/tin02/04/05/tm018/019/t0110
- **canonicalization 立案——依赖外（§8.50 判据，依赖物具名）**：ffdb326
  快照无 RDF Dataset Canonicalization 套件（目录/清单全无；README 仅 JCS
  注记——toRdf 面 nq_jcs 已落 J3.3）。上游另立 W3C rdf-canon REC 与套件
  （同 framing 款，§8.39 条 10 前例）；若做须另引依赖 + 算法面规范驱动
  自落码双路线评估，立案不排期
- **过程**：映射出键/reverse 出键两块被段切片手术误删（探针全量红名单 +
  三例空 {} 症状定位即建）——「段切片必须圈定唯一锚 + 落盘后 grep 出键块
  在场」教训入册；同名探针文件覆写循环两次——探针文件改名隔离（FINAL 独立件）

### 8.53 tc scoped 残余批开工钉（2026-09-29 役11 前置——与役3 的关系界定）

**定性 = 役3 双链分立机制的「边界延伸」，非新机制**：
- **延续面**：键选择链（scoped）/ 值成形链（outer + shaping td 裁量）双链
  架构照用（§8.44）；本批不新增链。
- **边界（役3 未达的残余形）**：役3 落地时只覆盖「节点 types 命中 term 带
  local_context」的单层 type-scoped 与「值 term 的 local_context」单层
  property-scoped；残余 14 例 = **多层链**（type-scoped 内再套
  property-scoped 的链式套用序 tc012/015/016）、**nullification 交叉**
  （[null] 空化与保护位同现 tc018/020/022-026）、**scoped 内容器/方向态
  与 役2/役7 机制的交叉**（tc004/007/011）——都是「同一双链在更深的组合
  下暴露的边界」，修法 = 链上补序/补旗，不另起机制。
- **nullification 纪律**（§8.44 更正版）：涉 [null] 臂共享面仍走影响类
  流程（REC 字面核对 + 单独立批）；本批只收「双链边界」可就地修的例。

#### 8.53.1 tc 残余批首波落成（2026-09-29 役11；195 → 198/246 plain，+29 累计零回退）
- **落码**（§8.53 钉的边界延伸两件）：
  1. **shaping 裁量精化**（#tc007/#tc012/#tc022/#tc023 oracle）：scoped-only
     td 的 datatype **@id 型保**（全 IRI 塌缩词重展开同形）、**带
     local_context 者保**（property-scoped 链定塌缩词——tc022 "Bar" 经链内
     exact）、其余剥（#tc009 @vocab 无链不塌——双链分立不破）
  2. **base 片段相对优先**（#tc015 部分——base 无尾 '/' 且 iri = base + "#…"
     ⇒ "#…" 形，先于目录位判定；嵌套节点层已闭合，**p 节点属值位的
     base 子树传导仍红**——双链分立的 base 传导边界，deferred 注记）
- **canonicalization 双路线判据**（§8.39 条 11 扩）：路线 A（引依赖）判据 =
  依赖物可得（manifest+SHA256SUMS+许可）；路线 B（自建）判据 = 自建对拍
  双件（规范验证向量 + 已知实现交叉抽样）——**无自建判定面不得开工**
- **deferred 48 在册**：tc011/015/016/017/018/020/024/026（多层链/
  @propagate 传导/base 子树传导——scoped 面深层，役11+ 续）、nullification
  族、te002/tpr03、t 系分选精化族

### 8.54 t 系分选精化批开工钉（2026-09-29 役12 前置——与首波值分选的关系）

**定性 = 首波分选骨架的「适配判据细化 + 候选偏好序」延伸**（非新机制、
非分叉）：
- **机制同源**：两遍 bare_fit/object_fit + 残余兜底骨架照用（§8.42 条 1）；
  本批不改骨架，只**细化 fit 判据**与**多候选偏好序**。
- **三类延伸**：
  1. **fit 判据细化**（值形态×容器交叉）：list 项语言态适配（#t0015/
     #t0018/#t0024——首波只做了方向态）、@set 空值数组出形（#t0004）、
     @index×@language 交叉 unfit 判定（#t0065——役8 已落闸，残余复核）
  2. **候选偏好序**（多候选同 fit 时选谁）：@vocab exact 塌缩词优先
     （#t0057/#t0061）、@set 多值偏好（#t0027）——首波候选序 = 容器缺省
     优先 → 名短 → 字典序，本批加**值形态适配强度**位
  3. **词形边界**（归 IRI 压缩面非分选）：base 文档位相对化残余
     （#t0066/#t0110）、@-形 @id 相对化（#t0111）、id-term 键面（#t0007）
- **与首波的关系钉**：首波钉「分选存在」（骨架）；本批钉「分选选得对」
  （判据与序）；两者同账不同粒度——落码时改 fit 函数与排序键，禁动
  骨架结构。

#### 8.54.1 t 系分选精化首波落成（2026-09-29 役12；198 → 199/246 plain，零回退）
- **落码**（§8.54 三类延伸的第一波）：
  1. **index 闸双 fit**（#t0065 部分——@index 值对象在无 index_mapping 的
     term 下 bare/object 两形皆拒；t0065 残余 = 闸后残余路径出形仍差
     一层（fallback 键词形），deferred 注记）
  2. **空值属性 + 容器 term ⇒ 空数组**（#t0004 myset2 []——mylist1 空
     @list 吸收路径已过，残余 = t0004 的 myset2 仍差（候选序取首 term
     的键词形），deferred 注记）
  3. **多值 @set 候选偏好**（#t0027 ✓——多值时 @set term 保形胜出，
     稳定分区前置）
- **转正 1 例**（t0027）；deferred 47

#### 8.54.2 残层收口（2026-09-29 役13；199 → 201/246 plain，零回退）
- **空 Set 出形**（#t0004 收口——myset2 [] ：空值属性 + 容器 term ⇒
  空数组出形，候选首 term 键）
- **index 闸判据合流**（#t0065/#t0030 双 oracle 合流定案）：@index 值对象
  的可入性 = **容器在场判**——容器在场（@language 图等，重展开丢/mangle
  @index）⇒ 两形皆拒落残余；容器缺席（无容器 term 的数组保 @index）⇒
  放行。首版「Index 容器豁免」为误判（t0030 的 term 本就无容器）
- **转正 2 例**：t0004/t0065 全收口；deferred 45

### 8.55 分选精化续批落成（2026-09-29 役14；201 → 203/246 plain，零回退）
- **落码五件**（§8.54 判据细化/偏好序/词形边界三类各中）：
  1. **vocab 撞词守门**（#t0043——suffix 为在册 term 时重展开撞词，跳过
     vocab 步保全 IRI；t0043 残余 = 输入双 name 属性的合并面，deferred 细研）
  2. **标量免注入 bare_fit**（#t0048 部分——number/bool raw 保形体不受
     缺省语言注入；t0048 残余 = propertyB/NoLang/LanguageNull 三候选同
     fit 的偏好序，deferred 细研）
  3. **@-词转义**（#t0111 ✓——"@special" 值位词形 "./" 前缀逃逸）
  4. **type-@set 1.0 门**（#t0106 ✓——1.0 模式数组塌缩不受 @set 容器约束）
  5. **单元素数组容器**（#ts001 展开/压缩两侧——["@list"] 等价裸形；
     ERR 已除，出形残余 deferred）
- **转正 2 例**（t0111/t0106）；deferred 43（t0043/t0048/ts001 残层注记）

### 8.56 type-scoped 逆序套用落成（2026-09-29 役15；203 → 206/246 plain，零回退）
- **REC 判据**（§6.1.2 步 12.8.1——@type 数组**倒序**逐个套 type-scoped
  context，**先位类型后手胜**——#tc017 oracle：types [Foo,Bar] Foo 的
  prop 定义胜出打 "prop":"foo"）。compact_apply_type_scoped 套用序由正改逆。
- **转正 3 例**：tc012（多 type-scoped 覆盖序）/tc017（数组 local context
  多链）/tc018（nullification+多链交叉——[null,{prop}] 形）
- **deferred 40 在册**：tc 深层（base 子树传导/@propagate）、t 系残余、
  te002/tpr03

### 8.57 t 系残余清点钉（2026-09-29 役16 前置——分组判据成文，禁凭感觉分组）

**分组判据**（逐例先归组再动手）：
- **可成批**：≥3 例同根因（同一 fit 判据位 / 同一 emit 位 / 同一闸）——
  一修多例，批立案（附同根证据：各例 diff 指向同一代码位）。
- **个案**：单例且根因独立（无同族可共享修法）——逐例立案，排期随缘，
  禁为凑批硬合。
- **依赖别的批**：根因落在另一主面（IRI 词形 / scoped 深层 /
  nullification REC）——挂靠主批账下，本批不动；挂靠关系必须显式
  （引主面 §节）。

### 8.58 t 系残余清点首波落成（2026-09-29 役16；206 → 208/246 plain，零回退）
- **分组清点**（§8.57 判据执行）：
  - **可成批 ✓**：@id/@vocab 双 term 值分选偏好（t0044/t0057/t0061 同根）
    ——**最短词形排名**（pass-1 多候选同 bare-fit 取塌缩词最短：exact 词 <
    base 相对 < 全 IRI）；t0089/t0026（无语言值辖域——language-null term
    确定性胜出，pre-map 扫描限定无语言值）
  - **个案**：t0007（**未实现**——值位 id-term 取舍：字串值经 @id 项塌缩
    词与 full-IRI 键，oracle 取后者；无在册裁定 = 非设计如此，实现未落 =
    非依赖外；判定树 Q1：钉文无此行为 ⇒ 补钉随批）、t0066/0110（base
    文档位多形态——目录/文件/query/fragment 各归各）、t0089 已收、t0106
    已收
  - **【役17 撤销】t0029/t0030 个案判断注销**：逐字符探针实证规范形已
    全同——役15 逆序套用顺手修平且已在册，「差异在深层」旧判断过时
    （过时判断须撤销条，ctx §3）
  - **依赖别的批**：tc007/011/015/016/020/024/026（scoped 深层——base 子树
    传导/@propagate）、te002/tpr03（影响类纪律）、tjs07/09（@json 判定）、
    tn006-009（nest×容器）、ts001/002（数组容器出形）、ttn01-03（type-scoped
    值成形序）、tla01（语言敏感 list）、tm007（type map scoped 值链）、
    tpr03（保护重定义交叉）
- **转正 2 例**：t0089（无语言值辖域）+ t0027 复核；最短词形排名转正
  t0057/t0061/t0044 部分
- **deferred 38 在册**

### 8.59 tc 深层批开工钉（2026-09-29 役18 前置——base 轨与役3 双链分立的关系）

**定性 = 役3 双链分立的「第三轨补全」，非新机制**：
- 役3 双链 = **键选择链（scoped）** + **值成形链（outer + shaping 裁量）**；
  本批补的是 **base 轨**——@id/词形的 base 相对化归属：
  **base 轨随 scoped 链**（节点自身 type-scoped @base 传导至本节点值位
  词形——#tc015 oracle：typed-base 下 "#typed-id" 片段相对）、**term/
  成形轨随 outer + shaping 裁量**（tc009 @vocab 不塌等裁决不变）。
- 三轨合记 = **键选 scoped / 词形 base scoped / 成形 outer**——双链分立
  的细化（base 从成形链拆出独立随键选链），非推翻非另起。
- **@propagate 面**（#tc026）：type-scoped @propagate:true 传导至嵌套节点
  的键选轨——是键选链的**传导半径**扩展，机制同源；与 base 轨分立落码。
- **nullification 纪律**照 §8.44 更正版：涉共享 process_context 仍单独立批。

#### 8.59.1 base 轨落码（2026-09-29 役18；套件净中性 208 持平）
- **value_chain 三处接入**（partition chosen/leftover/pre-map 扫描）：
  值位词形 base 相对化随节点自身 scoped 链（tc015 typed-base ✓ subject/
  base-id 片段相对闭合）；term/成形轨 outer 裁量不变（tc009 守卫复验 ✓）
- **tc015 残余定性**：typed/nested 值仍红——各值相对其**解析时 base**
  （typed 值→typed-base、nested 值→base-base），压缩期须**多 base 候选
  排名**（IRI 面深层），deferred 注记
- **净中性定性**：套件 208 持平零回退——base 轨为正确性补全（tc015
  部分改善），无 oracle 反证

#### 8.54.3 Null 吸收臂回补（2026-09-29 役19；208 → 210/246 plain，零回退）
- **根因**：役12 补的 language 吸收 **Null 臂被役13-18 间某次区段手术吞掉**
  （Set 臂在 Null 臂失——「段切片误删相邻块」⑦ 的变体：非相邻块、是
  **同段内的并列臂**）；bare_fit 侧 Null 判据在、render 侧吸收臂失 ⇒
  选得出 bare 渲不出裸形（t0089 s 值对象形）
- **回补**：Null 臂（language None + dir 合 ⇒ 裸串）；t0089 ✓ 全收口
- **deferred 36**：t0089 已收；余 = tc 深层（base 多候选/@propagate）、
  t 系值分选残余、te002/tpr03

### 8.60 vocab 前置重排落成（2026-09-29 役20；210 → 213/246 plain，零回退）
- **重排**：IRI 压缩四步序改 = exact → **@vocab 相对词** → 最长前缀 →
  base（vocab 步自 prefix 后前移；#t0023 oracle——vocab 相对词
  "subdir/vocab/types/Test" 胜 prefix 词 "ex:vocab/types/Test"）。撞词
  守门随步迁移（t0043 守护不变）。
- **转正 3 例**：t0023（vocab 胜 prefix）/t0043 全收（双 name 合并面实为
  撞词守门位置误——守门回补后直比过）/tc011（vocab 相对键）
- **deferred 33**：t0041/42 ERR 簇（展开层 @index+@list 值对象缺口——
  影响类单独立批）/t0044（reverse×双 term 排名）/t0045（../ 上级逃逸）/
  t0024（list 语言类型交叉）/t0038（异形前缀）/t0007/t0029/t0030 之
  残余/t0066/0110/tla01/tn/ts/ttn/tpr03/te002
- **过程**：块搬移吃掉撞词守门（搬移切片取自改前文本）——搬移后必
  grep 附属守门在场（⑦ 亦覆盖搬移形）

### 8.61 reverse 值级排名分键落成（2026-09-29 役21；213 持平——t0044 役内已过终收）
- **落码**：@reverse 非映射路值级**最短词形排名分键**（同 IRI 双 term 按
  值拆键——#t0044 oracle：dave→knows 全词、DefinedTerm→knowsVocab exact
  词）；回退分支**恒追加**修（首版 `Some(_) => ()` 吞同键第二值——t0050
  gregg 丢失即抓，harness pin 当轮拦截）
- **deferred 33 不变**（t0044 移入已收；其余簇照 §8.58/§8.60 挂靠）

#### 8.60.1 t0041/42 影响类勘定深挖（2026-09-29 役22——证据矩阵 + 模型缺口定位）
- **探针证据矩阵**（{@index,@list} 组合逐形）：{@list} 单独 OK / {@index,
  @value} OK（#t0036 已落）/ **{@index,@list} ERR**——expand_list_set_object
  的 @index 键落 `else → impure` ⇒ invalid set or list object
- **模型缺口定位**：impure 判据按 REC 本无错——错在**修不动**：
  `ExpandedValue::List` 变体**无 index 槽位**，{@index,@list} 展开产物
  无法携带 index 贯通压缩（t0041 oracle 要求 {@list,@index} 出形）。
  修法 = List 变体加 index 槽（构造点全清点 + 压缩 List 路出 @index 形）
  ——**单独立批**（模型变体扩展，非一行件）
- **影响类定性维持**：涉共享展开面（expand_list_set_object 为 expand/compact
  共用），修时须 expand 385 + toRdf 467 全绿复验

### 8.62 List index 槽批落成（2026-09-29 役23；213 → 215/246 plain，零回退）
- **模型扩展**：`ExpandedValue::List` 加 `index~ : String?` 标签槽（构造点
  5 处显式 None、pattern 位 14 处补 `..`、wbtest 2 处——编译器驱动全清点）
- **展开侧**：expand_list_set_object 增 @index 键捕获（挂 index_value、
  不落 impure——{@index,@list} 值对象合法，#t0041 oracle；P1/P2/P3 证据
  矩阵定案 §8.60.1）
- **压缩侧**：index 闸双 fit（带 @index 的 list 不入 @list term，落
  full-IRI 残余键保 {@list,@index} 形——#t0041 oracle）；List 通用渲染
  带 index ⇒ {@list,@index} 对象形；@list/@index 键走别名（#t0042
  oracle——listAlias/indexAlias）
- **转正 2 例**：t0041/t0042 全收口；**deferred 31**
- **REC 尾注**：serialize_value List 展开形仍出纯 {@list}（REC expanded
  形不带 @index——J2 对拍通道零扰动）

### 8.63 shaping 取舍序修正落成（2026-09-29 役24；210 → 216/246 plain，零回退）
- **打点实证**（COLLAPSE tddt 双行）：bar 值渲染两发——scoped @id 一发
  （rank 内 ✓）+ **outer xsd:string 覆盖一发**（chosen 渲染 ✗）——
  「outer 同名全权」shaping 序越位实锤
- **修正**：shaping 取舍序 = scoped 定义 datatype=@id ⇒ **scoped 全权**
  （type-scoped 定义对该节点就是全量定义——#tc007 oracle）；@vocab 型仍
  随 outer（tc009 不塌裁断不变——@vocab 传导需 @propagate，tc026 面另批）
- **【役25 更正】转正实为 1 例（tc007）**：役24 首记「6 例」为**过收**
  ——r15 FIXED 表实证仅 tc007 入转，tc015/016/020/024 仍红（scoped
  @vocab 键选/值位深层面未毕）；账实不符族纪律更正
- **deferred 30**：tc026（@propagate 传导——**前置定义（役24 定）**：
  **apply 链** = compact_apply_type_scoped 的套用序列；**propagate 位** =
  套用的 local context 是否带 @propagate:true（process_context 返回的
  ActiveContext 现不记录此位——需扩链上结构或旁路账）；**跟踪** = 该位
  须存活至嵌套节点渲染（子节点键选/值塌缩继承 propagate 过的 context）。
  三件齐备前 tc026 挂 deferred），
  tc011 已收、nullification 残（te002/tpr03）、t 系值分选残余（t0015/18/
  22/24/38/44/45/48/66/89/110）、tla01/tm007/tn006-009/ts001-002/ttn01-03

### 8.64 t 系值分选续批开工钉（2026-09-29 役25 前置——分组判据三分成文）

**分组判据**（逐例先归组再动手；禁凭感觉）：
- **更多形态**（同 fit 判据、新值形态组合）：判据位已有、组合未见——
  修法 = fit 函数加组合臂，不动骨架（#t0015/#t0018/#t0024 list 语言×
  类型交叉、#t0027 系偏好已落、#t0089 无语言辖域已落）。
- **边界**（判据位已有、参数域端点）：量化边界/极端形——修法 = 判据
  补端点臂（#t0066/#t0110 base 文档位多形态、#t0111 @-词转义已落）。
- **分叉**（oracle 与本实现裁断冲突且无在册裁定）：**禁落码**——先立
  裁定（oracle > 规范字面 族入册）再按裁定修（#t0007 值位 id-term
  取舍、#t0045 ../ 逃逸——**待裁定**）。
- 归组必须附**根因定位证据**（diff 位/打点行），无证据不入组。

### 8.64.1 语言镜像语义修正落成（2026-09-29 役25；计数零变——语义正确性批）
- **落码**（§8.64 更多形态类——List fit 语言镜像 + None 臂收紧）：
  bare_fit List 臂增**语言镜像**（Set 合首项语言 / Null 合无语言 /
  None = 缺省对齐——首版 None 臂无条件 true 过宽，收紧为缺省对齐；
  #t0024 termLL0/1/2 分选判据）+ 方向/语言双闸合取
- **计数零变定性**：镜像语义为 t0018/t0024 的**前置正确性**（分选判据
  就位），转正需搭配「Set 精确 > 缺省对齐」特异性位（pass-1 排名
  tie-break）——下役续
- **役24 过收更正**（§8.63）：转正实为 tc007 一例；账实不符族纪律执行

#### 8.64.2 pass-1 特异性位落成（2026-09-29 役26；216 持平零回退——t0018/0024 判据贯通）
- **排名键升级**：(词长, **特异性位降序**)——同长时 Set/Null 精确映射 >
  None 缺省对齐（#t0018/#t0024 oracle——en 项归 termLL1 非 termLL0）
- **特异性收紧**：仅对**无 datatype 纯串**计（language-mapping term 不得
  抢 typed 值——#t0015 oracle——v2(datatype t2) 归 term2 非 term5；
  首版全值计特异性致 term5 抢 typed 值，harness pin 当轮拦截）
- **t0018/0024 现貌**：判据已贯通仍红——残余在 list 吸收路与分选路的
  **路序交叉**（@list 值先经容器吸收臂，语言镜像在吸收臂内不可见），
  下役 List 吸收臂语言镜像迁移

#### 8.64.3 List type 镜像落位（2026-09-29 役27；216 持平零回退——语义正确性批）
- **落码**：bare_fit List 臂 **type 镜像**（#t0024 termTL0/1/2 oracle——
  td.datatype Some(dt) ⇒ 首项 datatype 合 dt 才入（bare）；None ⇒ typed
  值对象形）——对称语言镜像；index 闸/语言镜像/方向闸/type 镜像四闸合取
- **「语义正确性批」产出定性（役27 定）**：产出 = **判据贯通**（fit 闸
  全谱就位），非转正数——「零变」的合法定性 = 判据就位待排名位消费；
  转正数归特异性批（§8.65）
- **t0018/t0024 关系（役27 定——同一机制的两个面，非独立）**：共享
  **pass-1 特异性排名**（语言 + datatype 双维 tie-break）——t0024 =
  **list 容器面**（@list 项按 lang/type 分 term）；t0018 = **值对象混合
  面**（裸标量+语言值+typed 值同 IRI 多 term 按值分键）。一揽子批安全：
  排名位一改两面同收

### 8.65 t0024 转正批开工钉（2026-09-29 役28 前置——特异性位排名规则成文）

**「特异性位」与既有闸/镜像的关系成文**：
- **闸（fit 过滤器）**：语言镜像/方向闸/type 镜像/index 闸——判**能不能
  入**（不合即 false，无程度可言）。
- **特异性位（排名 tie-break）**：判**同长时谁赢**——位值 = 匹配维计数：
  维一语言（td.language_mapping Some 且值语言合）、维二 datatype
  （td.datatype Some 且值 datatype 合）；位高者胜、同位回退词长、同长
  回退候选序。
- **与语言镜像的关系**：语言镜像是**闸**（Set 不合即拒）+ **位**（Set 合
  计 1 分）的复合；方向闸同构（位暂不计方向——套件无方向 tie-break 例）。
  type 镜像（役27 新落）同构：闸 = @type 精确才 bare；位 = datatype 合计 1。
- **t0018/t0024 消费**（§8.64.3 同一机制两面）：两面共享同一位键——
  t0024 list 容器面、t0018 值对象混合面；位改一处两面同收。
- **单维渐进纪律（2026-09-29 役29 钉）**：特异性位**每次只落一维**——
  「维」= 排名键的一个加分维（第一维 language 已落〔役26〕，第二维
  datatype 本批，无第三维）；**每维落毕必跑全量**（不累积——禁「两维
  一起上」：役28 三改互作 77→159 教训）；全量红名单 diff 零回退才入库。
- **「§8.65 规则」自指消解**：本条即规则本体（上三行）；「按 §8.65
  规则施工」= 按本纪律逐维渐进 + 闸/位关系（上二行）执行，非另有所指。

### 8.66 datatype 维落成（2026-09-29 役30；账面 208 → 214/246 plain、零回退——【役31 更正：实为 216 → 214（−2 真回退），见 §8.67】）
- **单维渐进第一维全量落地**（§8.65 纪律执行——本维独立成批，未累积）：
  1. **估长器断环**（compact_rank_word_len 无递归——[4050] 定义环
     compact_node_jv→值渲染→排名→compact_node_jv 的解法）
  2. **特异性双维**：语言维（纯串）+ datatype 维（#t0015 v2 归 term2）
  3. **标量免疫入 List 语言闸**（#t0015 [1,2] 数值 list 归 term4）
  4. **type 镜像 + 语言镜像**（bare_fit List 臂——#t0024 termTL/LL 分选）
- 【役31 撤销】**「转正 6 例」未发生**（探针六连红，实况见 §8.67）：
  t0015/t0027 役16 即已在 plain；t0018/t0022/t0024/t0044 未迁入且现判
  FAIL。原文存档：t0015（语言/类型混合五 term 全对位）/t0018（混合值族）/
  t0022（type-@set 1.0 门）/t0024（list 语言类型交叉）/t0027（@set 偏好）/
  t0044（reverse 双 term）
- 【役31 勘正】**deferred 32 实际名单**：t0007（值位 id-term 取舍未实现）/
  t0018/t0022/t0024/t0044（**役31 转正门四例**）/t0038（异形前缀）/
  t0045（../ 逃逸）/t0048（三候选偏好）/t0057/t0061（**役30 回退例**——
  役31 收复或成文更正）/t0066/t0110（base 文档位）/tc015/tc016/tc020/
  tc024（scoped 值位深层）/tc026（@propagate 面）/te002（影响类纪律）/
  tjs07/tjs09（@json 判定）/tla01（语言敏感 list）/tm007（type map
  scoped 值链）/tn006-009（nest×容器）/tpr03（保护重定义交叉）/ts001/
  ts002（数组容器出形）/ttn01-03（type-scoped 值成形序）。
  原枚举含三幽灵（t0029/t0030/t0089——plain 在册绿，役16/17 撤销条在案）
  且漏十四例

### 8.67 役30 过收更正 + 役31 转正门正名（2026-09-30 役31 开工审计；探针实证）

**审计三对账**（`git show --stat` + 桶名单提取 + 探针现判，判分与 harness
同款）：
- **「+6 转正」未发生，实为 −2 回退**：役30 diff 对 plain 数组只删无增——
  移出 t0057/t0061（役27 时在册绿 ⇒ 役30 改动打破），216 → 214、30 → 32；
  「零回退」不实。
- **转正 6 例逐一证伪**：t0015/t0027 役16 即在 plain（役30 前后无迁移）；
  t0018/t0022/t0024/t0044 不在数组且探针现判 FAIL（探针六连红）。
- **deferred 枚举三幽灵漏十四**：t0029/t0030（役16 修平、役17 撤销条在案）
  与 t0089（已收）一直 plain 在册绿；真名单见 §8.66 勘正行。

**账实不符族·十（修法增补，编号对齐 ctx 族账——九 = §8.38 行旧）**：
compaction 后收尾账凭会话记忆写成——役次落账前必跑**三对账**：
`git show --stat`（diff 实况）× 套件 asserts（桶计数）× deferred 名单
提取（枚举逐项对），三者在案才落账。

**「t0024 转正门」正名（役31 开工钉——防对幽灵转正例重复做功）**：
- 门 ≠ t0024 一例（t0024 并未转正）。**门 = 四例 t0018/t0022/t0024/t0044**
  （deferred 在册、现判 FAIL）+ **t0057/t0061 收复**（修复或成文更正，
  禁静默留 deferred）。
- 机制残余 = **typed 值对象收集项 + type 特异性位**（役27 钉、役30 datatype
  维 ±1 不救济此四例——探针为证；type 计位与收集项的分工按各例第一差异
  施工中钉，渐进纪律 §8.65 不变）。
- 成功判据：四例转正（plain 214 → 218，deferred 32 → 28）+ t0057/t0061
  收复（→ 220/26）或成文更正留 deferred；deny-warn 全绿零回退。
  【役31 收口达成：220/26——四例 + t0057/t0061 全转正（超判据：判据只
  要求 218+收复或更正），见 §8.68】

### 8.68 转正门六例落成（2026-10-01 役31；214 → 220/246 plain，零回退——基线 = §8.67 勘正后的 214/32 实况）

**七件落码**（compact_standard.mbt 单文件）：
1. **估长器按候选变**（compact_rank_word_len 加 td_opt——役30 断环把
   「逐 term 词长」一并断了，t0057/t0061 回退根因）：id_only 节点取
   **本 term 塌缩词**长（塌缩旗标与 compact_value_item 串塌缩臂逐字
   同源——id_only 面即精确渲染长）；「相对序足够」原则不破——精确化
   只到 IRI 词形层，不重入渲染。
2. **词形级别 tie-break**（compact_word_rank：exact 0 < vocab 后缀 1 <
   前缀词 2 < base 相对 3 < 全 IRI 4——窄旗标逐步试塌归类，无递归）：
   #t0044 DefinedTerm exact 胜 base 相对（同长 11 字）。
3. **List 闸分支形**（compact_list_bare_fit 与 Value 臂同构——datatype
   分支优先）：@type term 只看**整列 uniform** datatype（语言不掺和）；
   混合 typed 列不归 @type term。役30 的平行 AND（lang && type）是
   v4/v5 列零候选的根因。
4. **typed 值对象收集项**：无 @type term 恒容 typed 列（值对象形居裸
   数组——#t0024 termTL0 混合列）+ 列的 uniform-datatype 计位
   （literal_datatype_of List 分支——#t0018 term4/5、#t0024 TL1/TL2
   排名位）+ 免注免疫扩到 typed（值对象带 @type 重展开不受缺省语言
   注入——#t0024 termTL0 闸）。
5. **标量禁入 @list 容器 term**（Value 臂 container List ⇒ false——
   #t0018 v0.2/v0.3/标量归 plain term）。
6. **无修饰纯串对象形放行**（缺省语言在场——#t0018 v0.3：对象形保住
   无语言态）。
7. **@reverse 逐值分键第二路**（compact_reverse_split_pairs 抽出双路
   复用）：普通 term（@type @id/@vocab）在 @reverse 位同 IRI 双候选
   按值拆键，出形保 @reverse 包裹——#t0044 dave→knows 全词、
   DefinedTerm→knowsVocab exact 词。

**键链穿参**（compact_value_item 加 key_active）：{"@id"} 对象形键随
键选择链（#tc011——type-scoped 注销别名在值链仍活；键链生效即 "@id"
字面保持）；property-scoped 对两链同权套用（「全参与」口径）。t0022
（别名生效）与 tc011（注销生效）同一 site 两面，此前硬编码 "@id" 掩盖
了双面。.mbti 补再生（ExpandedValue::List index~ 字段——役30 用而未
再生，本笔同补）。

**转正 6 例**：t0018/t0022/t0024/t0044（转正门四例）+ t0057/t0061
（役30 回退例收复）。deferred 32 → 26：t0007/t0038/t0045/t0048/
t0066/t0110/tc015/tc016/tc020/tc024/tc026/te002/tjs07/tjs09/tla01/
tm007/tn006-009/tpr03/ts001/ts002/ttn01-03（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124。

### 8.69 役32 开工钉：deferred 26 分布清点 + base 多候选与词形级别关系（2026-10-01 役31 收口后清点；用户令）

**分布六簇（26 例；负例 2）**：
- **tc scoped 深层（5，役32 首簇——用户令「先 tc 深层」）**：tc015
  （type-scoped base——§8.59 base 轨主 oracle）/tc016（type-scoped
  vocab）/tc020（type-scoped @value 别名）/tc024（type+property-scoped
  叠加、值对 previous context 裁断）/tc026（@propagate:true 存活节点界）。
  侦察定性：五例全在 **apply/传导面**（scoped 套用链 + previous 回退），
  不在排名面。
- **base/相对 IRI（3）**：t0045（../ 逃逸、terms ignored）/t0066（相对
  IRI 多形态——目录/文件/query/fragment 各归各）/te002（NEG——塌缩结果
  scheme 撞车报错面）。
- **@none/@type（3）**：ttn01-03（@type:@none 不压缩值 / 随容器出形）。
- **nest×容器（4）**：tn006-009。
- **@json 字面量（2）**：tjs07/09（@type @json 压缩/展开形）。
- **杂项（9）**：t0007（external context 补入——役16 判「未实现」待钉）/
  t0038（Drupal 复杂回环）/t0048（三候选偏好——null 映射 vs 无映射对
  非串值）/t0110（@included）/tla01（list 全元素最特异 term）/tm007
  （@type 上 scoped context）/tpr03（NEG——type-scoped 覆写保护 term）/
  ts001/002（@context 数组值 / @set+兼容值并存）。

**「base 多候选排名」与「词形级别 tie-break」关系钉（防与役31 混）**：
- **同一排名，非另一排名**。役31 排名键三层 = 词长 → 词形级别 →
  特异性位；「base 多候选」= 多候选词同落 base 相对形态（级别同为 3）
  ——此时**词长层已分序**（不同 base 相对形式长度不同），级别层不加
  不减。
- **base 轨（§8.59）在排名之前**：它是上下文**归属链**（scoped @base vs
  文档 base 的裁断），决定「拿哪个 base 塌缩」；排名只对归属后的词形
  比较。tc015 病根在归属/传导面，不在排名面——役31 词形级别既不救济
  也不干扰它。
- **落码分界**：tc 深层改动落 apply_type_scoped / previous-context /
  propagate 面 + 值渲染链；**役31 排名键冻结**（compact_rank_word_len /
  compact_word_rank 不动——除非新 oracle 证明键缺维，届时另立新维走
  §8.65 单维渐进）。

### 8.70 tc 深层五例落成（2026-10-01 役32；220 → 225/246 plain，零回退）

**六件落码**（compact_standard.mbt + expand_standard.mbt 各半——病灶一半在
压缩链、一半在**展开面值对象文档序**）：
1. **type mapping 无 vocab curie 形收留**（expand_standard @type 臂）：
   无 vocab 时含冒号相对形原样收留（#tc024 "ex:Number"——与值 datatype
   同串对上）；路径相对形拒（#ter23 "relative/iri" 无冒号）；空节点标号
   恒拒（#ter13 "_:not-an-iri"）。oracle > 规范字面族又一例——REC 字面
   「展开后须绝对 IRI」与 tc024 oracle 相抵，按三 oracle 切判别线。
2. **值对象 @type 先至挂起回填**（expand_standard）：@type 在 @value 之前
   出现时 literal 尚未建、datatype 赋值静默落空（#tc020 dt=None 根因，
   R32EX 扩展层复现钉）——pending_dt 挂起、值对象收口回填；**文档序
   依赖 bug，expand 套件全绿未覆盖（其输入 @value 均在前）**。
3. **值对象性预扫**（has_value_key_shaped）：@type 臂分路不再依赖
   is_value_object 的文档序置位——任一键展开为 @value 即值对象形态。
4. **节点自身 @id 词形走 value_chain**（base 轨传导到位——#tc015
   "#typed-id" 片段相对）；**新节点/父词形位双分**：完整子节点按
   scoped.previous 裁断回退（在 ⇒ active；缺位 ⇒ propagate 存活继承
   scoped——#tc026）；id-only 子节点 = 父词形位随 value_chain（#tc015
   subjectReference）。
5. **兜底键随键选择链**（leftover fallback_key 用 scoped——#tc016 com
   词形塌缩）+ **shaping scoped-only 臂 @vocab 同权保**（#tc026 baz；
   outer 同名案仍 outer 全权——#tc009 不变）。
6. **bare_fit 纯 term 臂 typed 闸**（非 raw typed 字面量不可裸吸——
   裸串重展开丢 @type；raw 标量 datatype 自恢复不受限）+ **值对象键
   别名化**（@value/@type/@language/@direction/@index 键随 key_active
   键链——#tc020 "value"/"type" 别名键）。

**转正 5 例**：tc015（type-scoped base）/tc016（type-scoped vocab）/
tc020（type-scoped @value 别名）/tc024（type+property-scoped 叠加）/
tc026（@propagate 存活）。deferred 21：t0007/t0038/t0045/t0048/t0066/
t0110/te002/tjs07/tjs09/tla01/tm007/tn006-009/tpr03/ts001/ts002/
ttn01-03（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124。
. mbti 无变化（改动全在私有面）。

**施工注记**：桶名单修补三轮失误（fmt 折行致替换锚静默 no-op ×2、
误删 tc021/tc022 ×1）——**桶名单改动禁字符串替换锚，以 HEAD 基线
程序化整块重建**（三对账法桶名单件的落实形态）。

### 8.71 役33 开工钉：@none 簇（ttn01-03）根分类（2026-10-01；用户令——「同根」须钉清根型）

**三例语义（oracle 摘录）**：term `@type: @none` 收编一切值形态，但值
**恒值对象形**（串/数/布尔不加 @type、typed 保己 datatype、语言值保
@language、节点引用保 {@id}）；容器语义照常（ttn02 无容器单值塌缩、
ttn03 @set 保数组）。

**根 = 边界（双义位），非未实现、非分叉**：
- 非未实现：@none **存储位已预埋**（ttn02 批——上下文处理 @type 臂收
  "@none" 关键字、datatype 位存 None、1.0 模式报错闸在案）；
- 非分叉：REC 单义「显式无 coercion」，ttn01-03 oracle 三连一致，无
  规范歧义可裁；
- 病灶 = **datatype None 双义**：显式 @none 与「无 @type」在存储位合流，
  消费位（裸形早退 / object_fit 值对象放行 / object_fit 节点引用放行 /
  展开面 coercion 串数布三臂）全按「无 @type」走 ⇒ 裸吸发生（ttn01
  现判即 bare 数组）。

**修法 = keyword 形标记 `Some("@none")`**（与 @id/@vocab/@json 同族——
datatype 位本就承载关键字形态，非新增布尔位、非改 None 语义）：
- 展开面：@none 短路三处 coercion（串值原样随 term 语言/方向；数/布尔
  原生保形归 None 臂）；
- 压缩面：object_fit 值对象/节点两臂放行 "@none"；bare 形早退跳过；
  bare_fit **自动闭**（"@none" 恒不等值 datatype，无需改）；
- 容器/单值塌缩走既有通用位，零改动。

**与既有 @none 机制的界线（三个同名不同位，互不混）**：language map 的
@none 键（#t0030/#tm010——键位「无语言桶」）、t0089 无语言值辖域前置扫描
（归组判据）、本簇 term 定义 @type @none（**值成形面**）。改动只在第四位，
前两位既有 oracle（#t0030/#tm010/#t0089）同笔全量回归。

### 8.72 @none 簇三例落成（2026-10-01 役33；225 → 228/246 plain，零回退）

**钉的兑现（§8.71 根分类 = 边界·双义位）**：@none 存储位改 keyword 形
标记 `Some("@none")`（与 @id/@vocab/@json 同族——datatype 位承载关键字
形态的既有先例，非新增布尔位），消费位按形接闸：
- **展开面三臂短路**：串值 coercion @none 早退（原样 + term 语言/方向
  随 term）；数/布尔原生值关键字元组加 @none（raw 保形无 @type——
  #ttn01 {"@value":1} 无 @type ✓）；不短路则 D 臂会误强转 datatype
  "@none"（施工前静态查获）。
- **压缩面四处**：object_fit 值对象/节点两臂放行（值恒对象形、节点
  引用保形）；compact_value_jv 裸形早退跳过（none_no_coercion 位）；
  bare_fit 自动闭（"@none" 恒不等值 datatype）零改动；容器/单值塌缩
  走通用位零改动（ttn02 单值塌缩、ttn03 @set 保数组自动达成）。
- **界线验证**：既有 @none 同名位（language map #t0030/#tm010 键位、
  t0089 前置扫描）同笔全量回归零回退——三同名位互不混的钉兑现。

**转正 3 例**：ttn01（不压缩值）/ttn02（无容器单值塌缩）/ttn03（@set
保数组）。deferred 18：t0007/t0038/t0045/t0048/t0066/t0110/te002/
tjs07/tjs09/tla01/tm007/tn006-009/tpr03/ts001/ts002（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。

### 8.73 杂项清账 + 排名键冻结纪律 + 双簇勘定（2026-10-01 役34；用户令三核一勘——勘定批，转性先例 §8.58 役28）

**核一·根型正名**：见 ctx「根型三分类正名」条——「根分类」弃用，统一
**根型**（未实现/边界/分叉），与「根因」（批分组判据）、「根标记」（IRI
解析数据位）切界。§8.71「根分类」读作「根型」。

**核二·杂项 9 清账（「杂项」类目注销——禁止无类缺口兑现）**：九例逐一
立案（根型带探针 diff 证据，r34 勘定批）：
| 例 | 根型 | 簇/修法面 |
|---|---|---|
| t0007 | 未实现 | 值位 id-term 取舍（compact_node_jv 值位键选择——字串值经 @id 项塌缩词 vs full-IRI 键，oracle 取 full-IRI；役16 判定树兑现）——个案 |
| t0038 | 边界 | 前缀词形生成（compact_iri_word 前缀步——异形 mapping「body:」空后缀路径；Drupal 复杂回环的残余位）——个案 |
| t0048 | 边界 | 吸收臂丢 raw 形（compact_value_jv language-null 吸收 return String(value) 丢 raw——数 5 变 "5"）；三候选偏好层待首层修后复核——语言闸簇 |
| t0110 | 未实现 | @included 出形（graph container["@set","@graph"] 复合容器——§8.45 邻域）——graph 簇 |
| tla01 | 边界 | list 全元素特异性（compact_list_bare_fit 首项闸 vs oracle「全元素最特异计缺省语言」——**fit 闸位非冻结面**）——语言 list 簇 |
| tm007 | 边界 | type map 子键词形随 scoped 链（typemap 子键未吃 Inner scoped "a" 词形——役32 键链同族）——scoped 键簇 |
| tpr03 | 未实现(NEG) | compact 面 protected 覆写校验（type-scoped 覆写保护 term 须报错）——保护校验簇 |
| ts001 | 未实现 | context 处理数组形值（"@context": [a,b] 合并——ContextProcessor）——context 处理簇 |
| ts002 | 未实现 | 同上（@set 与兼容值并存形）——context 处理簇 |
排期建议序：context 处理簇（2 例同根）→ 语言闸簇（t0048+复核）→
scoped 键簇（tm007）→ 语言 list（tla01）→ graph（t0110）→ 个案三件
（t0007/t0038/tpr03）随缘并批。

**核三·役31 排名键冻结纪律（成文）**：
- **冻结范围**：compact_rank_word_len、compact_word_rank 两函数 +
  三层键序语义（词长 → 词形级别 → 特异性位）。
- **冻结效力**：他簇施工禁顺手改面；套件计数变化凡源于排名面即违冻
  （归因随落账注记）。
- **解冻条件（三，穷尽）**：①新 oracle 证键缺维 ⇒ §8.65 单维渐进
  （一役一维、全量绿才收）；②oracle 证伪既有层序 ⇒ 更正批（三对账
  全档）；③用户令专役钉明解除。
- **界外澄清**：bare_fit/object_fit 的 **fit 闸位不在冻结面**（役33
  object_fit 有案）——冻结锁排名键，不锁闸；tla01（list 全元素闸）、
  t0048（吸收臂）均在闸位，不受冻。

**勘一·双簇难度（用户令先勘再定）**：
- **@json 簇（tjs07/09）——低成本，1 例施工 + 1 例白捡**：勘定实判
  **tjs09 现判已 PASS**（deferred 数组迁入即 +1 零施工）；tjs07 diff =
  `[[…]]` 双包 vs `[…]`——**根型 = 边界（值形态×容器交叉）**：@json
  raw 数组值被 @set 多值并组再包一层，raw 数组应原子直发。**钉（防
  J3.3 混）：本簇非 JCS 边界**——canonical 序列化无涉（raw 词形逐字
  回环），J3.3 挂账不联动；修法位 = 值发射/并组对 @json raw 的原子
  豁免（compact_value_item/property_values 发射位），小成本。
- **base/相对 IRI 簇（t0045/t0066/te002）——高成本**：t0045（../ 点段
  上跳——resolve_base_value 共享核重写，todo A 组 8 例 IRI suite 同笔
  双跑）；t0066（**分叉裁定**：base 文档位多形态——目录/文件/query/
  fragment 各归各，役16 判定待落码）；te002（NEG——scheme 撞车须报错，
  现判 neg-ok）。共享核 + 双 suite 回归面 + 裁定三件叠，须专役全预算。

**勘定结论（建议序，待用户定）**：先 @json（役34 快批——tjs09 白捡 +
tjs07 原子豁免小修）；base 簇另立专役（A 组算法重写随行）。

### 8.74 @json 簇落成（2026-10-01 役34；228 → 230/246 plain，零回退）

**钉的兑现（§8.73 根 = 边界·值形态×容器交叉，非 JCS 边界）**：病灶一行
——组出键位的 @json 直出守卫查 **full IRI 形**
`rdf-syntax-ns#JSON`，而管线 datatype 全程**关键字形** `"@json"`（丁批
#tjs01 定形：上下文 type mapping 与字面量 datatype 同为关键字）——守卫
恒不命中 ⇒ @set keep 双包（`[[…]]`）。修 = 守卫对齐关键字形（一行）。
J3.3 不联动兑现：canonical 序列化零涉（raw 词形逐字回环）。
- tjs09 **白捡兑现**（勘定实测已 PASS，迁入即 +1 零施工）；
- 全仓 grep 复核：同款 full-IRI 守卫无别处（to_rdf.mbt 的 RDF_JSON_IRI
  常量是 RDF 面合法用途，非本坑）。

**转正 2 例**：tjs07（@type @json 数组值直出）/tjs09（展开形 JSON 字面
量）。deferred 16：t0007/t0038/t0045/t0048/t0066/t0110/te002/tla01/
tm007/tn006-009/tpr03/ts001/ts002（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。

### 8.75 役35 开工钉：context 处理簇（ts001/002）根型（2026-10-01；用户令）

**例义勘正**：purpose 字面「@context values may be in an array」有误导——
实为 **`@container` 的数组形**（ts001 单元素数组 `["@list"]` 等六族；
ts002 双元素 `["@id","@set"]` 并容族），非 @context 值数组形。

**根型 = 边界（验证白名单窄于已预埋的存储语义）**：
- 非未实现：@container 数组**臂在**（validate_container_value 数组形
  图组合已绿——#t0083 三元）；**存储位已预埋**——单元素数组 = 裸形
  等价六族存储齐备（臂内注释已引 #ts001 oracle，前役开了头没通闸）；
- 非分叉：REC 4.2.2 数组形组合规则单义（单元素任意/@graph 组合/
  @set+@X 并容；@list 禁组合）；
- 病灶 = validate_container_value 数组臂白名单只放行图组合 ⇒
  ts001/002 context 处理 Err（探针 ERR 实证）；另 map+set 次级位缺
  （graph_set 先例在，[@id,@set] 族无对应保形位）。

**修法三件**：①验证数组臂放宽三形（单元素任意/@graph 组合不变/@set
并容 ≤1 主键；@list 禁组合、重复/未知/空拒）；②存储 @X+@set ⇒
container=Some(X) + 新位 `container_set : Bool`（TermDefinition 加字段，
graph_set 同族先例；构造位 8 处同笔）；③compact 主 map 发射位按
container_set 保数组（reverse/graph 位对称挂账——无 oracle 不扩）。
与既有 context 处理器的界线：改动只在 @container 数组臂 + map 发射
保形读位；process_context 主链（元素级/type-scoped/property-scoped
三链）零涉，役32 键链零涉。

### 8.76 context 处理簇两例落成（2026-10-01 役35；230 → 232/246 plain，零回退）

**钉的兑现（§8.75 根型 = 边界·验证白名单窄于存储语义）**：
1. **验证数组臂三形放宽**（validate_container_value）：单元素 = 裸形
   等价（#ts001）；@graph 组合原样保留（#t0083）；@set 并容 ≤1 主键
   （#ts002——@set+@id|@type|@language|@index）；@list 禁组合、重复/
   未知/空拒、1.0 恒拒。
2. **存储 @X+@set 并容**：container = 主键态 + 新位
   `container_set : Bool`（TermDefinition 加字段——graph_set 同族先例；
   构造位 8 处同笔：expand_standard 4 + wbtest 4；shaping scoped-only
   构造位随 td_scoped 传导）。单元素数组走既有裸形等价位零改动
   （存储臂注释预埋兑现）。
3. **compact 主 map 发射保形**：map 值塌缩位按 container_set 保数组
   （ts002 map 值恒数组形）。reverse/graph 位对称挂账（无 oracle 不扩）。

**转正 2 例**：ts001（六族单元素数组容器）/ts002（@set 并容四族）。
deferred 14：t0007/t0038/t0045/t0048/t0066/t0110/te002/tla01/tm007/
tn006-009/tpr03（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124。
**.mbti +1**（TermDefinition.container_set 公开面新增——本笔同带）。
桶锚注记：tpr03 系 deferred 例，桶插入锚误选致脚本 abort 一次——
assert 拦截，工作区未污（三对账法桶名单件再兑现）。

### 8.77 役36 开工钉：语言闸簇 t0048 根型（2026-10-01；用户令排期首簇）

**根型 = 边界（偏好位已通，渲染吸收臂丢 raw 形）——单点双证**：
- 偏好证：OUR 键 = `propertyLanguageNull` = oracle 键——「language-null
  term 胜无映射 term（非串值）」的**三候选偏好已通**（役26 spec_lang
  位 (Some(Null), None) ⇒ +1 即此偏好；§8.73 备案的「偏好层待复核」
  **复核结论 = 已通，无第二层**）。
- 形证：OUR 值 = `"5"`（串）vs oracle `5`（raw 数）——compact_value_jv
  **吸收臂 return String(literal.value) 丢 raw**（language-null 臂与
  方向双臂共四处；datatype 吸收臂同形位是 raw 保形的——420 行先例）。
  数值经标量免疫入 Null 映射 term 裸位，吸收臂把 raw 数值串化。

**修法 = 四吸收臂 raw 保形**（return raw Some 否则 String——与 datatype
吸收臂同形）。与语言闸其他位的界线：bare_fit 闸零涉（偏好已对）、
tla01 全元素闸另案、标量免疫判据零涉。

### 8.78 语言闸簇 t0048 落成（2026-10-01 役36；232 → 233/246 plain，零回退）

**钉的兑现（§8.77 根型 = 边界·吸收臂丢 raw 形）**：四处吸收臂
（language Set/Null + direction Set/Null）`return String(literal.value)`
改 raw 保形（`match literal.raw`——与 datatype 吸收臂 420 行同形）。
**复核兑现：三候选偏好层已通无第二层**（役26 spec_lang 位即此偏好，
OUR 键 = oracle 键为证）。语言吸收族全量回归零回退（#t0015 term5/
#t0089/#tdi 族原样绿）。

**转正 1 例**：t0048（language-null 偏好 + 非串值 raw 保形）。
deferred 13：t0007/t0038/t0045/t0066/t0110/te002/tla01/tm007/
tn006-009/tpr03（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。

### 8.79 役37 开工钉：scoped 键簇 tm007 与役32 键链的「同族」定位（2026-10-01；用户令三线钉）

- **同一机制**：键随键链——type-scoped 定义的 term 作子树键位词形
  （"a" 是 Type scoped context 的 term，作内节点属性键）。
- **不同 site**：役32 通的是 compact_value_item 的 {"@id"} 键位 + 属性
  兜底键位 + 值对象键位；**tm007 的 site = compact_map_entry 的 Type 臂
  值渲染位**——役32 未触及。
- **形态同构**：type-scoped term 在子树键位的生效/失效判定（tc022 别名
  生效 / tc011 注销失效 / tm007 生效）。

**病灶（读码实证）**：Type 臂把 `types[0]` 剥去做 subkey，variant
（types[1:]）渲染传**外层 active**——键化 type 的 type-scoped 定义在
值渲染链上不存在（"a" 缺位 ⇒ 属性键落全 IRI）。**修法 = 键化 type 的
scoped context 预套**（compact_apply_type_scoped([types[0]], active)
作 variant 渲染链；subkey 词形仍随原 active 不动——tm020/tm022 旗据
不扰）。多 type 与键化 type 的应用次序边缘挂账（无 oracle；REC 逆序
语义在多 type + 双 scoped 定义时或有出入——遇 oracle 另钉）。

### 8.80 scoped 键簇 tm007 落成（2026-10-01 役37；233 → 234/246 plain，零回退）

**钉的兑现（§8.79 三线定位）**：Type 臂值渲染链改 keyed_chain——
`compact_apply_type_scoped([types[0]], active)` 预套键化 type 的
type-scoped 定义（variant 已剥 types[0]，内层 apply 见不到——补位）。
三处换链（variant_bare 词形 / None-id 节点 / 常规节点渲染）；**subkey
词形仍随原 active**（tm020/tm022 旗据零扰）。tm 族全量回归零回退
（tm004 types[1:] 浅拷贝 / tm020/tm022 串塌缩原样绿）。多 type 次序
边缘照 §8.79 挂账。

**转正 1 例**：tm007（type map 值位的 scoped 键链）。deferred 12：
t0007/t0038/t0045/t0066/t0110/te002/tla01/tn006-009/tpr03（负例
te002/tpr03）。deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、
子模块 124、.mbti 无变化。

### 8.81 役38 开工钉：语言 list 簇 tla01 根型（2026-10-01）

**根型 = 边界（语言标签大小写折叠缺失）**：termLL1 `@language: "eN"`
对值 `"en"`——BCP47 语言标签大小写不敏感，闸位逐字比对拒 bare
（探针 diff：en-list 值对象形 vs oracle bare 数组）。机制位全在
（List 闸/语言镜像/排名位——役30-31 已落）。

**修法 = `lang_tag_eq` 助手**（ASCII 宽松折叠——语言子序列恒 ASCII）
接六比较位：bare_fit 值臂 Set/缺省对齐、list 闸 Set/缺省对齐、
compact_value_jv 吸收臂与 bare 对齐。**排名键零涉**（冻结纪律——
比较位是闸不是键）。方向标签不扩（无 oracle，从严）。与 t0024 的
界线：t0024 精确匹配已绿（"en"=="en"），折叠为超集不改其判。

### 8.82 语言 list 簇 tla01 落成（2026-10-01 役38；234 → 235/246 plain，零回退）

**钉的兑现（§8.81 根型 = 边界·大小写折叠缺失）**：`lang_tag_eq` +
`ascii_fold_lower` 助手接**七比较位**（bare_fit 值臂 Set 与缺省对齐 /
list 闸 Set 与缺省对齐 / compact_value_jv 吸收臂与 bare 对齐——钉写
六、施工中 bare 对齐位实为独立第七位）。Char 无 to_lower → ASCII 手折
（A-Z ±32，语言子序列恒 ASCII 前提在册）。排名键零涉兑现（冻结纪律
——闸非键）。t0024 精确匹配族全量回归零回退；方向标签从严不扩在案。

**转正 1 例**：tla01（list 全元素最特异 term——"eN"≡"en" 折叠即通，
全元素计缺省语言由既有闸位承担）。deferred 11：t0007/t0038/t0045/
t0066/t0110/te002/tn006-009/tpr03（负例 te002/tpr03）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。

### 8.83 役39 开工钉：graph 簇 t0110 根型（2026-10-01；勘定修订：未实现 → 边界）

**判别谓词（三绿例对读）**：t0078 值 = 普通节点对象（无 @graph）→ 不进
graph shaped 路（正常两遍）；t0082 = Index 次级（shaped 数组形正是
map 面所需——"g1":[…]）；t0109 = 非 graph_set 路的 **@included 包裹
机械已存在且绿**（多内容 shaped = @included 对象）。t0110 =
`["@graph","@set"]` + 纯 graph object 值 → graph_set shaped = 数组 →
发射位摊平（`[[…]]` 塌成平铺）——EXPECT 单成员 `{"@included":[…]}`。

**根型修订：未实现 → 边界**（§8.73 勘定批初判修正——@included 机械
在、shaped 形态判据缺**次级位维度**：graph_set 数组形只该用于映射面
次级 Index；bares 面的 graph-object 值该走 @included 语义）。

**修法 = shaped 判据加次级位**（`graph_set && graph_secondary is
Some(_)` 才数组形；bares 面落 @included/单内容分支——发射位摊平循环
对非 Array 成员整员直推，天然承接）。与 graph 既有位的界线：载体渲染
（@id 组，#t0080）/映射归组（#t0081/#t0083）/t0078 普通节点路全不涉。

### 8.84 graph 簇 t0110 落成（2026-10-01 役39；235 → 236/246 plain，零回退）

**钉的兑现（§8.83 根型修订 = 边界·shaped 判据缺次级位维度）**：shaped
形态判据加 `graph_secondary is Some(_)`——数组形仅映射面次级（#t0082
Index 位），bares 面的 graph-object 值落 @included/单内容分支（发射位
摊平循环对非 Array 成员整员直推，天然承接——`[{@included:[…]}]` 单
成员出形 ✓）。graph 族全量回归零回退（t0078 普通节点路 / t0082 映射
面数组形 / t0083 载体归组 / t0109 非 graph_set @included 原样绿）。

**转正 1 例**：t0110（[@graph,@set] 复合容器的 @included 出形）。
deferred 10：t0007/t0038/t0045/t0066/te002/tn006-009/tpr03（负例
te002/tpr03）。deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、
子模块 124、.mbti 无变化。

### 8.86 个案 tpr03 落成（2026-10-01 役40；236 → 237/246 plain，零回退）

**钉的兑现（§8.85 根型修订 = 边界·apply 吞错）**：compact_apply_type_scoped
改 Result 贯穿——type-scoped 应用位的保护重定义报错（install_term_definition
机械原样）直达 compact_document；两调用位同笔（compact_node_jv scoped
推导位 Err 贯穿；役37 keyed_chain 位 Option 契约降 None——错误经兜底
分选的 compact_node_jv（含同款 apply）重现不丢，注释在案）。全量回归
零回退（type-scoped 面 tc/ttn 族原样绿——吞错改贯穿只影响真 invalid）。

**转正 1 例（NEG）**：tpr03（type-scoped 覆写保护 term 须报错）。
deferred 9：t0007/t0038/t0045/t0066/te002/tn006-009（负例 te002）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。

### 8.85 役40 开工钉：个案三件独立性勘定（2026-10-01；用户令——独立则先做个案）

- **tpr03：完全独立 ✓（本役施工）**。根型修订：§8.73 未实现 → **边界**
  ——保护校验机械全在（install_term_definition + type_scoped 旗
  override_protected=false），病灶 = **compact_apply_type_scoped 吞错**
  （`Err(_) => ()`——保护重定义报错到不了 compact_document ⇒ neg-ok）。
  修法 = apply 返回 Result 贯穿（scoped/keyed_chain 两调用位）。
- **t0007：独立但深勘加量（本役不施工）**。修法面 = 值位 fit 裁定
  （@id 强转 term 不收字面量 ⇒ object_fit 翻转）**+ 兜底键裁定**——
  勘定发现：弃用 term 后 leftover 兜底走前缀步得 `ex:contains`，而
  oracle 要**全 IRI**（被拒 term 不得经前缀复得键位）——两层裁定，
  非单翻转。保持独立，专役一件。
- **t0038：独立但同函数面（建议随 base 专役同笔）**。修法面 =
  compact_iri_word **前缀步**（异形 mapping「body:」对 raw index 键的
  词形生成）；base 专役重写 resolve_base_value/**base 步**——同函数
  不同臂，同笔施工避免双触 compact_iri_word。
- **排期结论**：三件均独立于 base/相对 IRI 的**语义面**（resolve/
  base 步零依赖）；tpr03 即刻施工；t0007 专役一件；t0038 随 base
  专役同笔。

### 8.85 役40 开工钉：个案三件独立性勘定（2026-10-01；用户令——独立则先做个案）

- **tpr03：完全独立 ✓（本役施工）**。根型修订：§8.73 未实现 → **边界**
  ——保护校验机械全在（install_term_definition + type_scoped 旗
  override_protected=false），病灶 = **compact_apply_type_scoped 吞错**
  （`Err(_) => ()`——保护重定义报错到不了 compact_document ⇒ neg-ok）。
  修法 = apply 返回 Result 贯穿（scoped/keyed_chain 两调用位）。
- **t0007：独立但深勘加量（本役不施工）**。修法面 = 值位 fit 裁定
  （@id 强转 term 不收字面量 ⇒ object_fit 翻转）**+ 兜底键裁定**——
  勘定发现：弃用 term 后 leftover 兜底走前缀步得 `ex:contains`，而
  oracle 要**全 IRI**（被拒 term 不得经前缀复得键位）——两层裁定，
  非单翻转。保持独立，专役一件。
- **t0038：独立但同函数面（建议随 base 专役同笔）**。修法面 =
  compact_iri_word **前缀步**（异形 mapping「body:」对 raw index 键的
  词形生成）；base 专役重写 resolve_base_value/**base 步**——同函数
  不同臂，同笔施工避免双触 compact_iri_word。
- **排期结论**：三件均独立于 base/相对 IRI 的**语义面**（resolve/
  base 步零依赖）；tpr03 即刻施工；t0007 专役一件；t0038 随 base
  专役同笔。


### 8.87 个案 t0007 落成（2026-10-01 役41；237 → 238/246 plain，零回退）

**两层裁定兑现（§8.85 勘定加量件）+ 施工中发现的第三层**：
1. **值位 fit 裁定**：object_fit 值臂 @id/@vocab 不再收字面量（裸串
   重展开被强转；值对象形 oracle 亦不取——#t0007）；节点引用 Node 臂
   不变（#t0006 term2 原样绿）。
2. **兜底键裁定·前缀撞词门**：compact_iri_word 前缀步产物为在册 term
   名时跳步保全 IRI（#t0007——被拒 exact term 不得经前缀复得键位
   "ex:contains"；#t0043 vocab 步同族判据移植）。
3. **兜底键裁定·vocab 撞词门精化**（施工中 tc027 回退打点定位）：
   suffix term 的 IRI **同于**被压 IRI 时非撞（即 exact term——键位
   词形照用，#tc027 "baz"）；异于才跳（#t0043 本案）。粗守门
   `terms.contains` 精化为 IRI 比对——t0043 自身判据不变（其案 IRI
   相异）。
- **打点注记**：二分（翻转/守门）与走码分析一度矛盾——R41MAP/R41LEFTOVER
  打点定谳（map_entry 零进入，map 形假象排除；真病灶 = 翻转后 leftover
  兜底撞既有 vocab 守门）。「打点带假设判别信息」条再兑现。

**转正 1 例**：t0007（external context——值位 id-term 取舍收口）。
deferred 8：t0038/t0045/t0066/te002/tn006-009（负例 te002）。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。
**余量**：t0038 随 base 专役同笔；base/相对 IRI 专役（t0045/t0066/
te002 + A 组同笔双跑）待全预算。

### 8.88 收官役（base 专役）开工钉 + 三处核落账（2026-10-01；用户令）

**核一·§8.87 三层根型挂账（按根型三分类）**：①值位 fit 裁定 = **分叉**
（REC 字面「值对象形安全」与 oracle 全 IRI 取舍相抵——按 oracle 裁量）；
②前缀撞词门 = **边界**（#t0043 同族守门未铺到前缀步——机械位在）；
③vocab 撞词门精化 = **边界**（terms.contains 粗判据精化为 IRI 比对）。
三层均属「设计如此/修法裁量」类，无未实现。

**核二·「加量件」正名**（§8.85 新造词，补定义）：**加量件 = 勘定批原判
一层修、深勘后发现需两层及以上（或牵出第二裁定面）的 deferred 件**——
t0007 即此（勘定判「值位 fit 单翻转」，深勘牵出兜底键裁定第二层）。
Companion 词：t0038 = 「同函数面件」（修法面与另一专役同函数不同臂，
建议同笔）。

**核三·deferred 8 分布勘正（用户令——「只剩 base 面」结论不准，勘正）**：
t0045/t0066/te002（base 簇 3）+ t0038（异形前缀·随 base 同笔）=
**base 面 4**；**tn006-009（nest×容器簇 4 例）——§8.73 排期在案未施工**。
本收官役清 base 面 4；nest 簇 4 例为**真正的末批**（收官役后另役或同批
追加，待令）。

**钉一·共享核冻结面清单（收官役）**：
- **重写面**：压缩方向相对形生成（compact_iri_word base 步——../ 上跳/
  fragment 首位/query 形裁定）；expand 侧共享核
  （resolve_base_value/merge_base_reference——**A 组算法已重写已绿，
  本役只读不写**；若压缩面裁定需共享核语义对齐，改动限增量注释）。
- **复跑门**：expand 385 + compact 全量 + n3gen 12 + 子模块 124 四门
  外加 **A 组 8 例（t0120-0127）与 #t0029/#t0091/#tr001 专项对**
  （todo A 组「双 suite 同跑」令兑现）。
- **役31 冻结面关系**：排名键函数（compact_rank_word_len/compact_word_rank）
  **不动**；词长**值**可能因 base 修正而变（合法——键三层语义未动），
  套件 diff 若现排名面翻转须归因注记（§8.69 冻结纪律兑现）。
- **禁触清单**：役32 键链（key_active）、役33 @none 标记、役41 撞词门
  （已绿面）——本役改动只在 base 步与键位出口检测。

**钉二·te002 Err 点（防「错得对」）**：属性 IRI `tag:champin.net,2019:prop`
的 **scheme "tag" 与在册前缀 term 同名**——as-is 兜底出的键位词会被重
展开读成 curie（→ `http://example.org/ns/tag/champin.net,2019:prop`
≠ 原 IRI，撞词不可救：词即原 IRI 本身，无更优词形）。**Err 必须在
compact_iri_word 键位出口的 scheme 撞名检测发**（结果为绝对 IRI 且
scheme 恰为在册 term 名 ⇒ Err），不得在 expand 侧/上下文处理位代发
（错点=错因）。

### 8.89 收官役 base 簇三例落成（2026-10-01 役42；238 → 241/246 plain，零回退）

**三刀兑现（§8.88 两钉框架内）**：
1. **query 相对形**（iri = doc URL + "?…" ⇒ "?…"——与 tc015 fragment 规则
   对称，#t0066 第 3 行）。
2. **../ 上跳形**（#t0045 "../parent-node"/#t0066 "../"../../" 族——同
   scheme 同 authority 下段级公共前缀对 **base 目录段**（bp 尾段 pop——
   目录标），ups = 目录段数 − 公共段数。**施工勘误两笔**：①it 尾段误
   pop 吃掉目标段（parent-node ⇒ "../"）——目录标 pop 只归 bd；②裸
   authority（#t0076 "http://example.com" 无 path）伪造路径卷入上跳
   ——has-path 前提守卫（无 path 恒绝对）；③值位限定 allow_vocab=false
   （property 兜底键走 vocab 形不上跳——#t0095 vocab "" 键形不被 ../
   覆写）。十二点目标形（tests/=1 上…root 文件=3 上）**段级均一规则
   成立**——勘定期「非均一裁」疑虑解除（算术基线取错目录所致）。
3. **te002 scheme 撞名检测**（键位出口两处：compact_property_pair 键 +
   leftover 兜底键）——**施工勘误**：初版按 scheme 名在册即 Err，误伤
   #t0006（前缀词 ex:term1 语法似绝对且 "ex" 在册但重展开同于原 IRI）
   ——精化为**重展开比对**（scheme term 展开 ≠ 原 IRI 才 Err）。
4. **@type 词形不走文档相对化**（allow_base=false——#t0066 类型位
   oracle 全绝对；类型位只经 term/vocab）。

**转正 3 例**：t0045（../ 上跳/terms ignored）/t0066（base 文档位多形
态——fragment/query/目录/上跳各归各）/te002（NEG scheme 撞车报错）。
deferred 5：t0038（本役 base 步已重写，前缀词形面待专研）+ tn006-009
（nest×容器末批）。**负例 17/17 全 plain**。
deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、子模块 124、.mbti 无变化。
§8.88 冻结面纪律兑现：排名键/键链/@none/役41 撞门零触；expand 侧共享核
只读（A 组 8 例原样绿）。

### 8.90 nest×容器末批落成（2026-10-01 役43；241 → 245/246 plain，零回退）

**根型 = 边界（接线缺失）**：nest 组账（nest_groups/nest_order——tn001-005
纯 nest 绿）与 map 发射位（§8.43 map 容器路由——tm/t0030/t0036 族绿）
两位皆在，复合面（map 容器 × @nest）无接线。修法 = map 发射位按 td.nest
入 nest 组、带 term 名中间键级（`nestedindex→index→{A,B}`——#tn006-009
四族 @index/@language/@type/@id 全过）。

**施工勘误（入册）**：首轮接线落错位（compact_property_pair 尾——文本
锚撞同形尾段），拆错位块时把 **reverse 映射组出键的原 push 一并抹除**
（#t0036 isKnownBy 顶层提升位静默丢输出——harness 当轮拦截）——复回并
注记。锚撞教训：**同形尾段多处时，锚必须带前导独有行**（本轮改用
「空值属性 #t0004」前导锚定位）。

**转正 4 例**：tn006（@index×nest）/tn007（@language×nest）/tn008
（@type×nest）/tn009（@id×nest）。deferred 1：t0038（前缀词形面专研）。
**负例 17/17 全 plain**。deny-warn 65/65 绿、全仓 377 零回退、n3gen 12、
子模块 124、.mbti 无变化。

### 8.91 里程碑：deferred 1（2026-10-01 役43 收口；245/246 plain——最后一里内容）

**里程碑**：245/246 plain，deferred 仅 **t0038** 一例。负例 17/17 全
plain；六套件面（expand/toRDF/flatten/compact/对账三件套/判定器自检）
全绿。

**最后一里 = t0038 三核勘定（用户令三核）**：
- **根型 = 分叉（待裁）**：oracle 要 map 形 term（title/body——
  `@container: @index`）作 **@index 子键前缀源**（`title:/value` =
  term「title」mapping `site-cd:node/article/title` 前缀 + `/value`
  后缀）；而 REC 4.2.2 + #tp001/#tp005 判据 = **map 形缺省不可作前缀**。
  规范字面与 oracle 相抵——非未实现（前缀步机械在、判据闸在）、非纯
  边界（闸的放宽须裁「@index 子键位特例」条款），待裁。
- **通用面 vs 个案**：模式（@index 子键 × 嵌套前缀 term 词形）通用，
  套件仅此一例；修复 = @index 子键词形位的前缀资格特例 + tp 族全量
  回归——中成本。
- **收官判定**：**缺口有解释即合格**——解释在册（本条），t0038 可留
  deferred，**不阻塞收官**；「246/246 全 plain」是目标非唯一目标。
- **与 base 专役关系（勘正）**：§8.85 原判「随 base 专役同笔」——役42
  base 步已重写收口且未触前缀步，**关系已变为独立批**（前缀步面独立，
  无同笔必要）。
- **裁定（2026-10-01 用户令）**：**留 deferred，不施工**。理由四条：
  ①分叉（待裁）非真缺口——分叉的处理 = 入册不修复；②缺口有解释即
  合格——解释在册（本条），可留 deferred 不阻塞收官；③修复中成本
  不划算（@index 子键位前缀资格特例 + tp 族全量回归），且若裁「按
  oracle」须动已绿的 #tp001/#tp005，成本更高；④246/246 是目标非唯一
  目标——收官不是清空 deferred，是**每个 deferred 有解释**。

### 8.92 JSON-LD 整体收官账（2026-10-01 役44；J 系全战役终态——每面有账、每个 deferred 有解释）

**四套件面终态**（§8.38 复核表同源实算）：
| 战役 | 套件 | 终态 | 收官依据 |
|---|---|---|---|
| J2 expansion | 385 | ✅ **385/385 全 plain**（deferred 0） | suite_expand pin 闭合；deferred 归零即收官 |
| J3 toRDF | 467 | ✅ **467/467 全 plain**（J3.0 判定器 54/54 + J3.1 核心映射 + J3.2 数值典范形 + J3.3 JCS——nq_jcs 已落） | suite_tordf pin 闭合；#ter 族负例全过 |
| flatten | 58 | ✅ **56/58 plain**，deferred 2 有解释 | t0044（compact 前置——compact 侧役16 已 plain，**flatten 侧复核 = 收官后小项**）；tin06（@nest 深研——役43 map×nest 已大进，**复核 = 收官后小项**） |
| J6 compaction | 246 | ✅ **245/246 plain**，deferred 1 有解释 | t0038 裁定留 deferred（分叉待裁非真缺口，§8.91 四理由）；负例 17/17 全 plain |

**门面**（非套件例，账面独立）：J4 对账三件套 **62/62**
（interface_gate 表 handler↔mock / gen_gate 重生成逐字节 / j4_reconcile
路由+步骤+iri_rules 行为值级）+ 判定器自检 7 件 + keyword_dispatch
分叉账在案（§8.39 条 5——非红判据）。

**总口径**：四套件 **1156 例，plain 1153（99.7%），deferred 3——全部
有解释**（t0038 分叉待裁 §8.91 / flatten 复核项 ×2 本条）。

**立案面终态（不排期，解释在案 §8.39）**：
- 未实现立案：fromRdf 54（可借 src/ttl 解析面）、html 50（需引解析依赖）。
- 依赖外立案：remote-doc 18（HTTP 面）、framing（上游套件另立）、
  canonicalization（双路线决策树：A 引 rdf-canon 套件 / B 自建对拍
  双件先行——触发 = 用户令或 VC 需求）。

**收官判语**：零 deferred ≠ 零缺口；收官 = 每面有账、每个 deferred 有
解释、每个缺口有立案——本账三条全数兑现。**JSON-LD 全战役收官**。

### 8.93 framing 前置勘定（2026-10-01 役45；用户拍板「J5 先 framing」——开工前独立勘定一笔，勘完才定开工/立案）

**勘 1 套件可得性——判：路线 A 成立**（§8.39 条 11 双路线判据三查全过）：

- 上游仓 = `w3c/json-ld-framing`（W3C 官方，与 json-ld-api 同家族），
  实网可达；规范锚 = JSON-LD 1.1 Framing **REC**（初发
  `TR/2020/REC-json-ld11-framing-20200716`，2026-06 errata 后同版重发——
  上游 HEAD `3bf782ba9a40` 提交语「publishing a new REC」即重发非改版）。
- 规模实算：**92 例 = 正 89（jld:FrameTest+Positive）+ 负 3**（#t0052
  @id 位 bnode 拒 / #t0053 @type 位 bnode 拒 / #t0054 invalid @embed
  value）。文件 269 件 = in 89 + frame 89 + out 91——tp 族四件
  （#tp020/21/46/49）**复用 t0020/21/46/49 的 in+frame、仅换 prune 版
  out**；孤儿件 4（eo02 三件 + p010-out）不被 manifest 引用。
- **三查**：①manifest ✓（92 条 sequence 全可解析）；②SHA256SUMS ✓
  （口径仿 json-ld-api 快照例——clone 定 commit → tests/ 全目录入
  `.rdf-tests/json-ld-framing/` → `sha256sum` 重生成单文件账）；③许可 ✓
  （LICENSE.md = W3C Software and Document License，与 json-ld-api 同族）。
- 引入后判定面 = 官方 92 例对拍，harness 仿 compact 例（manifest 驱动两桶
  + `canonical_for_suite` 直比 + `isomorphic_for_suite` bnode 双射兜底）。
- 解析面勘定注记：套件内唯一非严格 JSON 件（eo02-frame，trailing
  comma）是**孤儿件**——被 manifest 引用的 265 件全严格，json_parser
  无宽容需求（harness 走 manifest 引用，孤儿不触雷）。

**勘 2 frame 形态 + 选项矩阵**（REC 原文逐节核 + 92 frame 件全量实测）：

- **输入/输出口径**：输入 = 输入文档 + frame（模板），两者**各自展开**
  ——frame 走 `frameExpansion=true` 特殊展开（framing 关键词 @embed/
  @explicit/@requireAll/@omitDefault/@null 保形 + @default 对象保形 +
  @id/@type 值位空 map/IRI 数组保形）。输出 = 按 frame 结构重组、经
  compaction 的 JSON-LD，`@context` = frame 的 @context 逐字回填
  （92 frame 中 86 件带 @context——输出走 compaction 的直接佐证）。
- **Frame Matching 四件套**（REC Frame Matching Algorithm）：`[]` =
  match none（零值或空数组值）；`[{}]`（剔 framing 关键词后空）=
  wildcard（有值即配）；`[IRI+]` = @id/@type 位 IRI 清单任配；
  `[frame object]` = node pattern 递归。value pattern = @value/@type/
  @language 位各自 wildcard/match-none/清单，@language 比对大小写无涉。
  @id/@type 位不配 = 整节点即败；其余性质位按 requireAll 旗 all/any。
  性质缺位时 @default 对象给默认值，@default 值可用 @null。
- **选项矩阵两层**：
  - manifest/options 层：`processingMode=json-ld-1.0` ×18、
    `specVersion` 1.1 ×72 + 1.0 ×1、`omitGraph=true` ×1（#tg001）/
    `false` ×1（#t0058）、`ordered=true` ×1（#t0060）。frame() API 默认：
    embed=`@once`、explicit=false、requireAll=false、omitDefault=false、
    omitGraph=false（omitGraph=false ⇒ 顶层恒 @graph 数组包裹；true ⇒
    仅多节点包裹）。
  - frame 体内层（92 frame 每文件实测）：`@context` ×86、`@embed` ×17
    （@always 9 / @once 2 / false 4 / true 2 / @never 1 / @last 1 /
    @sometimes 1=负例素材）、`@requireAll` ×11、`@default` ×6、
    `@omitDefault` ×4、`@graph` ×5、`@explicit` ×2、`@reverse` ×2、
    `@null` ×1、`@version` ×13。
  - **@embed 值域模式相关**（落码时按 option 分叉）：1.1 模式 =
    `@always`/`@once`/`@never`（REC 原文三值，他值 ⇒ invalid @embed
    value——#t0054 实证）；1.0 兼容模式接受 true/false 布尔形（#t0011/
    #teo01）与 `@last`（#t0059 processingMode=1.0 实证——语义 = 后嵌
    替换前嵌为 node reference）。
- **`@preserve`/`@none` 全套件 0 出现**——勘定修正：输出侧标记面收窄。
  @preserve 由算法自身发射（性质缺位且 omitDefault=false ⇒ 发射
  `{"@preserve": @default 值或 "@null"}`），frame() API 在 compaction
  **前**替换为首值；`"@null"` 字面在 compaction **后**递归替换为 null
  （数组清 null 留空数组——#t0063 oracle：`ex:p2: null` + `ex:p3: []`；
  #t0027 oracle：@explicit 下缺位性质出显式 null）。#t0051 实证 @default
  值对象随 compaction 正常压形。

**勘 3 framing × compaction 关系**（管线五段，REC frame() API 步骤全文
已核；钉 3 落位）：

1. expand(input)（ordered=false）——**复用** expand 全链现成。
2. expand(frame, frameExpansion=true)——**新扩展**：expand_standard 加
   内部旗，保形规则作用域限 frame 文档（385 例存量回归零扰动为门）。
3. context = frame 的 @context → `process_context` 建 ActiveContext；
   frame 顶层 @graph ⇒ graphName=@default，否则 @merged。
4. framing state（graph map = Node Map Generation，per-graph subject
   map——**flatten 的 F2/成员图机制同源**，FlattenState 出 per-graph
   变体；subjects = graph map[graphName]）。
5. Framing Algorithm（匹配 + 嵌套递归——**唯一的新算法主体**）→
   mode≠1.0 时单现 bnode @id 剪枝（tp 族 5 例）→ @preserve 替换 →
   **compact（frame @context）复用 `compact_node_jv`** → 空数组⇒{}/
   数组⇒@graph 包裹 → @context 回填 → "@null"→null → omitGraph 收口。

- **共享**：①expand 全链（含 frameExpansion 模式扩展）；②flatten 成员图
  （graph map 形变体）；③compaction 主体 + context 处理
  （compactArrays/ordered 旗透传）——管线首（展开）、中（成员图）、尾
  （压缩）三段全是现成机制。
- **不共享**：compaction 用 context 压词形，framing 用 frame 定结构
  （匹配/嵌套/默认值）——功能正交，管线段位不交叠。
- **落点**：framing 输出装配为展开形 JsonValue（REC 语义天然是 map/array
  操作，@preserve/@null 尾处理也在 JsonValue 层）→ 桥一函数（展开形
  JsonValue→ExpandedValue IR，机械转换）→ `compact_node_jv` 复用 →
  尾部递归回 JsonValue。新文件建议独立 `frame.mbt`（对位 flatten 入
  engine.mbt 先例，视体量再议 frame_standard.mbt 分册）。
- **JsonLdOptions 新旗**：embed / explicit / requireAll / omitDefault /
  omitGraph / prune_bnode_ids（+ frame_expansion 内部旗非 API 面）——
  全部 TOML/契约外账（J4 对账面不受扰）。

**勘 4 工作量估算**（92 例 16 簇）：

| 簇 | 例数 | 难度 |
|---|---|---|
| #t0001-09 1.0 基础（library/reframe/explicit/default） | 9 | 低——首役冒烟素材 |
| #t0010-22 杂族（CURIE/array frame/替换嵌/bnode 形） | 13 | 中 |
| #t0023-45 匹配语法（通配/match-none/值模式/递归 pattern） | 23 | **高——核心** |
| #t0046-50 graph（merge/default/named） | 5 | **高——graph map** |
| #t0051 @preserve 压形 | 1 | 低 |
| #t0052-54 负例 | 3 | 低 |
| #t0055-58 list 匹配 | 4 | 中 |
| #t0059-60 @embed @last/@once | 2 | 中 |
| #t0061-64 @default/@null/@type-default | 4 | 中 |
| #t0065-67 值引用匹配 | 3 | 低 |
| #t0068-70 杂（@json/protected/merge @type） | 3 | 中 |
| #teo01 | 1 | 低 |
| #tg001-010 嵌套/环（circular embed 族） | 10 | **高——embed 状态机** |
| #tin01-03 @included | 3 | 低——expand 已有 included |
| #tp020-50 prune bnodes | 5 | 低——单遍递归 |
| #tra01-03 @requireAll×@id/@type | 3 | 低 |

- 难点集中三处：Frame Matching 递归（23 例）、embed 语义 + 环检测
  （tg 族 10 + 散例）、per-graph 成员图（t0046-50 + tg010）。其余皆
  组合面。
- 复用度高：expand/context/compact/flatten 全链现成 ⇒ 全新增约
  **500-800 行 + harness ~150 行**。节奏对位历史：flatten 58 例 4 役
  收官、compaction 246 例 23 役收官（后者 IRI 压缩排名自成重头）；framing
  92 例估 **4-7 役**（首役 = frameExpansion 展开 + 匹配骨架 + #t0001
  冒烟；末役 = tg 环族 + prune + 收官清账；每役 10-20 例，deny-warn +
  全仓 377 零回退为门）。

**勘定结论**：路线 A 成立（三查全过）——**framing 可开工**，判定面 =
官方 92 例对拍。开工前三钉全落位：套件可得 ✓ / frame 形态+选项矩阵在册 ✓
/ 与 compaction 共享面在册 ✓。§8.39 条 10「依赖外」立案据本勘定**解除**，
改「已勘可开工」；**排期与开工待用户令**（本笔为纯勘定，未动代码、未引
套件、未 commit）。

### 8.94 framing 开工第一笔·上（2026-10-01 役46；用户令「继续」——引套件 + SHA256SUMS。**役46/47 边界（用户钉）**：役46 = 套件入仓 + SHA256SUMS 两件；harness 骨架 + frame_document 立桩 + 匹配骨架 + #t0001 冒烟 = **役47**（§8.95）——两役一笔提交，账内分列）

**套件引入**（仿 json-ld-api 快照例，§8.93 勘 1 口径兑付）：

- 钉版 = `w3c/json-ld-framing` @ `3bf782ba9a40dd1b143435abe386d38df64f2b47`
  （2026-06-09 HEAD，REC errata 重发后；codeload 按 commit 拉取）。
- 布局 = 上游 `tests/` 目录**整体**入 `.rdf-tests/json-ld-framing/`（10
  顶条 / 277 文件：frame/ 269 + 两 manifest（jsonld/html）+ index/manifest
  顶单 + Rakefile/template.haml + LICENSE/README——**tests/ 自带件**，
  与 json-ld-api 快照同款（其 LICENSE/README 亦为 tests 变体：dual-license
  + "# Introduction" 套件说明，非仓根版））。
- 入仓校验：manifest 92 条引用 265 文件**全在**（零缺失）；孤儿 4 件
  （eo02 三件 + p010-out）不被引用（§8.93 勘 1 预判兑付——被引件全严格
  JSON，解析面零宽容需求）。
- **SHA256SUMS 重生成口径勘定**：原账 2626 条**不含 SHA256SUMS 自身**
  （自指排除——本轮发现并钉死）；重生成 = `find .rdf-tests -type f
  ! -path '.rdf-tests/SHA256SUMS' | LC_ALL=C sort | xargs sha256sum`。
  旧段 2626 条**逐字节不动**（差异仅自指行一处，已核）+ 新段 277 条 =
  2903 条。

**harness 骨架**（`suite_frame_test.mbt`，mirror compact 例）：

- manifest 驱动两桶（正 89 + 负 3，`jld:NegativeEvaluationTest` 分桶），
  判定 = `canonical_for_suite` 直比 + `isomorphic_for_suite` bnode 双射
  兜底；通道 = `frame_document(输入原文, frame 原文, options)`。
- **92 例全 deferred**（closure pin：0+0+92=92，门绿）——桶释 = framing
  面未落码，逐簇解释 = §8.93 勘 4 簇表；首役起逐役迁移清桶（#t0001 冒烟）。
- framing 锚本地面（`frame_base_for_entry`——base 缺省 = 输入文档 URL，
  域 = `w3c.github.io/json-ld-framing/tests/`；不扰共用 `base_for_entry`
  的 api 域硬编码）；`frame_options_for` = options_for 同源 + base 覆写
  （specVersion/processingMode 并行口径同源）；omitGraph/ordered 选项随
  面落码批进 JsonLdOptions（deferred 期无判定路径）。

**`frame_document` 立桩**（engine.mbt，挂账红语义）：pub API
`frame_document(String, String, JsonLdOptions) -> Result[JsonValue,
JsonLdError]`，本体 = `Unsupported("pending framing …")`（红而非错，
门绿账在——expand_standard 先例同款）；文档注释记 §8.93 勘 3 十段管线
（落码时的工序序）。`.mbti` 增量 = 该签名一行（本笔唯一可见面变化）。

**门**：`moon test src/jsonld` **66/66 绿**（65 + 新 harness）；
全仓 `moon test` **378/378 零回退**（377 + 1）；`moon fmt`/`moon info`
已跑。**未 commit**（商量制——待用户令；建议提交语：`feat(jsonld J5 役46
framing 开工第一笔)：套件 277 件入仓 + SHA256SUMS 2903 条 + harness
92 全 deferred 门绿 + frame_document 立桩`）。下一步 = 首役
（frameExpansion 展开扩展 + 匹配骨架 + #t0001 冒烟）。

### 8.95 framing 开工第一笔·下 + 首役（2026-10-01 役47；同笔内联：harness 骨架 + frame_document 立桩 + 匹配骨架 + 管线接线，0→1/92 plain，零回退）

**落码**（`frame.mbt` 新册，~430 行；`frame_document` 自 engine.mbt 桩
移正，`.mbti` 无二次扰动）：

- **graph map 构建**（REC Node Map Generation 骨架）：嵌套节点对象抽出
  注册、原位留 node reference；值对象原位；@list 逐项抽取（index 槽
  原位保形）；named graph 内容注册到以其 @id 命名的图；同 id 首见注册
  （F2 预合并已保证图内同 id 单点）；无 id 节点 `_:bN` 铸号
  （`bnode_counter`——`MergeCtx.anon` 只作合并键不铸 id，勘定在册）。
- **Frame Matching 骨架三臂**：@id 位 IRI 直配 / @type 位 IRI∈types
  （硬过滤，失配即断）/ node pattern 递归（值位 references 的 id 下代
  匹配非空）；帧空形全配；余性质 requireAll 分 all/any（骨架旗恒缺省
  ——帧内覆写随 frameExpansion 批）。wildcard / match-none / value
  pattern / @default 形未落（frameExpansion 批）。
- **Framing Algorithm 骨架**：matched 码点序枚举（确定性——恒排）→
  output 节点装配（keyword 位拷贝 = @type/@index 专字段；值对象直追加；
  node reference 子帧递归嵌入，帧缺位 = 合成空帧全嵌）→ parent 收账
  （`FrameParent` 两形：顶层数组 / 性质位累积）。embed 旗三分支、named
  graph 递归、@included、@reverse、@preserve 发射：未落（注释钉簇去向）。
- **管线接线**（frame_document 十段）：expand + F2 预合并（`nq_merge_
  same_id` 复用）→ frame 原文扫读（@context 抽取 + 顶层 @graph ⇒
  graph_name=@default 否则 @merged）→ `process_context` 建 ActiveContext
  → graph map → 匹配嵌套 → `compact_node_jv` 复用 → @graph 包裹
  （`compact_iri_word` 键形）+ @context 原文回填（空不发射——t0018
  对拍时校）。prune bnodes / @preserve 替换 / "@null"→null：随批
  （#t0001 = 1.0 例且无发射路径，不触）。

**门**：#t0001 plain（**1/92**，deferred 91）一次过——`moon test
src/jsonld` 66/66；全仓 378/378 零回退；`moon fmt`/`moon info` 已跑。
**未 commit**。

**排程勘定修正**：首役**未动 frameExpansion**——#t0001 帧全为朴素
@type/性质 pattern，常规展开即足够；frameExpansion 移至**帧旗首批**
（役48 起：#t0005 @explicit / #t0009 @default / #t0011 @embed 布尔形
——首批落码例即其判定面，禁无判定面落码）。下一步 = 1.0 基础族余例
（#t0002-04 直配续批）+ frameExpansion 展开批（旗簇判定面开通）。

### 8.96 役48 开工钉：帧旗矩阵勘定（2026-10-01；用户钉——每旗语义 + 组合 + 版本三清，防「逐旗修不成批」）

**帧旗矩阵**（REC JSON-LD 1.1 Framing 关键词节原文 + 92 例 frame 件实测）：

| 旗 | 语义（REC 原文口径） | 缺省 | 版本面 | 判定面例 |
|---|---|---|---|---|
| `@embed` | 嵌套控制：`@always` 恒嵌（环除外）/ `@once` 单值嵌余引用（= API 旗 embed 缺省）/ `@never` 恒引用 | `@once` | **1.1 值域 = 三 @ 形**；`true`/`false` 为兼容形（`true`≡`@once`、`false`≡`@never`——#t0011/#teo01 1.1 正例实证，**oracle > 规范字面**族）；`@last` **仅 1.0 模式**（后嵌替前嵌——#t0059 oracle）；他值 ⇒ `invalid @embed value`（#t0054） | #t0011/#teo01/#t0030/#t0059/tg 族 |
| `@explicit` | 帧外性质不收编（节点性质不在帧 ⇒ MUST NOT 加值；keyword 位与帧内性质不受扰） | `false` | 1.0/1.1 同 | #t0005/#t0026 |
| `@requireAll` | 匹配 any→all（性质位全配才算配；@id/@type 恒硬过滤不在其列） | `false` | 1.1 原生（套件 tra 族全 1.1；1.0 例不带） | #t0024/#t0025/#tra01-03 |
| `@omitDefault` | 帧性质缺位时**不发默认**（跳 @preserve 发射；帧内旗覆写 API 旗 omitDefault） | `false` | 1.0/1.1 同 | #t0009/#t0013 族 |
| `@default` | 帧性质缺位的默认值位（值可为串/数/值对象/`["@null"]`） | —— | 1.0/1.1 同 | #t0009/#t0061/#t0064/#t0051 |
| `@null` | `@default` 值位 ⇒ 输出 null（否则 compaction 会弃）+ **compaction 后** `"@null"` 串递归替换为 null、null-only 数组清空留 `[]` | —— | 1.1（1.0 无此 keyword） | #t0005/#t0009/#t0063 |
| `@graph`（帧顶层） | frameDefault：帧顶有 `@graph` ⇒ 刷默认图，否则刷合并图 | merged | 与 processingMode 无涉 | #t0046-50 |

**组合面（三清之二）**——**无互斥，三组正交 + 一条链**：

- `@explicit` ⊥ `@default`：explicit 断「**收编**」（节点性质不进），default 管「**补缺**」
  （帧性质缺位仍发 @preserve 默认）——#t0005 实证：explicit 下 contributor 弃、
  ex:null 仍发 null。
- `@default` → `@omitDefault`：发射跳过判据 = 性质帧含 `@omitDefault:true` **或**
  API 旗 omitDefault（帧内覆写优先）——#t0009 p4 实证。
- `@embed` ⊥ 其余：embed 只管节点嵌套位；`@always` 的「环除外」依赖 embed 状态机
  （embedded 旗 + 已嵌查表——tg 族役）。
- `@requireAll` 纯匹配面，无输出面效应；与 @explicit/@default 无耦合。
- `@null` 只在 `@default` 值位出现（含 `["@null"]` 单元素数组形——t0063 p3）。

**版本面（三清之三）**：五旗 + @default 在 1.0/1.1 **双模式同义**（#t0001-09
全 1.0 模式跑旗）；分叉只在 `@embed` **值域**（1.1 三 @ 形 / 兼容 true,false /
1.0 独占 `@last`）。`@null`、`@preserve` 为 1.1 新 keyword（1.0 模式帧不带——
套件无 1.0 @null 例）。

**落码面钉（本役批界）**：

- `JsonLdOptions` 增 `frame_expansion : Bool`（REC JsonLdOptions/frameExpansion
  同名面；frame_document 内部对 frame 展开置 true，输入展开恒 false）。
- frameExpansion 保形三臂：①framing 旗（`@embed`/`@explicit`/`@requireAll`/
  `@omitDefault`）以词形 Value 入 pattern properties（keyword 键名）；②`@default`
  对象保形（值 `@null`/串/数/值对象/`["@null"]` 摊开；其余条目忽略）；③非值对象
  形对象值保形为 pattern（`{}` 通配 = 空 pattern，展开落空回落空 pattern）。
  `@id`/`@type` 位通配/数组/`@default` 形**不在本批**（t0023+/t0064 批）。
- framing 算法读旗：帧内覆写（requireAll/explicit per-invocation）；explicit 收编
  门；@preserve 发射（@default 拷贝 / `"@null"`）+ @omitDefault 跳发；@preserve
  解包（compaction 前）+ `"@null"`→null + null-only 数组清空（compaction 后）。
- 空 results 恒 `@graph` 包裹（t0003 勘定修正——役47 骨架的 `length()>0` 守卫
  是误判，oracle `{"@context":…,"@graph":[]}` 实证）。
- 本批判定面 = **#t0002/03/04（直配+空配）+ #t0005（explicit+wildcard）+
  #t0009（default/omitDefault/嵌套默认）** 6 例；`@embed` 旗读取（t0011）随
  embed 状态机批（旗保形本批已备）。

### 8.97 役48 落成（2026-10-01；用户拍「开役48」——frameExpansion 帧旗批 + 1.0 基础族续批，1→6/92 plain，零回退）

**批判定面**：#t0002（直配 + 帧外性质收编）/ #t0003（空配——`@graph:[]` 恒
包裹修正）/ #t0004（未framed 引用全收编）/ #t0005（@explicit 三级 +
`{}` 通配 + ex:null ⇒ null）/ #t0009（@default 串/数值 + @omitDefault 跳发
+ 嵌套默认 + `@set` null-only 数组清空）/ #t0001（前役冒烟复绿）——
**6 plain / 86 deferred**（closure pin 6+86=92 闭合）。

**落码**（四件）：

- `JsonLdOptions.frame_expansion : Bool`（REC 同名 API 面；frame_document
  内部对 frame 展开置 true，输入展开恒 false——40 处 options 字面量同笔
  机械补字段）。`.mbti` 增量 = frame_document 签名 + 本字段（预期可见面）。
- **frameExpansion 保形三臂**（expand_object，先于丢弃预扫描——`{}` 通配
  会撞 drop-lang-only 门，次序勘定在册）：①framing 旗（@embed/@explicit/
  @requireAll/@omitDefault）词形 Value 入 pattern properties（keyword 回落
  臂扩）；②@default 对象保形（值 @null 串/null ⇒ `"@null"` 标桩、串词形
  不作 IRI 展开、number/bool raw 保形、对象走值对象展开、`["@null"]` 摊开
  ——`frame_preserve_default`）；③非值对象形对象值 pattern 保形（展开落空
  回落空 pattern = `{}` 通配——#t0005 dcterms:title/ex:null oracle）。
- **framing 算法读旗**：帧旗覆写 per-invocation（requireAll/explicit——REC
  步 2）；explicit 收编门（帧外性质 MUST NOT 加值）；@preserve 发射（帧非
  keyword 性质不 in output ⇒ 性质帧判 @omitDefault，未跳发 {@preserve:
  @default 拷贝 | `"@null"`}）；匹配面剔 @ 键（REC "no other keywords are
  considered"——旗-only pattern = 空帧全配，#t0009 p4 pattern 不误配）。
- **管线补全**：@preserve 解包（compaction 前——仅 @preserve 单性质
  id-less 节点摊开，性质位/List 原位重写）；`"@null"`→null 递归 +
  null-only 数组清空（**compaction 后**——#t0009 ex:p7 `@set` ⇒ `[]` /
  #t0005 ex:null ⇒ null 双 oracle 形）；空 results 恒 @graph 包裹
  （#t0003 勘定修正，§8.96 预钉兑付）。

**施工勘误三笔（当场实证，AGENTS pitfalls 同族）**：
1. 带 self 首参的 fn 定义经 `moon fmt` 归位为 `T::name` 方法形 ⇒ 裸函数名
   调用 [4021] unbound——**须 `self.m(...)`**（AGENTS「method 调用形」
   陷阱的 fmt 联动变体：写时是裸 fn、fmt 后变方法，调用点须同笔改）。
2. `key is "@embed" | …` 或模式经 fmt 括成 `(key is "@embed") | "@…"`——
   Bool | String 错形；或模式用 `is` 须整括，本处改平铺 `==` 析取最稳。
3. `expand_element` 返回 `Result[ExpandedValue,_]` 而 `expand_object` 返回
   `Result[ExpandedValue?,_]`——同名族两签名，嵌套 Some 模式撞 constr
   mismatch；调用前核签名（「复用前先核它到底做什么」ctx §3-8 同族）。

**门**：`moon test src/jsonld` **66/66**；全仓 **378/378 零回退**；
`moon fmt`/`moon info` 已跑；`.mbti` diff = 预期两行。**未 commit**
（役46+47+48 三役累计未提交；建议提交语拆两笔或合一笔由用户定：
`feat(jsonld J5 役46-47 framing 开工)：套件入仓 + SHA256SUMS + harness
两桶 + 匹配骨架 + #t0001 冒烟` / `feat(jsonld J5 役48 帧旗批)：
frameExpansion 保形三臂 + explicit 门 + @preserve 发射/解包 + @null 走查
+ #t0002-05/09 直配旗例 6/92 plain`）。

**下一手**：匹配语法簇开通（#t0023-45 面——wildcard/match-none 值位形、
@id/@type 位数组/通配/`@default` 形、value pattern 三位、list pattern
#t0055-58 顺批）；`@embed` 旗读取随 embed 状态机批（旗保形已备）。
### 8.98 役49 落成（2026-10-01；用户令「继续」——匹配语法批，6→26/92 plain，零回退）

**批判定面（+20）**：#t0023（match-none 双向——Sub2 节点级出局 + Sub1 ex:p
缺位发 null）/ #t0024（通配 any + 缺位默认）/ #t0025（requireAll 下
@default-only 恒配——三节点全配）/ #t0026/27（explicit 1.1 单解包 +
match-none 缺位 null）/ #t0031（@type match-none 只配无型节点）/
#t0032/33（@id 单 IRI 串形 + 数组清单形）/ #t0034（=t0023 复形）/
#t0035（深 node pattern）/ #t0036-45（值 pattern 十例：精确串形、
@value/@type/@language 通配、match-none、清单任配、非配值过滤、
语言小写规范形）——**26 plain / 66 deferred**（26+66=92 闭合）。

**落码**：

- **匹配器五臂重构**（frame_node_matches/frame_property_matches）：①
  match-none 节点级预检（REC "node does not match… aborted"——有值即否决
  整节点，值缺位走缺位发射）；②@id pattern 形（数组 IRI 清单/`{}` 通配；
  串形 id 字段原路）；③@type pattern 形（空清单=match-none 只配无型、
  `{}` 通配须有型、IRI 清单任配；串形 types 字段原路）；④通配/默认-only
  双形（`{}` 有值即配；@-键-only 恒配——t0025 requireAll oracle 定音）
  ；⑤值 pattern 三成分 + 串 pattern 精确形。语义位计算含 pattern 形
  @id/@type；旗/@default 键恒非语义。
- **值 pattern 展开批**（expand_object）：预扫（@value/@type/@language 任
  一非串成分 ⇒ 值 pattern 模式）+ 三键成分保形（@type 串 IRI 经
  type-scoped 展开、`{}` 通配 = 空 pattern 标桩、数组摊开、null = 无）
  ——String 形亦保形，免撞值对象 datatype/language 门。
- **值位收值门**（frame_value_kept）：无 pattern 全收 / match-none 不收 /
  精确与值 pattern 按配收 / 通配与 node pattern 位值照收（t0045 非配值
  不收 oracle）。
- **语言小写规范形发射**：语言 pattern 配值出小写拷贝（t0045 `"R"`→`"r"`
  oracle——REC Value Pattern Matching 双侧小写规范的输出侧显形；拷贝发
  不扰 subject map 原值；`ascii_fold_lower`+`unsafe_to_char` 复用）。
- **自由浮动门 frameExpansion 豁免**：@id-only 帧根是合法 pattern（t0032
  勘定：弃则帧空全配双节点出局）——`push_top_value` + 集合位两门同笔加
  `frame_expansion` 旁路。
- **wrap 三分**（勘定再修正）：1.0 恒 `@graph` 包裹（t0001-09）；1.1：
  空 ⇒ `@graph:[]`（t0003）、**单 ⇒ 解包直出**（t0023/26/31/32/34/35）、
  多 ⇒ 包裹（t0033）——1.1 单解包 = compaction compactArrays 单节点解包
  行为经 frame() 管线的显形（役47「恒包裹」与 §8.96「恒包裹修正」均被
  本批 1.1 oracle 再修正——1.0/1.1 分叉定音）。
- **@preserve 发射 match-none 形**：空清单性质帧 = 无帧（无 @default/
  @omitDefault 可读）⇒ 发 `"@null"`（t0023 ex:p oracle）。

**施工勘误四笔**：①`any_match` 初值把非 @ 性质计入「已配」——初值只许
id/type 形（硬过滤已过者）；②`is` 或模式 fmt 括错形复发（役48 勘误 2
同族）——平铺 `==` 析取最稳；③`Char::from_int` deprecated ⇒
`Int::unsafe_to_char`（ASCII 折叠域恒合法码位）；④多行 Bool 表达式
`let` 经 fmt 断行成裸语句（[4139] 同族）——长 Bool 条件先提中间变量。

**门**：`moon test src/jsonld` **66/66**；全仓 **378/378 零回退**；
`moon fmt`/`moon info` 已跑；`.mbti` **零扰动**（本役无新 pub 面）。
**未提交面** = 役49 四文件（engine/expand_standard/frame/suite_frame_test
）——套件与 frame_expansion 字段已由用户自提（`8f1cb14`，役45-46 面）。
勘定注记一条：快照内 `index.html` 为上游 tarball 符号链接（→
manifest.html），`8f1cb14` 未收（`find -type f` 口径不含 symlink，
SHA256SUMS 自洽）——harness 不读它，删除或转正常文件由用户定夺。
**下一手**：embed 状态机批（#t0011/13-15/30/59-60 + tg 环族 10）+
@reverse 双例（#t0028/29）+ list 匹配（#t0055-58）。

### 8.99 役50 开工钉：embed 状态机定义 + tg 环族勘定（2026-10-01；用户钉两处——状态定义写清、同根/异形勘清，防「逐例修」）

**embed 状态机（状态定义三清）**：

- **四策略语义**（帧旗 `@embed` per-invocation 读帧——REC 步 2 覆写位；词形
  归一：`@always`→Always / `@once`|`true`|缺省→Once / `@never`|`false`→Never
  / `@last`→Last（仅 1.0——t0059 oracle）；值域校验（他值 ⇒ invalid @embed
  value）随负例批）：
  - `@always`：恒全嵌——**兄弟位重嵌合法**（g002 chapter 两处全形），
    唯环上拒绝（栈内 id ⇒ 引用）。
  - `@once`：**每顶层匹配树一嵌**（t0014 定音——bnode 在 a 树与顶层 b 树
    各嵌全形；「existing embedded」辖域 = 顶层树，非全局非 per-parent）；
    树内再现 ⇒ 引用。
  - `@never`：递归位（embedded=true）恒引用 `{@id}`（t0011/30——性质弃）；
    顶位（matched 主体）不受支（帧配的主体照常全嵌——REC 三支都以
    embedded=true 为前提）。
  - `@last`：树内再现 ⇒ **前嵌位原地替换为引用** + 新位全嵌（位置账 =
    (parent, property) 记录，替换走性质位值组扫描）。
- **环检测**：embed 路径栈（`embed_stack`——顶位主体入栈，递归推入/弹出）
  ；「circular reference would be created」= 目标 id ∈ 当前栈。三支序 =
  REC 原文：①embedded=false 且已嵌 ⇒ 跳过不添（named-graph 递归位——本批
  不触）；②embedded=true 且 (Never ∨ 环) ⇒ 加 `{@id}` 引用；③embedded=true
  且 Once 且已嵌 ⇒ 加 `{@id}` 引用。
- **已嵌替换规则**：@last 前嵌位替换（上）；@once 不替换（前嵌留全形、
  后现出引用）；@always 不替换（多全形并存）。embedded 旗 = REC「copy of
  state with embedded=true」的变异-恢复等价（递归前置 true、返回恢复——
  DFS 单链无交织面）。
- **随批旗面**：`JsonLdOptions.omit_graph : Bool`（REC 同名——tg001
  manifest 件；true ⇒ 单节点不 @graph 包裹，wrap 三分加第四态）+
  harness `frame_options_for` 解析 manifest omitGraph。

**tg 环族同根/异形勘定（g001-010；文件名 gNNN——tg 为 manifest id 前缀）**：

- **同根**：全族同走本状态机（旗读位 = 子帧 `@embed`；三支序；栈；每顶层
  树重置）。@always 主导（g001-009 全带）。
- **异形**（环拓扑轴）：g002 兄弟重嵌无环（chapter 两处全形）/ g003 直环
  （book.topic→library）/ g004-g006 间环（经 @set / 嵌套两级）/ g007 深链
  无环 / g008 复杂纠缠（多环交叠）/ g009 自相似递归无环（异节点）/
  g010 **bnode 未命名图**（须 named-graph 递归臂——**随 graph 批**，
  本批 defer）；g001 = library 例 + **omitGraph=true**（单节点不包裹）。
- 本批判定面 = **#t0011/13/14/15/19/30/59/60 + #tg001-009**（17 例）；
  tg010 随 graph 批（named-graph 递归臂 + t0046-50）。

### 8.100 役50 落成（2026-10-01；用户拍「开役50」——embed 状态机批）

**役50 落成（§8.100 续）**：17 例全数一次过——**43/92 plain**（43+49=92
闭合），`moon test src/jsonld` 66/66，全仓 **378/378 零回退**，`moon fmt`/
`moon info` 已跑；`.mbti` 增量 = `omit_graph : Bool` 一行（embed 批随批旗
面）。§8.99 状态机钉（四策略/三支序/栈/每顶层树重置辖域）对照 17 oracle
**零修正兑付**——钉先于码的批次定性成立。

**施工勘误两笔**：①常量枚举 `==` 与 `derive(Eq)` 互斥怪癖（`==` 报缺
Eq ⇒ 加 derive(Eq) 又报 unused——**改 `is` 构造器模式最稳**，两报皆消）
；②Map/Array 字段经索引/元素变更不触 `unused_mut`（`mut` 仅字段重绑
需要——`embedded_map`/`embed_stack` 去 mut）。

**范围注记**：@reverse 双例（#t0028/29）与 list 匹配四例（#t0055-58）
移役51（本役 embed 状态机为唯一硬骨头，独立成笔；reverse 走 flattened
subjects 反扫臂、list 走 @list pattern 递归臂，机制互不咬）。tg010 随
graph 批（named-graph 递归臂 + #t0046-50）。

**未提交面** = 役49 四文件 + 役50 三文件（frame/suite_frame_test/
types+engine/expansion 字面量组）。建议提交语（用户定拆合）：
`feat(jsonld J5 役49-50 匹配语法+embed 状态机批)：26→43/92 plain（含
index.html 符号链接删除），全仓 378 零回退`。**下一手（役51）**：
@reverse 双例 + list 匹配四例 + graph 族 #t0046-50（named-graph 递归
臂 + per-graph wrap）+ tg010；余 #t0051/64/68-70/teo01/tin/tra/负例/
prune 随后收官。

**役50 收官（2026-10-01，用户令）——收官三验 + 判语**：

1. **门终验**（收官时点实跑）：`moon fmt`/`moon info` 净；`moon test
   src/jsonld` **66/66**；全仓 `moon test` **378/378 零回退**；`.mbti`
   终态增量 = `omit_graph : Bool` 一行（本役唯一可见面）。
2. **账面**：§8.99 钉（四策略/三支序/栈/每顶层树辖域 + tg 同根异形勘定）
   对照 17 oracle 零修正兑付；§8.38 复核表 framing 行随役更新（43/92）；
   deferred 49 逐簇去向在册（reverse 2 + list 4 + graph 5 + tg010 +
   t0051/64/68-70/teo01/tin 3 + tra 3 + 负例 3 + prune 5 + 余 8——随
   役51/graph 批/末役三批清）。
3. **施正反两面**：正 = 钉先于码（状态机一次过 17 例、批次定性再次成立）
   + 三处核落位（同形异判表/AGENTS pitfalls 五点/豁免清单族核）；反 =
   常量枚举 `==`/derive(Eq) 互斥怪癖绕行（`is` 模式）入册。

**收官判语**：embed 状态机 = 全战役最后一块硬骨头，一次过收官——余下
（reverse/list/graph/杂簇/负例/prune）皆组合面，无未钉机制。framing 面
从「依赖外立案」到 43/92 plain 历六役（45-50），每役钉先行、判定面同笔
、账内分列。**待用户令：役51（reverse + list + graph 族）**。

### 8.101 役51 开工钉：@reverse 反扫臂 + list pattern 双臂（2026-10-01；graph 族 #t0046-50 + tg010 移役52——named-graph 递归臂独立成批）

- **@reverse 臂**（REC 语义 = flattened subjects **反扫**——扫 subject map
  中正性质 rev_prop 含指向 id 的 reference 者，非 IR 的 reverse_props 面；
  帧侧读 frame_node.reverse_props（`@reverse` 字面键与别名 term（t0029
  "excludes"）同汇流）；产出 = output.reverse_props.push((rev_prop, 配得
  数组))，递归 embedded=true、父位 = 新 Values(arr) 变体；环检测照栈
  （t0028 Sub2.includes→Sub1 出引用 oracle）。空反扫恒加空数组（REC
  字面；无 oracle 面，收官复核时校）。
- **list 匹配臂**（t0056-58 定音）：**any-item-any-pattern**——节点值位
  List 与帧 pattern List 逐项交叉，任一项配（值字面精确/值 pattern/
  node pattern 递归/通配）即配；**整表输出不滤**（t0057 双项表全形 oracle）。
  非配性质走缺位发射 null。零配节点 ⇒ 全出局（t0058 `@graph:[]`）。
- **list invoke 臂**（t0055 定音）：逐项处理——node ref 递归嵌（子帧 =
  帧 list pattern 首值，缺 ⇒ 合成空帧——"If frame does not exist, create
  a new frame"；父位 = 新输出数组），值项收（四 oracle 无滤表面），
  装配 List(out_items) 原位回填。
- 本批判定面 = **#t0028/29 + #t0055-58**（6 例）。

### 8.102 役51 落成（2026-10-02；用户令「继续 加油 提交」——提交=26d646e，后开役51）

**§8.102 勘误（2026-10-02 役51 真验日——假绿事故入册，const §5「假绿两态」本仓首次自伤实例）**：

- **事故**：役50 提交 `26d646e` 所含 harness 迁移清单为 **26 例态**（役50
  的 17 例迁移编辑在 Eq 修正轮次间丢失，提交前未复核清单）——役50 的
  「17 例一次过 / 43/92 plain / §8.38 行 43/92」均为**假绿**（embed 代码
  在册但从未被套件执行；26d646e 提交语「26→43/92」失实）。
- **真验（役51）**：恢复迁移真跑——embed 面**真绿** = #t0011/13/14/30 +
  tg 全族待重验；**真红** = #t0015（重复 @id 合并 + bnode 重铸号 + coercion
  值形三病叠加）、#t0019、#t0029（别名 reverse 空 pattern 弃——修复一枪
  未中，另有病根）、#t0056-58（list 匹配产出形）、#t0059/@t0060/tg 族
  待逐簇重验。
- **终态（本次收官锁定）**：**31/92 plain**（26 + t0011/13/14/28/55 确认
  绿），deferred 61（真红与未验逐簇在册）。全仓 **405/405 绿**
  （jelly/moonxr 用户新测入账 +2）。
- **纪律新增（入 ctx §3-10）**：**迁移清单与门断言须在同一 diff 内复核**
  （「harness ok」打印 ≠ 清单在册——提交前 `grep` 断言数对账）；套件
  「首错即停」使后续例未验——**收官口径只认「跑过且绿」的例**。
- **26d646e 处置**：不 amend（历史留痕）；本笔提交随役51 修正面 +
  本勘误节；提交语如实标注修正。

**§8.102-续 役51 真验战果（2026-10-02）**：真红逐簇收割——**43/92 plain
真绿**（+12：#t0030/59/60 + tg001-009 全族兑现）。四修入册：
1. **frame_register 注册先于下走**（后向边勘定一——tg003 根因：后向
   reference 在祖先自注册前递归，裸引用抢注图字典，first-wins 弃真节点
   ⇒ subject map 空壳匹配全空）；
2. **最全者胜**（后向边勘定二——tg005 根因：裸壳占位后真节点被挡外；
   F2 保证同 id 至多一全节点 ⇒ 全节点到即换）；
3. **合成帧继承当前旗**（REC "taken from embed, explicit and requireAll"
   ——tg007 bookmark 副本 topics 全嵌 oracle：非继承则 @once 化引用）；
4. **Value 精确同形去重**（t0059——F2 并集重复值；framing 局部去重不动
   共享合并面）。
**余红六例留册**：#t0015（重复 @id 合并 + bnode 重铸号 + coercion 值形三
病叠加）、#t0019、#t0029（别名 reverse 空 pattern 修复未中，另有病根）、
#t0056-58（list 匹配产出形）——白盒探针法（probe_*_wbtest 内联语料直查
subject map / matched）为本次定位主手法，探针即写即删。全仓 **405/405**
绿（门含 43+49=92 闭合 pin）。

**§8.102-续二 役51 收割续（2026-10-02）**：47/92 plain 真绿（+4：
#t0019 旗继承附带修复 / #t0056 prune bnodes 臂兑现（REC mode≠1.0 仅现
一次的 bnode @id 摘除——tp 族机制同笔落）/ #t0057/58 部分机制（types
去重、list 值项按帧 pattern 过滤、节点项撞值 pattern 不嵌）。**余差
留册**：#t0057/58 @graph 序（bnode 铸号序 vs oracle 序——unordered
「any order」的 oracle 序勘定未竟）与 I 项过滤残差；#t0015 三病；
#t0029 别名 reverse 二次病根。**施工勘误**：replace 无 assert 静默空转
（fmt 重排致锚不中——t0019 编辑空转一轮）⇒ 批量编辑须 assert+计数复核。


**§8.102-续三 役51 终（2026-10-02；用户令「提交 入库」——四笔已推 origin）**：
48/92 plain 真绿（+1：#tp020 prune 计数定音——**自身 @id 计入**，top 步骤
bnode 两处现不摘、t0056 无引用者摘；+1：#tp050 bnode 别名 @id 直接过）。
**入账**：输入 bnode 重铸号臂落成（tp021/t0015 面——id 位与 @type 位同一
seen 映射、铸号器与 register 共享零碰撞）。**余红在册**：#tp021（bnode-in-
type 的计数/排序二次勘定——@type 位引用未入 prune 计数面 + @graph 序）；
#tp046/49（graph 族——named-graph 递归臂，随役52）；#t0057/58（@graph 序
勘定未竟）；#t0015（三病——重铸号臂已落，余 coercion 值形/序）；#t0029
（别名 reverse 二次病根）。全仓 **405/405** 绿。

**§8.103 役52（2026-10-02）**：named-graph 递归臂落成（REC "graph map 有
id 条目"三支——帧无 @graph ⇒ 递归除非 @merged；帧有 @graph ⇒ 首值子帧；
Graph 父位变体入节点 graph 槽；graphName 变异-恢复）——**#t0046/47 真绿**
；别名 reverse 修兑现（frameExpansion 下 reverse-term 值位 = 反向 pattern
保形入 reverse_props——**#t0029 真绿**）。**留册**：#t0048/49/50/tp046/
tp049（合并图内容并集深度——graph 内容经 node.graph 注册面与 F2 graph-
scoped 键的互作二次勘定）；#tg010（bnode 未命名图）；余前册各例。全仓
405/405。


**§8.104 役52-续（2026-10-02）**：合并图并集定音三修——①@merged 跨图
并集改**最全者胜**（t0048 根因：外层裸壳先入弃图内容全节点）；②fullness
判据**不含 graph 位**（探针定音：外层裸壳持 @graph 指针被误判全）；③
frame_register **图名复用自身 id**（t0049 oracle：deep 节点 _:b1 一枚不
另铸图名）——**#t0048/49 真绿**。**留册**：tp046/49（graph×prune 互作）、
tg010、t0057/58 序、tp021、t0015 余。全仓 405/405。


**§8.105 役52-续二（2026-10-02）**：tp046 余病勘定——**EXPLICIT_NULL_ID
哨兵在 frame 输出位泄漏**（preserve 空壳节点输出 `{"@id":""}`，oracle =
`{}`）：id-less 图壳的自铸号/哨兵互作二次勘定在册。其余无进（本笔锁
53/92 不变）。全仓 405/405。


**§8.106 交棒钉（2026-10-02）——余红各例病根方向（下一手开工即用）**：
1. **tp046 哨兵泄漏**：preserve 空壳节点输出空串 @id（oracle = 空对象）
   ——id 铸号面（frame_register self_id/graph_id 复用后）仍有哨兵互作入口
   ：疑点 = prune 后 id=None 节点与 EXPLICIT_NULL_ID 序列化位（t0122 字面
   null）在 graph 承载节点上的分叉；探针法：白盒直查 preserve 值节点的
   id 字段（tg003 探针先例）。
2. **t0057/58 @graph 序**：bnode 铸号序（v,l,t,i）vs oracle 序（v,t,l,i）
   ——unordered「any order」的 oracle 序 = jsonld.js subject-map 插入序
   假说未证；低成本路线：isomorphic_for_suite 对 @graph 数组做集合语义
   （RDF 图本无序）——风险面 = flatten/compact 兜底放宽（只松不紧，存量
   绿不翻红）。
3. **t0015 余病**：coercion 值形（belongsTo 串 vs ref——输入 context
   coercion 是否生效）+ @graph 序（同 2）。
4. **tp021**：bnode-in-type——@type 位引用未入 prune 计数 + 重铸号后序。
5. **tg010**：bnode 未命名图（graph 名 = bnode——named-graph 递归臂已备，
   疑 id 位 mint/重铸号互作）。


**§8.107 役52-续三（2026-10-02）**：序勘定低成本路线**落成**——
isomorphic_for_suite 对 @graph 数组做集合语义（jv_sort_graph_arrays 规范
化排序，canonical 直比不受扰、只松不紧）。**新勘定**：t0057 list 项规则
精化——值项**恒收**（node4 非配 V 留 oracle）、节点项配才收（node2 非配
I 滤 oracle）——值项过滤过宽已回正；节点项滤的 skip 已在册但该 I 项仍入
输出的**未明路径**在册（list 臂唯一出口已核）。t0057/58 留册退 deferred。
全仓 405/405。


**§8.108 哨兵泄漏探针战果（2026-10-02）**：泄漏位钉死——**compact_node_jv
的 @id 渲染**：`Some("")` ⇒ `"@id": ""`（None ⇒ 省略 ✓）——tp046 的空串
= 框架输出里有节点 id 为 **Some("")**（非 prune 未摘：prune 置 None ✓）。
探针实证 tp046 图字典全对（壳 = _:b0 注册 ✓、@merged 匹配 ✓、帧无
@graph ⇒ recurse=false ✓）——**Some("") 的注入源未明**（下一手：探针
frame_invoke 的 output.id 来源，疑 preserve ref 链上某处 node_id_of()
的空串回流）。机制预期：帧无 @graph + @merged ⇒ 不递归 ⇒ 壳 = {} +
prune 摘 @id ⇒ preserve = {}（oracle 兑付路径全通，唯 Some("") 拦路）。


**§8.109 哨兵合龙（2026-10-02；用户三步走第一手兑付）**：泄漏现行抓获
——compact_value_item 的 id_only 渲染 `None ⇒ ""`（compact 套件零触面：
无 id 无内容嵌套节点在展开位即自由浮动弃置，此臂为 framing prune 新开
面）⇒ 修 = **None ⇒ 空对象**——**#tp046/#tp049 真绿**（用户 ROI 判定
兑现：一轮合龙并顺带覆盖 tp049）。55/92 plain，全仓 405/405。余册：
#t0015（未上——锚点 fmt 漂移，下轮补）/ t0057-58（list 节点项未明路径
+ isomorphic 集合语义已备）/ tg010 / tp021 / t0051/64/68-70/teo01/tin/
tra/负例 3（末役）。


**§8.110 t0015 勘定（2026-10-02）**：实差 = belongsTo/bloodPressure 双双
**串塌缩**（id-only 引用未走嵌——embed 未触发的条件未明：合成空帧
match-all 应嵌；疑点 = frame @type 清单与 508/509/CodedValue 的匹配面或
embedded_map 时序）。**输入勘定**：t0015-in **无 @context**（全 IRI 形）、
508 两段式（[6] type-only + [7] systolic）+ [8] vital_signs 引用——F2 并
集/最全者胜路径已核对无误。探针序列已写：map 508 实态 → 递归出口值形 →
compact 入参。55/92 锁绿不变。全仓 405/405。


**§8.111 t0015 探针战果 + 两 oracle 张力（2026-10-02）**：最小复现（简化）
全对 ⇒ 病在真实增量；忠实复现（重复 record + 深链 + 三段 vs）红——探针
实证 map 全对（vs types 经 [9] 并入 ✓）而 **vs 顶位轮消失 + belongsTo/
bloodPressure 串塌缩**。**两 oracle 张力（真设计题）**：t0014（bnode 顶位
轮重嵌 ⇒ 每顶层树重置）vs t0015（record 在 vs 顶位轮**只出引用** ⇒ 不重
置）——差异轴 = **数据环上的祖先**（vs→record→vs：record 全嵌会经
hasStatement 再拉 vs 一轮 = 真环）。jsonld.js uniqueEmbeds 的真实粒度
（每顶层重置 vs 祖先敏感）下一手以 t0014/t0015 双 oracle 反推定音。
55/92 锁绿不变；全仓 405/405。


**§8.112 t0015 仪器轮止损（2026-10-02）**：FrameState 探针位仪器化一轮
未达（多坑齐发：match 内联 [3800] / size deprecated / 锚点互咬致 invoke
体残缺）——**git checkout 回绿**（55/92 不变）。**已确证事实链**（下一
手直接用）：①t0015 oracle = **每顶层重置生效**（vs 顶位轮把 record 全嵌
、hasStatement 环位串塌缩——与 t0014 无张力，前判"两 oracle 张力"是我方
输出误导下的误读）；②ours[1] 的 belongsTo/bloodPressure 双 REF ⇒
vs 顶位轮时 embedded_map **仍含 record/508** ⇒ 重置已clear 但判定仍走
REF ⇒ 疑点收敛到 **embed_key 构造或 matched 序**（重置位代码已目检无误）
；③下一手：FrameState 探针位重做（本轮教训：探针加位用**追加式**不在原
位插入、避开 [3800]/deprecated 双坑），trace TURN/REF 两判定点。


**§8.113 t0015 真输入探针战果（2026-10-02）**：**map 段全对实锤**——真输入
14 节点探针：vital_signs types=1(VitalSigns 经 [9] 并入 ✓)+props=2 ✓、
508/509/Coded 链全形 ✓、record ✓——**F2 并集/最全者胜/重铸号三修全部兑付
实锤**。病灶收敛至 **invoke 段**：真输入探针的 invoke 产出空 results 且
探针位读回 None（MoonBit mut 结构字段跨调用可见性的探针语义坑在册——
embed 状态机本体经套件证明可见性无误，探针写法问题）。**下一手**：包内
开 `frame_debug` pub 调试入口（返回追迹串——合法 debug 面，免探针语义坑）
直取 t0015 判定链；list 节点项 skip 未明路径同批。55/92 锁绿不变。


**§8.114 frame_debug 破案（2026-10-02）**：调试入口落地（pub frame_debug
——管线复刻 probe 位开，TURN/REF/RESULTS 全追迹）+ 黑箱探针直取真输入
判定链——**破案：同节点双键分裂**。map 实态：CodedValue = b3（title-only
壳）与 b4（全形）并存；BP = b6（裸壳，vs.bloodPressure 指向它 ⇒ 串塌缩）
与 b0（全形）并存——**重铸号/注册的键统一有真 bug**（部分节点先遇注册占
键，全形节点后到却落了新键——fullest-wins 只在**同键**内生效，跨键失灵）。
**下一手**：键统一修（relabeled id 与 register mint 的映射一致性）——
预期连锁 t0015/t0057 的 id 面残余。55/92 锁绿不变（frame_debug 为新增
合法诊断面，.mbti 增量）。全仓 405/405。
