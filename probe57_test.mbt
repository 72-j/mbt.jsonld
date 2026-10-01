///|
async test "probe t0057 frame_debug" {
  let input_text = "{\"@context\":{\"@version\":1.1,\"ex\":\"http://example.org/\"},\"@graph\":[{\"ex:list-v\":{\"@list\":[\"V\",{\"@value\":\"L\",\"@language\":\"l\"}]}},{\"ex:list-l\":{\"@list\":[{\"@value\":\"L\",\"@language\":\"l\"},{\"@value\":\"T\",\"@type\":\"ex:t\"}]}},{\"ex:list-t\":{\"@list\":[{\"@value\":\"T\",\"@type\":\"ex:t\"},{\"@id\":\"I\",\"@type\":\"ex:T\"}]}},{\"ex:list-i\":{\"@list\":[\"V\",{\"@id\":\"I\",\"@type\":\"ex:T\"}]}}]}"
  let frame_text = "{\"@context\":{\"@version\":1.1,\"ex\":\"http://example.org/\"},\"@requireAll\":false,\"ex:list-v\":{\"@list\":[\"V\"]},\"ex:list-l\":{\"@list\":[{\"@value\":\"L\",\"@language\":\"l\"}]},\"ex:list-t\":{\"@list\":[{\"@value\":\"T\",\"@type\":\"ex:t\"}]},\"ex:list-i\":{\"@list\":[{\"@id\":\"I\",\"@type\":\"ex:T\"}]}}"
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
  }
  let trace = @jsonld.frame_debug(input_text, frame_text, options)
  let _ = @fs.write_file("/tmp/t0057-trace.txt", trace)
  match @jsonld.frame_document(input_text, frame_text, options) {
    Ok(v) => {
      let _ = @fs.write_file(
        "/tmp/t0057-out.json",
        diag_json_str(@jsonld.canonical_for_suite(v)),
      )
    }
    Err(_) => {
      let _ = @fs.write_file("/tmp/t0057-out.json", "ERROR")
    }
  }
}
