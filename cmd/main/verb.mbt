// ===== jsonld 命令行薄壳（八命令执行体）=====

///|
async fn run_expand(invocation : CliInvocation) -> Unit {
  let document = match first_positional(invocation, "doc") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  print_json("expand", @jsonld.expand_document(document, options))
}

///|
async fn run_compact(invocation : CliInvocation) -> Unit {
  let document = match first_positional(invocation, "doc") {
    Some(text) => text
    None => return
  }
  let context = match load_positional(invocation, 1, "context") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  print_json("compact", @jsonld.compact_document(document, context, options))
}

///|
/// flatten 的 context 可选：有则压缩包装（@context + @graph），无则裸节点表。
async fn run_flatten(invocation : CliInvocation) -> Unit {
  let document = match first_positional(invocation, "doc") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  if invocation.positionals.length() > 1 {
    let context = match load_positional(invocation, 1, "context") {
      Some(text) => text
      None => return
    }
    print_json("flatten", @jsonld.flatten_document(document, context~, options))
  } else {
    print_json("flatten", @jsonld.flatten_document(document, options))
  }
}

///|
async fn run_frame(invocation : CliInvocation) -> Unit {
  let document = match first_positional(invocation, "doc") {
    Some(text) => text
    None => return
  }
  let frame = match load_positional(invocation, 1, "frame") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  print_json("frame", @jsonld.frame_document(document, frame, options))
}

///|
fn quad_line(quad : @jsonld.JsonLdQuad) -> String {
  let head = "\{quad.subject} \{quad.predicate} \{quad.object}"
  match quad.graph {
    Some(graph) => "\{head} \{graph} ."
    None => "\{head} ."
  }
}

///|
async fn run_to_rdf(invocation : CliInvocation) -> Unit {
  let document = match first_positional(invocation, "doc") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  match @jsonld.to_rdf_document(document, options) {
    Ok(quads) =>
      for quad in quads {
        println(quad_line(quad))
      }
    Err(error) => eprintln("jsonld to-rdf 失败：\{error_text(error)}")
  }
}

///|
async fn run_from_rdf(invocation : CliInvocation) -> Unit {
  let dataset = match first_positional(invocation, "nq") {
    Some(text) => text
    None => return
  }
  let options = make_options(invocation.base, invocation.mode_1_0)
  print_json("from-rdf", @jsonld.from_rdf_document(dataset, options))
}

///|
async fn run_canonicalize(invocation : CliInvocation) -> Unit {
  let dataset = match first_positional(invocation, "nq") {
    Some(text) => text
    None => return
  }
  let algorithm = if invocation.hash_sha384 {
    @jsonld.C14nHashAlgorithm::Sha384
  } else {
    @jsonld.C14nHashAlgorithm::Sha256
  }
  match @jsonld.rdfc10_canonicalize_with_hash(dataset, algorithm) {
    Ok((canonical, _hashes)) => println(canonical.trim_end())
    Err(error) => eprintln("jsonld canonicalize 失败：\{error_text(error)}")
  }
}

///|
async fn run_json_canonical(invocation : CliInvocation) -> Unit {
  let text = match first_positional(invocation, "json") {
    Some(text) => text
    None => return
  }
  match @jsonld.parse_json(text) {
    // JCS（RFC 8785）直出——评审役 R-1 处置（2026-10-09）：原经
    // json_canonical（对拍归一器，长度序）误称 JCS，改接 jcs_serialize 真品
    Ok(value) => println(@jsonld.jcs_serialize(value))
    Err(error) =>
      eprintln("jsonld json-canonical 失败：\{error_text(error)}")
  }
}
