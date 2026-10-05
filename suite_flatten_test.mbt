///|
/// flatten 套件 harness（J5——spec §8.40）：manifest 驱动 58 例两桶
/// （57 正 + 1 负），判定 = canonical_for_suite 对拍（数组无序、@list 保序）
/// + bnode 双射兜底（isomorphic_for_suite——引用实现重标签语义）。
/// bnode 标签：引用实现 _:b0 顺序 vs 本实现遍历序——直比不过再补双射兜底。
async test "flatten suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./.rdf-tests/json-ld-api/flatten-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  // J5 flatten 收官（2026-09-29 役31：56/58 → 役56：58/58 全 plain——
  // deferred 清零。t0044/tin06 役56 收复（spec §8.128）：t0044 = flatten+
  // compaction 合成通道、tin06 = 同 id 全形再现成员值级并集。原勘注：
  // t0044 = compact 前置（compactArrays 触发 context 保留+压缩形，随
  // compaction 面解）、tin06 = @nest 深研（author 包装节点被 data 值吸收——
  // §8.39）。本批转正 4 例：t0038/t0045 = bnode 双射兜底件、t0046 = 相对
  // IRI 保形（flatten_term 有词面恒保留）、te001 = colliding indexes 检出
  // （F2 合并 @index 冲突 + free-floating @index 豁免）
  let migrated : Array[String] = [
    "#t0001", "#t0002", "#t0003", "#t0004", "#t0005", "#t0006", "#t0007", "#t0008",
    "#t0009", "#t0010", "#t0011", "#t0012", "#t0013", "#t0014", "#t0015", "#t0016",
    "#t0017", "#t0018", "#t0019", "#t0020", "#t0021", "#t0022", "#t0023", "#t0024",
    "#t0025", "#t0026", "#t0027", "#t0028", "#t0030", "#t0031", "#t0032", "#t0033",
    "#t0034", "#t0035", "#t0036", "#t0037", "#t0038", "#t0039", "#t0040", "#t0041",
    "#t0042", "#t0043", "#t0045", "#t0046", "#t0047", "#t0048", "#t0049", "#tin01",
    "#tin02", "#tin03", "#tin04", "#tin05", "#tli01", "#tli02", "#tli03", "#te001",
    // 役56 收官二连（spec §8.128）：tin06 = 同 id 全形再现成员值级并集
    // （visited 早退只应吞裸引用/环）；t0044 = flatten+compaction 合成
    // 通道（REC flatten(input, context)；compactArrays=false 数组保形）
     "#tin06", "#t0044",
  ]
  let deferred : Array[String] = []
  let plain : Array[String] = []
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    let is_neg = match json_object_get(entry, "@type") {
      Some(@jsonld.JsonValue::Array(kinds)) => {
        let mut neg = false
        for k in kinds {
          match k {
            @jsonld.JsonValue::String(kind) =>
              if kind == "jld:NegativeEvaluationTest" {
                neg = true
              }
            _ => ()
          }
        }
        neg
      }
      _ => false
    }
    if migrated.contains(id) {
      plain.push(id)
      let input_path = match json_string_get(entry, "input") {
        Some(p) => p
        None => fail("\{id}: migrated but no input")
      }
      let input_text = @utf8.decode(
        @fs.read_file("./.rdf-tests/json-ld-api/" + input_path).binary(),
      )
      let context_map : Map[String, String] = Map([])
      match @jsonld.parse_json(input_text) {
        Ok(parsed_input) =>
          match base_for_entry(entry) {
            Some(anchor_url) =>
              preload_contexts(anchor_url, parsed_input, context_map)
            None => ()
          }
        Err(_) => ()
      }
      let options = options_for(entry, context_map)
      // context 字段接线（役56 t0044——flatten(input, context) 合成面）：
      // 清单带 context 文件 ⇒ 走 flatten+compaction 合成入口
      let flatten_result = match json_string_get(entry, "context") {
        Some(context_path) => {
          let context_text = @utf8.decode(
            @fs.read_file("./.rdf-tests/json-ld-api/" + context_path).binary(),
          )
          @jsonld.flatten_document(input_text, context=context_text, options)
        }
        None => @jsonld.flatten_document(input_text, options)
      }
      match flatten_result {
        Err(_) => if !is_neg { fail("\{id}: 正例 flatten 报错") }
        Ok(flattened) =>
          if is_neg {
            fail("\{id}: 负例意外全绿")
          } else {
            let expect_path = match json_string_get(entry, "expect") {
              Some(ep) => ep
              None => fail("\{id}: 正例无 expect")
            }
            let expect_text = @utf8.decode(
              @fs.read_file("./.rdf-tests/json-ld-api/" + expect_path).binary(),
            )
            let expected_value = match @jsonld.parse_json(expect_text) {
              Ok(v) => v
              Err(_) => fail("\{id}: expected 解析失败")
            }
            let ours = diag_json_str(@jsonld.canonical_for_suite(flattened))
            let expected = diag_json_str(
              @jsonld.canonical_for_suite(expected_value),
            )
            if ours != expected {
              // bnode 双射兜底（引用实现重标签语义——词面位三钉：谓词键/
              // @id 值/@type 串值；@value 字面量不重标）
              if !@jsonld.isomorphic_for_suite(flattened, expected_value) {
                fail(
                  "\{id}: flatten 对拍不一致\n  ours=\{ours}\n  expect=\{expected}",
                )
              }
            }
          }
      }
    } else {
      deferred.push(id)
    }
  }
  assert_eq(deferred.length(), 0)
  assert_eq(plain.length(), 58)
  // 复核面自报行（J4；suite-review.txt 抽取源——勿改格式）
  println(
    "[flatten] entries=\{sequence.length()} plain=\{plain.length()} deferred=\{deferred.length()}",
  )
}

///|
/// 判定器自检（isomorphic_for_suite——bnode 双射兜底语义四钉）：
/// 标签对调同构 / @type 串值位与谓词键位同入双射 / 字面量 "_:x" 不重标 /
/// 结构异构否
test "flatten suite judge: bnode bijection semantics" {
  let obj = fn(
    pairs : Array[(String, @jsonld.JsonValue)],
  ) -> @jsonld.JsonValue {
    @jsonld.JsonValue::Object(pairs)
  }
  let arr = fn(items : Array[@jsonld.JsonValue]) -> @jsonld.JsonValue {
    @jsonld.JsonValue::Array(items)
  }
  let str = fn(s : String) -> @jsonld.JsonValue { @jsonld.JsonValue::String(s) }
  let ref_ = fn(id : String) -> @jsonld.JsonValue { obj([("@id", str(id))]) }
  // 钉一：标签对调同构（图同构、标签任意）
  let swap_left = arr([
    obj([("@id", str("_:a")), ("http://ex/p", arr([ref_("_:b")]))]),
  ])
  let swap_right = arr([
    obj([("@id", str("_:x")), ("http://ex/p", arr([ref_("_:y")]))]),
  ])
  assert_true(@jsonld.isomorphic_for_suite(swap_left, swap_right))
  // 钉二：@type 串值位与谓词键位同入双射（flatten 词面三钉之二）
  let typed_left = arr([
    obj([
      ("@id", str("_:a")),
      ("@type", arr([str("_:c")])),
      ("_:p", arr([str("v")])),
    ]),
  ])
  let typed_right = arr([
    obj([
      ("@id", str("_:x")),
      ("@type", arr([str("_:z")])),
      ("_:q", arr([str("v")])),
    ]),
  ])
  assert_true(@jsonld.isomorphic_for_suite(typed_left, typed_right))
  // 钉三：@value 字面量串不重标（"_:x" 字面非词面——异文即异构）
  let lit_left = arr([
    obj([
      ("@id", str("_:a")),
      ("http://ex/v", arr([obj([("@value", str("_:x"))])])),
    ]),
  ])
  let lit_right = arr([
    obj([
      ("@id", str("_:b")),
      ("http://ex/v", arr([obj([("@value", str("_:y"))])])),
    ]),
  ])
  assert_false(@jsonld.isomorphic_for_suite(lit_left, lit_right))
  // 钉四：结构异构否（词数等但入度不等——双射无解）
  let dense_left = arr([
    obj([("@id", str("_:a")), ("http://ex/p", arr([ref_("_:b"), ref_("_:b")]))]),
    obj([("@id", str("_:b"))]),
  ])
  let dense_right = arr([
    obj([("@id", str("_:x")), ("http://ex/p", arr([ref_("_:y"), ref_("_:z")]))]),
    obj([("@id", str("_:y"))]),
  ])
  assert_false(@jsonld.isomorphic_for_suite(dense_left, dense_right))
}
