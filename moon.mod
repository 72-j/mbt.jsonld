// MoonBit module manifest — mbt.jsonld
// 定位：JSON-LD 1.1 通用库（expand / compact / flatten / frame / toRDF / fromRDF）
//       + RDFC-1.0 canonicalization。生成器（jsonld_gen.toml / skelgen）由主仓管理；
//       本仓只留产物 gen.mbt + 手写库面（见 AGENTS.md）。

name = "thy1016/jsonld"

version = "0.1.2"

repository = "https://www.gitlink.org.cn/thy7/mbt.jsonld"

license = "Apache-2.0"

keywords = [ "jsonld", "json-ld", "rdf", "linked-data", "canonicalization" ]

description = "JSON-LD 1.1 (expand / compact / flatten / frame / toRDF / fromRDF) + RDFC-1.0 canonicalization for MoonBit."

readme = "README.md"

preferred_target = "native"

import {
  "moonbitlang/async@0.22.4",
  // quicktest 随机状态机脚手架（仅 jsonld/quicktest 测试面消费）
  "moonbit-community/quickcheck_statemachine@0.0.1",
  // quickcheck 统一最新（0.14.0 注册表 tarball 是旧格式 moon.mod.json，新工具链拒装）
  "moonbitlang/quickcheck@0.15.1",
}
