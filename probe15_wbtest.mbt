///|
test "probe t0015 trace" {
  let input_text = "[{\"@id\":\"urn:record\",\"@type\":\"urn:Record\"},{\"@id\":\"urn:record\",\"urn:hasStatement\":{\"@id\":\"urn:vs\"}},{\"@id\":\"_:v9\",\"@type\":\"urn:VitalSign\"},{\"@id\":\"_:v9\",\"urn:vitalName\":{\"@id\":\"_:cv\"}},{\"@id\":\"_:bp\",\"@type\":\"urn:BP\"},{\"@id\":\"_:bp\",\"urn:systolic\":{\"@id\":\"_:v9\"}},{\"@id\":\"urn:vs\",\"urn:belongsTo\":{\"@id\":\"urn:record\"},\"urn:bp\":{\"@id\":\"_:bp\"}}]"
  let frame_text = "{\"@context\":{\"@vocab\":\"urn:\"},\"@type\":[\"urn:Record\",\"urn:VitalSigns\"]}"
  let options : JsonLdOptions = {
    base: None,
    expand_context: None,
    processing_mode: ProcessingMode::JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
  }
  let values = match expand_top_values(input_text, options) {
    Ok(v) => v
    Err(_) => fail("expand err")
  }
  let merge_ctx : MergeCtx = { anon: 0, seen: Map([]) }
  for value in values {
    let _ = nq_merge_same_id(value, merge_ctx, "")
  }
  let state : FrameState = {
    graph_name: "@merged",
    graph_map: Map([]),
    bnode_counter: 0,
    embedded: false,
    embed_stack: [],
    embedded_map: Map([]),
    last_locations: Map([]),
    probe: Some(""),
  }
  let relabel_seen : Map[String, String] = Map([])
  for value in values {
    frame_relabel_bnodes(state, value, relabel_seen)
  }
  for value in values {
    let _ = frame_register(state, "@default", value)
  }
  let frame_expanded = match expand_top_values(frame_text, options) {
    Ok(v) => v
    Err(_) => fail("frame expand err")
  }
  let frame_root : ExpandedNode = match frame_expanded.get(0) {
    Some(ExpandedValue::Node(pattern)) => pattern
    _ => frame_empty_pattern()
  }
  let results : Array[ExpandedValue] = []
  let subjects = frame_subject_map(state).keys().collect()
  subjects.sort()
  frame_invoke(state, subjects, frame_root, Top(results))
  let dump = match state.probe {
    Some(t) => t
    None => "(no probe)"
  }
  fail("PROBE-DUMP\n" + dump)
}
