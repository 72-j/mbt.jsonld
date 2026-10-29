# MoonJSONLD

`thy1016/jsonld` 是一个用 MoonBit 编写的 JSON-LD 1.1 通用库：实现
expand / compact / flatten / frame / toRDF / fromRDF 六个算法，另含
RDFC-1.0 数据集规范化、JCS（RFC 8785）规范化 JSON 序列化，以及 HTML
`application/ld+json` 脚本抽取。

## 特性

- JSON-LD 1.1 六算法：`processing_mode` 支持 1.0 / 1.1 双档；flatten 的
  上下文为可选参数，展平后可直接压缩。
- RDFC-1.0 规范化：W3C RDF Dataset Canonicalization，SHA-256 / SHA-384
  双哈希档，返回规范化形与空白节点哈希表。
- JCS（RFC 8785）：`jcs_serialize` 按 JSON 键码点序、RFC 8785 §3.2.2.2
  转义规则与 ECMAScript 数值格式输出规范化 JSON。
- 自带 JSON 解析器：`parse_json` / `JsonValue` AST；库本身仅依赖 MoonBit
  标准库（`moonbitlang/async` 只用于测试与命令行工具）。
- 强类型错误面：`JsonLdError` 九变体，可按变体 match 处理。

## 安装

确保环境中已安装 MoonBit 工具链，然后在模块根目录：

```bash
moon add thy1016/jsonld
```

模块源码正式地址：gitlink <https://gitlink.org.cn/thy7/mbt.jsonld> 与
GitHub 镜像 <https://github.com/72-j/mbt.jsonld>；工作区多模块场景可
直接以本地树路径引用。

再在用到它的包的 `moon.pkg` `import` 块中添加 `"thy1016/jsonld"`，
代码内以 `@jsonld` 前缀使用。

## 快速上手

`JsonLdOptions` 需全字段显式构造：

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
  Ok(parsed) => println(@jsonld.jcs_serialize(parsed))
  Err(err) => println("parse failed: \{err}")
}
```

### 远程上下文注入

库内不做网络 I/O；远程上下文经 `load_context` 回调由调用方注入：

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
| `jcs_serialize` | JCS（RFC 8785）规范化序列化直出 |
| `json_canonical` / `render_json` | JSON 归一化（比对用途，非 JCS）/ JSON 序列化 |
| `canonical_for_suite` / `isomorphic_for_suite` | 套件比对辅助（规范化形 / 数据集同构） |
| `jsonld_iri_routes` / `jsonld_keyword_routes` | IRI / 关键字词表路由自省 |

## 错误面

`JsonLdError` 九变体：`Syntax` / `InvalidContext` / `InvalidIri` /
`InvalidValue` / `InvalidList` / `Unsupported` / `ContextOverflow` /
`LoadingDocumentFailed` / `InvalidScriptElement`。

## 设计边界

- 远程文档抓取：库内不做网络 I/O，远程上下文经 `load_context` 回调由调用方
  注入；W3C remote-doc 套件用例不纳入测试范围。

定位与边界的完整说明见 `spec.md` §9。

## 命令行工具

可运行示例：`examples/quickstart`（六个算法与 JCS 的完整走览），运行
`moon run examples/quickstart`。

库随附命令行工具（不做网络访问，输入与上下文均读本地文件）：

```bash
moon run cmd/main -- <command> [options] <inputs>
```

八个命令：`expand` / `compact` / `flatten` / `frame` / `to-rdf` / `from-rdf` /
`canonicalize` / `json-canonical`；选项 `--base <iri>`、`--mode <1.0|1.1>`、
`--hash <sha256|sha384>`。错误信息输出到 stderr，数据输出到 stdout。

```bash
# 例：展开并直出 N-Quads
moon run cmd/main -- to-rdf doc.jsonld
# 例：RDFC-1.0 规范化（sha384 档）
moon run cmd/main -- canonicalize --hash sha384 dataset.nq
```

## 测试与验证

```bash
moon test
```

运行时输出各测试面的计数行（下表实测于 2026-10-30）：

| 面 | entries | plain | deferred |
|---|---|---|---|
| expand | 385 | 385 | 0 |
| toRdf | 467 | 467 | 0 |
| compact | 246 | 245 | 1（#t0038 版次越界超面，有意保留） |
| frame | 92 | 92 | 0 |
| canon（RDFC-1.0） | 86 | 86 | 0 |
| flatten | 58 | 58 | 0 |
| fromRdf | 54 | 54 | 0 |
| html | 50 | 50 | 0 |
| **合计** | **1438** | **1437** | 1 |

测试语料为 W3C json-ld-api / json-ld-framing / rdf-canon 三套件，存于
`.rdf-tests/`，由 `SHA256SUMS` 锁定版本。

版本沿革见 `CHANGELOG.md`。

## 许可证

- 本项目代码采用 Apache License 2.0（见 `LICENSE`）。
- `.rdf-tests/` 内的 W3C 测试文件按 W3C 双许可（W3C 3-clause BSD License 与
  W3C Test Suite License，任选其一）分发，原始文件逐字节未修改；该目录随
  仓库保存，不进入发布包。
- 无背书声明：上文套件通过计数是本项目自测结果，只表示本实现能通过相应
  用例，不代表 W3C 认证、合规认定或任何形式的背书。
