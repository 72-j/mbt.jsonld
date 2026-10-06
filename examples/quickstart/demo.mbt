// ===== 六算法走览本体 =====
// 纯同步库调用；Err 臂 = 九变体 match 分型提示（例不入 Err）。

///|
/// 六算法全链报告：Alice knows Bob（Bob 无 @id ⇒ 空白节点）。
/// main 打印 / wbtest 断言同源。
fn six_algorithm_report() -> String {
  let document =
    #|{
    #|  "@context": {
    #|    "name": "http://schema.org/name",
    #|    "knows": "http://schema.org/knows",
    #|    "Person": "http://schema.org/Person"
    #|  },
    #|  "@id": "https://example.org/alice",
    #|  "@type": "Person",
    #|  "name": "Alice",
    #|  "knows": { "name": "Bob" }
    #|}
  let context =
    #|{
    #|  "@context": {
    #|    "who": "http://schema.org/name",
    #|    "kw": "http://schema.org/knows"
    #|  }
    #|}
  let frame =
    #|{
    #|  "context": "unused"
    #|}
  let options : @jsonld.JsonLdOptions = {
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
  // ① expand：IRI 全解析 + 词表归一
  let expanded = match @jsonld.expand_document(document, options) {
    Ok(value) => @jsonld.render_json(value)
    Err(_) => "（JsonLdError——九变体 match 分型）"
  }
  // ② compact：以 context 压缩
  let compacted = match @jsonld.compact_document(document, context, options) {
    Ok(value) => @jsonld.render_json(value)
    Err(_) => "（JsonLdError——九变体 match 分型）"
  }
  // ③ flatten：节点表展平
  let flattened = match @jsonld.flatten_document(document, options) {
    Ok(value) => @jsonld.render_json(value)
    Err(_) => "（JsonLdError——九变体 match 分型）"
  }
  // ④ frame：Person 帧匹配
  let framed = match @jsonld.frame_document(document, frame, options) {
    Ok(value) => @jsonld.render_json(value)
    Err(_) => "（JsonLdError——九变体 match 分型）"
  }
  // ⑤ toRDF：文档 → 四元组 → N-Quads 文本（quad 三元位直插值）
  let dataset = match @jsonld.to_rdf_document(document, options) {
    Ok(quads) => {
      let mut text = ""
      for quad in quads {
        let head = "\{quad.subject} \{quad.predicate} \{quad.object}"
        text = match quad.graph {
          Some(graph) => text + "\{head} \{graph} .\n"
          None => text + "\{head} .\n"
        }
      }
      text
    }
    Err(_) => ""
  }
  // ⑥ RDFC-1.0：Bob 空白节点 ⇒ _:c14n0 签发换名
  let canonical = match
    @jsonld.rdfc10_canonicalize_with_hash(
      dataset,
      @jsonld.C14nHashAlgorithm::Sha256,
    ) {
    Ok((canonical, _hashes)) => canonical
    Err(_) => ""
  }
  // ⑦ JCS：context 原文规范化（键序）
  let jcs = match @jsonld.parse_json(context) {
    Ok(value) => @jsonld.render_json(@jsonld.json_canonical(value))
    Err(_) => ""
  }
  let mut report = ""
  report = report + section("1 expand 展开", expanded)
  report = report + section("2 compact 压缩", compacted)
  report = report + section("3 flatten 展平", flattened)
  report = report + section("4 frame 帧", framed)
  report = report + section("5 toRDF → N-Quads", dataset)
  report = report + section("6 RDFC-1.0 规范化", canonical)
  report = report + section("7 JCS 规范化 JSON", jcs)
  report
}
