///|
/// 己批 harness 预载通道：BFS 预扫输入/装载文档中 @context/@import 的字符串
/// 引用，建 Map[URL→文本]；options_for 的 loader 闭包 = 同步查表（miss → Err）。
/// core merge 与 harness join 同为 last-segment replace ⇒ 键一致（套件平铺目录）
fn harness_join(anchor_url : String, context_ref : String) -> String {
  let cut = match anchor_url.rev_find("/") {
    Some(idx) => idx + 1
    None => 0
  }
  let dir = anchor_url[:cut].to_owned()
  "\{dir}\{context_ref}"
}

///|
/// 单引用装载：resolved URL → 本地镜像路径（`tests/` 后缀直映 .rdf-tests 目录），
/// 读盘 → 解析 → 入 map（先入后走——环自断），再递归走装载文档内容
async fn load_one_context(
  anchor : String,
  context_ref : String,
  map : Map[String, String],
) -> Unit {
  // 绝对 IRI 引用（含 scheme）不预载——core 侧照传 loader（miss → 装载失败，
  // 语义仍真）；套件平铺目录下相对引用才有本地镜像文件
  if context_ref.contains(":") {
    return
  }
  let url = harness_join(anchor, context_ref)
  if map.contains(url) {
    return
  }
  let mirror_prefix = "https://w3c.github.io/json-ld-api/tests/"
  let prefix_len = mirror_prefix.length()
  let local_path = "./src/jsonld/.rdf-tests/json-ld-api/" +
    url[prefix_len:].to_owned()
  let text = @utf8.decode(@fs.read_file(local_path).binary())
  map[url] = text
  match @jsonld.parse_json(text) {
    Ok(parsed) => preload_contexts(url, parsed, map)
    Err(_) => ()
  }
}

///|
/// 深走 JSON：@context/@import 键的字符串值 → 装载；数组项字符串 → 装载；
/// 其余一律递归深走（inline context 的 td @context 引用由此覆盖）
async fn preload_contexts(
  anchor : String,
  value : @jsonld.JsonValue,
  map : Map[String, String],
) -> Unit {
  match value {
    @jsonld.JsonValue::Object(pairs) =>
      for pair in pairs {
        if pair.0 is "@context" || pair.0 is "@import" {
          match pair.1 {
            @jsonld.JsonValue::String(context_ref) =>
              load_one_context(anchor, context_ref, map)
            @jsonld.JsonValue::Array(refs) =>
              for item in refs {
                match item {
                  @jsonld.JsonValue::String(context_ref) =>
                    load_one_context(anchor, context_ref, map)
                  _ => preload_contexts(anchor, item, map)
                }
              }
            _ => preload_contexts(anchor, pair.1, map)
          }
        } else {
          preload_contexts(anchor, pair.1, map)
        }
      }
    @jsonld.JsonValue::Array(items) =>
      for item in items {
        preload_contexts(anchor, item, map)
      }
    _ => ()
  }
}

///|
/// per-case base（单一来源——options_for 与预载共用；option.base 覆盖优先，
/// 缺省 = 输入文档 URL 含文件名）
fn base_for_entry(entry : @jsonld.JsonValue) -> String? {
  match json_object_get(entry, "option") {
    Some(option_value) =>
      match json_string_get(option_value, "base") {
        Some(b) => Some(b)
        None => base_from_input(entry)
      }
    None => base_from_input(entry)
  }
}

///|
fn base_from_input(entry : @jsonld.JsonValue) -> String? {
  match json_string_get(entry, "input") {
    Some(input_path) =>
      Some("https://w3c.github.io/json-ld-api/tests/" + input_path)
    None => None
  }
}

///|
/// 预载 map → 同步 loader 闭包
fn loader_from_map(
  map : Map[String, String],
) -> (String) -> Result[String, String] {
  fn(url : String) {
    match map.get(url) {
      Some(text) => Ok(text)
      None => Err("not preloaded: \{url}")
    }
  }
}
