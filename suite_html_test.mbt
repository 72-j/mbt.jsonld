///|
/// HTML 套件 harness（J9——REC 9.5）：manifest 驱动 50 例两桶
/// （35 正 + 15 负），四通道复用既有引擎与判定器：
/// ExpandTest → expand_document / CompactTest → compact_document（context
/// 文件）/ FlattenTest → flatten_document_with_context / ToRDFTest →
/// to_rdf_document → parse_nquads → datasets_isomorphic。
/// 提取通道 = html_script_source（REC 9.5.1：输入 URL #fragment 按 script
/// id 选择；extractAllScripts=true 合并数组；无 script + false → 负例）。
async test "HTML suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/html-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  let deferred : Array[String] = []
  let plain : Array[String] = []
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    let input_url = match json_string_get(entry, "input") {
      Some(path) => path
      None => fail("\{id}: input missing")
    }
    // 输入 URL 剥 fragment（'#' 后段 = script id 选择器，REC 9.5.1）
    let mut cut = input_url.length()
    for i in 0..<input_url.length() {
      if input_url[i].to_int() == 35 {
        cut = i
        break
      } else {
        ()
      }
    }
    let path = input_url[:cut].to_owned()
    let fragment : String? = if cut < input_url.length() {
      Some(input_url[cut + 1:].to_owned())
    } else {
      None
    }
    let mut is_neg = false
    let mut kind = ""
    match json_object_get(entry, "@type") {
      Some(@jsonld.JsonValue::Array(items)) =>
        for item in items {
          match item {
            @jsonld.JsonValue::String(t) =>
              if t == "jld:NegativeEvaluationTest" {
                is_neg = true
              } else if t == "jld:ExpandTest" {
                kind = "expand"
              } else if t == "jld:CompactTest" {
                kind = "compact"
              } else if t == "jld:FlattenTest" {
                kind = "flatten"
              } else if t == "jld:ToRDFTest" {
                kind = "toRdf"
              } else {
                ()
              }
            _ => ()
          }
        }
      _ => fail("\{id}: @type missing")
    }
    // extractAllScripts 选项（REC 9.5.1 无 fragment 支）
    let mut extract_all = false
    match json_object_get(entry, "option") {
      Some(option_value) =>
        match json_object_get(option_value, "extractAllScripts") {
          Some(@jsonld.JsonValue::Bool(flag)) => extract_all = flag
          _ => ()
        }
      None => ()
    }
    // 检索 URL（REC url 参数）= option.base ?? 文档位置（剥 fragment）
    let mut document_url = "https://w3c.github.io/json-ld-api/tests/" + path
    match json_object_get(entry, "option") {
      Some(option_value) =>
        match json_string_get(option_value, "base") {
          Some(base_value) => document_url = base_value
          None => ()
        }
      None => ()
    }
    let html_text = @utf8.decode(
      @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + path).binary(),
    )
    match
      @jsonld.html_script_source(
        html_text,
        Some(document_url),
        fragment,
        extract_all,
      ) {
      Err(_) =>
        if !is_neg {
          fail("\{id}: 正例 HTML 提取报错")
        } else {
          plain.push(id)
        }
      Ok(result) =>
        if result.no_scripts && kind != "toRdf" {
          // 无 script 臂·通道分叉（同形异判，2026-10-03 勘定）：expand/compact/
          // flatten 面 ⇒ loading document failed（#te006 负例 oracle）；
          // 仅 ToRDFTest 面视作空输入（#tr006 正例 ⇒ 空数据集）
          if is_neg {
            plain.push(id)
          } else {
            fail(
              "\{id}: 正例无 script（该通道应报 loading document failed）",
            )
          }
        } else if is_neg {
          fail("\{id}: 负例意外提取成功")
        } else {
          // base 优先序（te019/20/21 oracle）：HTML <base href>（已对检索
          // URL 解析）> option.base > 文档位置（剥 fragment）
          let mut effective = document_url
          match json_object_get(entry, "option") {
            Some(option_value) =>
              match json_string_get(option_value, "base") {
                Some(base_value) => effective = base_value
                None => ()
              }
            None => ()
          }
          match result.document_base {
            Some(base_value) => effective = base_value
            None => ()
          }
          let mut options = options_for(entry, Map([]))
          options = { ..options, base: Some(effective), }
          html_run_channel(id, kind, result.source, entry, options, plain)
        }
    }
  }
  assert_eq(plain.length() + deferred.length(), sequence.length())
  assert_eq(deferred.length(), 0)
  assert_eq(plain.length(), 50)
  // 复核面自报行（J4；suite-review.txt 抽取源——勿改格式）
  println(
    "[html] entries=\{sequence.length()} plain=\{plain.length()} deferred=\{deferred.length()}",
  )
}

///|
/// 四通道分派判定（正例）：JSON 面 canonical_for_suite 直比 + bnode 双射
/// 兜底；toRdf 面 parse_nquads 归一 + datasets_isomorphic。
async fn html_run_channel(
  id : String,
  kind : String,
  source : String,
  entry : @jsonld.JsonValue,
  options : @jsonld.JsonLdOptions,
  plain : Array[String],
) -> Unit {
  match kind {
    "expand" =>
      match @jsonld.expand_document(source, options) {
        Err(m) => fail("\{id}: expand 报错 \{html_error_text(m)}")
        Ok(compacted) => html_expect_json(id, entry, compacted, plain)
      }
    "compact" => {
      let context_text = html_context_text(id, entry)
      match @jsonld.compact_document(source, context_text, options) {
        Err(m) => fail("\{id}: compact 报错 \{html_error_text(m)}")
        Ok(compacted) => html_expect_json(id, entry, compacted, plain)
      }
    }
    "flatten" => {
      let context_text = html_context_text(id, entry)
      match @jsonld.flatten_document(source, context=context_text, options) {
        Err(m) => fail("\{id}: flatten 报错 \{html_error_text(m)}")
        Ok(compacted) => html_expect_json(id, entry, compacted, plain)
      }
    }
    "toRdf" =>
      match @jsonld.to_rdf_document(source, options) {
        Err(m) => fail("\{id}: toRdf 报错 \{html_error_text(m)}")
        Ok(quads) => {
          let expect_path = match json_string_get(entry, "expect") {
            Some(ep) => ep
            None => fail("\{id}: 正例无 expect")
          }
          let expect_text = @utf8.decode(
            @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + expect_path).binary(),
          )
          let expected = match parse_nquads(expect_text) {
            Ok(quads_out) => quads_out
            Err(m) => fail("\{id}: expected 解析失败 \{m}")
          }
          let ours = match parse_nquads(render_nq(quads)) {
            Ok(quads_out) => quads_out
            Err(m) => fail("\{id}: ours 渲染解析失败 \{m}")
          }
          if datasets_isomorphic(ours, expected) {
            plain.push(id)
          } else {
            fail("\{id}: 数据集不同构")
          }
        }
      }
    _ => fail("\{id}: 未知通道 \{kind}")
  }
}

///|
/// JSON 面期望对拍（expand/compact/flatten 共用）
async fn html_expect_json(
  id : String,
  entry : @jsonld.JsonValue,
  ours_value : @jsonld.JsonValue,
  plain : Array[String],
) -> Unit {
  let expect_path = match json_string_get(entry, "expect") {
    Some(ep) => ep
    None => fail("\{id}: 正例无 expect")
  }
  let expect_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + expect_path).binary(),
  )
  let expected_value = match @jsonld.parse_json(expect_text) {
    Ok(v) => v
    Err(_) => fail("\{id}: expected 解析失败")
  }
  let ours = diag_json_str(@jsonld.canonical_for_suite(ours_value))
  let expected = diag_json_str(@jsonld.canonical_for_suite(expected_value))
  if ours != expected {
    if !@jsonld.isomorphic_for_suite(ours_value, expected_value) {
      fail("\{id}: 对拍不一致\n  ours=\{ours}\n  expect=\{expected}")
    }
  }
  plain.push(id)
}

///|
/// context 文件原文（compact/flatten 通道；无 context 条目 = 空对象文）
async fn html_context_text(id : String, entry : @jsonld.JsonValue) -> String {
  match json_string_get(entry, "context") {
    Some(context_ref) =>
      @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + context_ref).binary(),
      )
    None => {
      let _ = id
      "{}"
    }
  }
}

///|
/// 错误消息面（harness 失败诊断用；对拍判据不依赖错误文案）
fn html_error_text(e : @jsonld.JsonLdError) -> String {
  match e {
    @jsonld.JsonLdError::Syntax(m) => "syntax: " + m
    @jsonld.JsonLdError::InvalidContext(m) => "invalid context: " + m
    @jsonld.JsonLdError::InvalidIri(m) => "invalid iri: " + m
    @jsonld.JsonLdError::InvalidValue(m) => "invalid value: " + m
    @jsonld.JsonLdError::InvalidList(m) => "invalid list: " + m
    @jsonld.JsonLdError::Unsupported(m) => "unsupported: " + m
    @jsonld.JsonLdError::ContextOverflow(m) => "context overflow: " + m
    @jsonld.JsonLdError::LoadingDocumentFailed(m) =>
      "loading document failed: " + m
    @jsonld.JsonLdError::InvalidScriptElement(m) =>
      "invalid script element: " + m
  }
}
