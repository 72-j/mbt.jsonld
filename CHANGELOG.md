## 0.1.2（2026-10-31）

工程面版本：新增 quicktest 随机状态机测试件（**数据集守恒律机**）——pbtgen
QuickMachine 三面 TOML（`quicktest/`）生成骨架 + P0 接框架真面；对外 API 零变化。

### 新增（测试面）

- **`quicktest/` 数据集守恒机**：Empty→Seed→Ledgered 状态机，Ledgered 环上
  `AppendQuad`（载荷选 quad 池）+ `Roundtrip`；被测性质 = 守恒律双口径——
  ①字面集守恒（`to_rdf(from_rdf(台账))` 键集 == 台账键集，bnode 标签键面规约）
  ②图同构守恒（两轮 `from_rdf` 产物 `isomorphic_for_suite` 同构，bnode
  结构身份保真）。随机 60 例 + 固定脚本回归基线（含重复追加挡板见证）+
  单例覆盖门；固定守恒罐四件（Seed 基线 / 全池含 bnode / 重复防御 /
  模型-系统双执行同步）。
- **模块依赖**：`moonbit-community/quickcheck_statemachine@0.0.1` +
  `moonbitlang/quickcheck@0.15.1`（仅 quicktest 测试面消费，产品面零涟漪）。

### 口径

- 台账集合语义：`valid` 在生成期挡重复追加（模型镜像池索引集）；quad 池
  6 条与 `ref_id_range` 一对一（IRI 宾词 / 朴素字面量 / 语变 / 型标 /
  bnode 主词 / bnode 宾词）。
- 读数：native 与 wasm 各 548/548（含 quicktest 13 例）；产品 `.mbti`
  零漂移。

## 0.1.1（2026-10-09）

发布合规修正版：JCS 能力兑现宣称（真 RFC 8785 序列化出口晋 pub）+ CLI 换线 +
语料锁版修锁；评审役四面全绿 + 发布合规八道门收口（详见 `review.md` §1.4/§1.5）。

### 新增 API

- **`jcs_serialize`**：JCS（RFC 8785）规范化序列化直出——键 Unicode 码点序、
  字符串转义 §3.2.2.2、数值词形 = ECMAScript `Number::toString`
  （本体经 #tjs01~23 oracle 全绿）。

### 修正

- **CLI `json-canonical` 接真 JCS**：0.1.0 经 `json_canonical`（对拍归一器，
  键长度序）误称 JCS——现改接 `jcs_serialize`，输出码点序。
- **`json_canonical` 定位改口**：重定位为对拍归一器（比对用，非 JCS）；
  README 四处与 quickstart 第 7 节同步。
- **语料锁版修锁**：`rdf-canon/manifest.csv` 出生错配（自 J7 入树未变而
  SHA256SUMS 记数不符）——同笔修锁，复验 **3068/3068 OK**。

### 勘误（0.1.0 补遗）

- 0.1.0 CHANGELOG 漏列 `jsonld_keyword_route`（单数，init 既有）。
- 0.1.0「全量选项面」实列 11/12——`JsonLdOptions.expand_context` 漏列。
- 0.1.0「语料 SHA256SUMS 锁版 2626 件」系 J0 单套件旧口径，实为 **3068 件**
  （json-ld-api / json-ld-framing / rdf-canon 三套件）。
- 0.1.0「JCS（RFC 8785）规范化 JSON」宣称失实，本版兑现（见上）。

### 测试与质量

- 八面套件 **1438 条**（plain 1437 + deferred 1，`suite-review.txt` 单一来源）
  不变；总测试 **535** 全绿 + deny-warn。
- 覆盖率棘轮 ≤ **235** 只降不升（役C5 换带，`coverage-baseline.txt`）。
- 性能役 P1 定稿：十场景回归门 + scoped_heavy COW 回归门
  （`perf-baseline.txt`，开局 17.9s → 全场景 ≤190ms）。

## 0.1.0（首发，2026-10-06）

JSON-LD 1.1 通用库首个发布版：expand / compact / flatten / frame / toRDF /
fromRDF 六算法全链 + RDFC-1.0 数据集规范化 + JCS（RFC 8785）规范化 JSON +
HTML `application/ld+json` 脚本抽取 + 命令行薄壳（`cmd/main`，八命令）。

### 新增 API

- **六算法入口**：`expand_document` / `compact_document` / `flatten_document`
  （上下文可选参）/ `frame_document` / `to_rdf_document`（→ `JsonLdQuad`，
  N-Quads 形术语）/ `from_rdf_document`（N-Quads 文本输入）。
- **`JsonLdOptions` 全量选项面**：`processing_mode`（1.0 / 1.1）、`base`、
  `load_context`（远程上下文同步注入回调——库内不做网络 I/O）、`rdf_direction`、
  `produce_generalized_rdf`、`compact_arrays`、`compact_to_relative`、
  `frame_expansion`、`omit_graph`、`use_native_types`、`use_rdf_type`。
- **规范化面**：`rdfc10_canonicalize_with_hash`（RDFC-1.0，Sha256 / Sha384
  双档，规范化形 + 空白节点哈希表）；`json_canonical`（JCS，RFC 8785）+
  `render_json`（带转义门的序列化出口）。
- **自带 JSON 解析**：`parse_json` / `JsonValue` AST（产品面仅依赖 MoonBit
  标准库）。
- **HTML 集成**：`html_script_source`（`<script type="application/ld+json">`
  抽取）。
- **强类型错误面**：`JsonLdError` 九变体（`derive(Eq + Debug)`，可 match 分型）。
- **套件辅助与自省**：`canonical_for_suite` / `isomorphic_for_suite`（官方比对
  语义：数组默认无序、唯一例外 `@list` 保序）；`jsonld_iri_routes` /
  `jsonld_keyword_routes`（词表路由自省）。
- **命令行薄壳**：`cmd/main` 可执行包（`moon run cmd/main -- <command> …`）——
  八命令 expand / compact / flatten / frame / to-rdf / from-rdf / canonicalize /
  json-canonical，选项 `--base` / `--mode` / `--hash`；错误文案走 stderr，不接
  网络（上下文一律本地文件）。库 pub 面零变化。

### 语义要点

- 词表路由 / IRI 展开由**表数据驱动**（生成器面在主仓 `fsm/jsonld_gen`，
  本仓只留产物 `gen.mbt` + 手写库面）；展开/压缩语义对齐 JSON-LD 1.1 API
  （含 `@import` / `@propagate` / `@protected` / scoped context / base direction）。
- `@context` 溢出防护：上下文链深度限 32（REC 4.1.2），超限报
  `ContextOverflow`。

### 测试与质量

- W3C json-ld-api / json-ld-framing / rdf-canon 三套件八面 **1438 条**
  （plain 1437 + deferred 1；唯一留册 `compact #t0038` = 版次越界排除[设计]，
  见 `review.md` §1.2）；语料 `SHA256SUMS` 锁版（2626 件）。
- 覆盖率棘轮：未覆盖行数 ≤ 608 只降不升（2026-10-06 复测 606）。

### 设计边界（圈外 = 设计裁定，非缺口）

- 远程文档抓取（remote-doc）不做内置网络 I/O（`load_context` 注入）。
  定位裁定全证据链见 `spec.md` §9。

### 工程

- 本版以独立模块 `thy1016/jsonld` 首发（生成器面归主仓，见 `moon.mod` 头注）。
- **可运行示例**：`examples/quickstart`（六算法 + JCS 全链走览；依
  `moonttl/src/examples` 制——main 只留进程入口，本体进测试宿主冒烟）。
