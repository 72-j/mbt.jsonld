# mbt.jsonld

`thy1016/jsonld` 是一个用 MoonBit 编写的 **JSON-LD 1.1 通用库**：
expand / compact / flatten / frame / toRDF / fromRDF 六算法全链，
外加 **RDFC-1.0** 数据集规范化、**JCS（RFC 8785）** 规范化 JSON，
以及 HTML `application/ld+json` 脚本抽取。

## 特性

  - **JSON-LD 1.1 六算法全链**：`processing_mode` 支持 1.0 / 1.1 双档；
    flatten 的上下文为可选参数（展平 + 压缩一步到位）。
  - **RDFC-1.0 规范化**：W3C RDF Dataset Canonicalization，SHA-256 / SHA-384
    双哈希档，规范化形与空白节点哈希表一并返回。
  - **JCS（RFC 8785）**：`json_canonical` 树规范化（键序 + 数词形）+
    `render_json` 序列化出口（带转义门）。
  - **自带 JSON 解析器**：`parse_json` / `JsonValue` AST；产品面仅依赖
    MoonBit 标准库（core）。
  - **强类型错误面**：`JsonLdError` 九变体，`derive(Eq + Debug)`，可 match 分型。
  - **测试底座**：W3C json-ld-api / json-ld-framing / rdf-canon 三套件
    1438 例（`SHA256SUMS` 锁版）。

## 安装

确保环境中已安装 MoonBit 工具链，然后在模块根目录：

```bash
moon add thy1016/jsonld
```

再在用到它的包的 `moon.pkg` `import` 块中添加 `"thy1016/jsonld"`，
代码内以 `@jsonld` 前缀使用。

## 快速上手

`JsonLdOptions` 为全字段显式构造（MoonBit 跨包构造规则）：

```moonbit
let opts = @jsonld.JsonLdOptions::{
  base: None,
  expand_context: None,
  processing_mode: @jsonld.ProcessingMode::JsonLd11,
  load_context: None,
  rdf_direction: None,
  produce_generalized_rdf: false,
  compact_arrays: true,
  compact_to_relative: true,
  frame_expansion: false,
  omit_graph: false,
  use_native_types: false,
  use_rdf_type: false,
}
```

### 展开（expand）

```moonbit
let doc = "{\"@context\": {\"name\": \"http://schema.org/name\"}, \"name\": \"Ada\"}"
match @jsonld.expand_document(doc, opts) {
  Ok(expanded) => println(@jsonld.render_json(expanded))
  Err(err) => println("expand failed: \{err}")
}
```

### 压缩（compact）

```moonbit
let context = "{\"name\": \"http://schema.org/name\"}"
match @jsonld.compact_document(doc, context, opts) {
  Ok(compacted) => println(@jsonld.render_json(compacted))
  Err(err) => println("compact failed: \{err}")
}
```

### toRDF / fromRDF

`to_rdf_document` 产出 `JsonLdQuad` 数组（术语为 N-Quads 形字符串）；
`from_rdf_document` 的输入为 N-Quads 文本。

```moonbit
match @jsonld.to_rdf_document(doc, opts) {
  Ok(quads) => println("quads: \{quads.length()}")
  Err(err) => println("toRDF failed: \{err}")
}

let nq = "<http://example.org/s> <http://example.org/p> \"v\" .\n"
match @jsonld.from_rdf_document(nq, opts) {
  Ok(node_object) => println(@jsonld.render_json(node_object))
  Err(err) => println("fromRDF failed: \{err}")
}
```

### RDFC-1.0 规范化

```moonbit
match @jsonld.rdfc10_canonicalize_with_hash(nq, @jsonld.C14nHashAlgorithm::Sha384) {
  Ok((canonical, hashes)) => {
    for id, hash in hashes {
      println("\{id} => \{hash}")
    }
  }
  Err(err) => println("canonicalize failed: \{err}")
}
```

### JCS 规范化 JSON

```moonbit
match @jsonld.parse_json("{\"b\": 1.0, \"a\": 2}") {
  Ok(parsed) => println(@jsonld.render_json(@jsonld.json_canonical(parsed)))
  Err(err) => println("parse failed: \{err}")
}
```

### 远程上下文注入

库内**不做网络 I/O**；远程上下文经 `load_context` 回调由调用方注入：

```moonbit
// ((String) -> Result[String, String])?
let loader = url => fetch_document(url)
// 构造 options 时：load_context: Some(loader)
```

## API 总览

| 入口 | 作用 |
|---|---|
| `parse_json` | 自带 JSON 解析（`JsonValue` AST） |
| `expand_document` | 展开：IRI 全解析 + 词表归一 |
| `compact_document` | 压缩（文档 + 上下文 + 选项） |
| `flatten_document` | 展平（上下文可选参） |
| `frame_document` | 帧（frame） |
| `to_rdf_document` | JSON-LD → RDF 四元组（`JsonLdQuad`） |
| `from_rdf_document` | N-Quads 文本 → JSON-LD 节点对象 |
| `html_script_source` | HTML `<script type="application/ld+json">` 抽取 |
| `rdfc10_canonicalize_with_hash` | RDFC-1.0 规范化（Sha256 / Sha384） |
| `json_canonical` / `render_json` | JCS 规范化 / JSON 序列化 |
| `canonical_for_suite` / `isomorphic_for_suite` | 套件比对辅助（规范化形 / 数据集同构） |
| `jsonld_iri_routes` / `jsonld_keyword_routes` | IRI / 关键字词表路由自省 |

## 错误面

`JsonLdError` 九变体：`Syntax` / `InvalidContext` / `InvalidIri` /
`InvalidValue` / `InvalidList` / `Unsupported` / `ContextOverflow` /
`LoadingDocumentFailed` / `InvalidScriptElement`。

## 设计边界（圈外 = 设计裁定，非缺口）

  - **远程文档抓取（remote-doc）**：不做内置网络 I/O，`load_context` 注入；
    W3C remote-doc 套件例按设计排除。
  - **命令行工具**：不做（库定位）。

定位裁定与全证据链见仓内 `spec.md` §9。

## 测试与验证

```bash
moon test
```

输出八面自报行 `[<面>] entries=N plain=N deferred=N`（下数计于 2026-10-06）：

| 面 | entries | plain | deferred |
|---|---|---|---|
| expand | 385 | 385 | 0 |
| toRdf | 467 | 467 | 0 |
| compact | 246 | 245 | 1（#t0038 版次越界，[设计]） |
| frame | 92 | 92 | 0 |
| canon（RDFC-1.0） | 86 | 86 | 0 |
| flatten | 58 | 58 | 0 |
| fromRdf | 54 | 54 | 0 |
| html | 50 | 50 | 0 |
| **合计** | **1438** | **1437** | 1 |

语料 = W3C json-ld-api / json-ld-framing / rdf-canon（`.rdf-tests/`，
`SHA256SUMS` 完整性锁版）。

## 许可证声明（W3C 语料）

  - 本仓代码采用 **Apache-2.0**（见 `LICENSE`）。
  - W3C 测试文件按 W3C 双许可分发（W3C 3-clause BSD License 与 W3C Test Suite
    License，被许可方二选一）。语料位于 `.rdf-tests/`（顶层点目录 ⇒ 留在仓库、
    **不进发布包**），原始文件逐字节未修改，`SHA256SUMS` 锁版。
  - **无背书声明**：上文套件通过计数是本项目自测结果，只表示本方实现能通过
    相应用例，不代表 W3C 认证、合规认定或任何形式的背书。

## 许可证

Apache License, Version 2.0（`LICENSE`）。
