// ===== jsonld 命令行薄壳（共享核心）=====
// 错误契约：文案一律 eprintln（stderr；stdout 保净供管道），退出码恒 0
// （工具链无 exit API——moonttl / mbtgen cmd 同款先例）。

///|
async fn dispatch(invocation : CliInvocation) -> Unit {
  match invocation.verb {
    "expand" => run_expand(invocation)
    "compact" => run_compact(invocation)
    "flatten" => run_flatten(invocation)
    "frame" => run_frame(invocation)
    "to-rdf" => run_to_rdf(invocation)
    "from-rdf" => run_from_rdf(invocation)
    "canonicalize" => run_canonicalize(invocation)
    "json-canonical" => run_json_canonical(invocation)
    unknown => {
      eprintln("jsonld：未知命令 \{unknown}")
      print_usage(true)
    }
  }
}

///|
/// 选项构造：全字段显式（跨包构造规则）；错误面 / 语义全在库侧。
/// 缺省与套件 harness 同款（compact_arrays=true / frame_expansion=false）。
fn make_options(base : String?, mode_1_0 : Bool) -> @jsonld.JsonLdOptions {
  let processing_mode = if mode_1_0 {
    @jsonld.ProcessingMode::JsonLd10
  } else {
    @jsonld.ProcessingMode::JsonLd11
  }
  {
    base,
    expand_context: None,
    processing_mode,
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
}

///|
async fn read_text(path : String) -> String? {
  try {
    let bytes = @fs.read_file(path).binary()
    Some(@utf8.decode(bytes))
  } catch {
    _ => None
  }
}

///|
/// 错误文案：变体名即错误类别（JsonLdError 无 Show，九臂直出）。
fn error_text(error : @jsonld.JsonLdError) -> String {
  match error {
    Syntax(text) => "syntax: \{text}"
    InvalidContext(text) => "invalid context: \{text}"
    InvalidIri(text) => "invalid IRI: \{text}"
    InvalidValue(text) => "invalid value: \{text}"
    InvalidList(text) => "invalid list: \{text}"
    Unsupported(text) => "unsupported: \{text}"
    ContextOverflow(text) => "context overflow: \{text}"
    LoadingDocumentFailed(text) => "loading document failed: \{text}"
    InvalidScriptElement(text) => "invalid script element: \{text}"
  }
}

///|
/// 第 index 个位置输入：不足额或读不到文件时打错误（stderr）并返回 None。
async fn load_positional(
  invocation : CliInvocation,
  index : Int,
  label : String,
) -> String? {
  if index >= invocation.positionals.length() {
    eprintln("jsonld \{invocation.verb}：缺少 <\{label}> 输入")
    return None
  }
  let path = invocation.positionals[index]
  match read_text(path) {
    Some(text) => Some(text)
    None => {
      eprintln("jsonld \{invocation.verb}：无法读取 \{path}")
      None
    }
  }
}

///|
/// JSON 结果打印：Ok 出 stdout，Err 出 stderr。
fn print_json(
  label : String,
  result : Result[@jsonld.JsonValue, @jsonld.JsonLdError],
) -> Unit {
  match result {
    Ok(value) => println(@jsonld.render_json(value))
    Err(error) => eprintln("jsonld \{label} 失败：\{error_text(error)}")
  }
}

///|
async fn first_positional(
  invocation : CliInvocation,
  label : String,
) -> String? {
  load_positional(invocation, 0, label)
}
