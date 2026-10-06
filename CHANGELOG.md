# Changelog

本文件面向**使用者**，记录每版对外可见的变化（API / 语义 / 工程）。
内部战役账（役录、复核面、勘误沿革）见 `todo.md` / `review.md`，不在此重复。

数字单一来源纪律：套件通过计数一律引用 `suite-review.txt`（八面自报行），
覆盖率读数一律引用 `coverage-baseline.txt`，本文件只转述、不另立。

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

- 词表路由 / IRI 展开由**表数据驱动**（生成器面在主仓 `src/fsm/jsonld_gen`，
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
