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
- **vocab 位 base 门控（勘定挂账，2026-09-26）**：vocab 位键展开在无 @vocab 时
  规范语义 = 原样返回、**不落 base merge**（#t0003 oracle：未映射 term 必须丢弃）。
  **挂「vocab 位 base 门控批」**（t0051 解挂前置）。harness 默认 base 注入
  （document location 约定，t0051 需要）**禁止先行单独落**——实测全局注入即刻
  破 #t0003（未映射键被解析成绝对 IRI 而保留，本应丢弃）。**注入与门控必须
  同笔落**：先门控、后注入；任何一边单独落 = 引入红例。

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
- 挂账：harness per-case options（specVersion 注入）未实现 ⇒ 1.0 负例 6 条迁移挂此；
  RFC3986 完整 IRI 解析（点段消除等）挂后续（#t0092 oracle 证实 raw 拼接即预期）。

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