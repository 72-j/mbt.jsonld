///|
/// 探针（throwaway）：t0015 现貌
async test "probe: r23 t0015" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/compact-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    if id != "#t0015" {
      continue
    }
    let input_text = @utf8.decode(
      @fs.read_file(
        "./src/jsonld/.rdf-tests/json-ld-api/" + json_string_get(entry, "input").unwrap(),
      ).binary(),
    )
    let context_text = @utf8.decode(
      @fs.read_file(
        "./src/jsonld/.rdf-tests/json-ld-api/" + json_string_get(entry, "context").unwrap(),
      ).binary(),
    )
    let context_map : Map[String, String] = Map([])
    match @jsonld.parse_json(input_text) {
      Ok(parsed_input) =>
        match base_for_entry(entry) {
          Some(anchor_url) => preload_contexts(anchor_url, parsed_input, context_map)
          None => ()
        }
      Err(_) => ()
    }
    let options = options_for(entry, context_map)
    match @jsonld.compact_document(input_text, context_text, options) {
      Err(_) => debug("ERR")
      Ok(compacted) => debug("OURS \{diag_json_str(@jsonld.canonical_for_suite(compacted))}")
    }
  }
}
