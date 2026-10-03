///|
/// RDFC-1.0 suite harness: W3C rdf-canon suite, 86 entries
/// (64 Eval + 21 Map + 1 Negative). Eval = canonical form byte-compare
/// vs the result file; Map = issued-identifiers ledger vs the suite's
/// map json (REC 4.4.3 step 6 output); Negative = work-budget error.
/// Every entry gets a real verdict — no dialect buckets on this face
/// (the canon face has no dialect axis; the plain bucket is the whole
/// suite).
async test "RDFC-1.0 suite harness: manifest-driven buckets" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/rdf-canon/manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "entries") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("pin shape changed: manifest entries missing")
  }
  let deferred : Array[String] = []
  let plain : Array[String] = []
  for entry in sequence {
    let id = match json_string_get(entry, "id") {
      Some(id) => id
      None => continue
    }
    let kind = match json_string_get(entry, "type") {
      Some(kind) => kind
      None => fail("\{id}: manifest @type missing")
    }
    let action = match json_string_get(entry, "action") {
      Some(action) => action
      None => fail("\{id}: manifest action missing")
    }
    let input_text = @utf8.decode(
      @fs.read_file("./src/jsonld/.rdf-tests/rdf-canon/" + action).binary(),
    )
    let hash_algorithm = match json_string_get(entry, "hashAlgorithm") {
      Some("SHA384") => @jsonld.C14nHashAlgorithm::Sha384
      _ => @jsonld.C14nHashAlgorithm::Sha256
    }
    if kind == "rdfc:RDFC10NegativeEvalTest" {
      match @jsonld.rdfc10_canonicalize_with_hash(input_text, hash_algorithm) {
        Ok(_) => fail("\{id}: poison expected to error")
        Err(@jsonld.JsonLdError::Unsupported(_)) => plain.push(id)
        Err(_) => fail("\{id}: wrong error family")
      }
      continue
    }
    if kind == "rdfc:RDFC10MapTest" {
      let map_path = match json_string_get(entry, "result") {
        Some(result) => result
        None => fail("\{id}: map test without result ledger")
      }
      let map_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/rdf-canon/" + map_path).binary(),
      )
      let expected_map = match @jsonld.parse_json(map_text) {
        Ok(@jsonld.JsonValue::Object(pairs)) => {
          let ledger : Map[String, String] = Map([])
          for pair in pairs {
            match pair.1 {
              @jsonld.JsonValue::String(canonical) => ledger[pair.0] = canonical
              _ => fail("\{id}: map ledger value not a string")
            }
          }
          ledger
        }
        _ => fail("\{id}: map ledger parse failed")
      }
      match @jsonld.rdfc10_canonicalize_with_hash(input_text, hash_algorithm) {
        Err(_) => fail("\{id}: map test canonicalization errored")
        Ok((_form, ours)) => {
          if ours.length() != expected_map.length() {
            fail(
              "\{id}: ledger size ours=\{ours.length()} want=\{expected_map.length()}",
            )
          }
          for original, canonical in expected_map {
            match ours.get(original) {
              Some(assigned) =>
                if assigned != canonical {
                  fail(
                    "\{id}: \{original} assigned \{assigned} want \{canonical}",
                  )
                }
              None => fail("\{id}: \{original} missing from ours")
            }
          }
          plain.push(id)
        }
      }
      continue
    }
    // rdfc:RDFC10EvalTest (the remaining kind): byte compare.
    let result_path = match json_string_get(entry, "result") {
      Some(result) => result
      None => fail("\{id}: eval test without result")
    }
    let result_text = @utf8.decode(
      @fs.read_file("./src/jsonld/.rdf-tests/rdf-canon/" + result_path).binary(),
    )
    match @jsonld.rdfc10_canonicalize_with_hash(input_text, hash_algorithm) {
      Err(_) => fail("\{id}: eval canonicalization errored")
      Ok((ours, _mapping)) =>
        if ours != result_text {
          let mut first_diff = ""
          let shared = if ours.length() < result_text.length() {
            ours.length()
          } else {
            result_text.length()
          }
          for i in 0..<shared {
            if ours[i] != result_text[i] {
              first_diff = "at byte \{i}: ours=\{ours[i]} want=\{result_text[i]}"
              break
            }
          }
          fail("\{id}: byte mismatch \{first_diff}")
        } else {
          plain.push(id)
        }
    }
  }
  assert_eq(plain.length() + deferred.length(), sequence.length())
  assert_eq(plain.length(), 86)
  // 复核面自报行（J4；suite-review.txt 抽取源——勿改格式）
  println(
    "[canon] entries=\{sequence.length()} plain=\{plain.length()} deferred=\{deferred.length()}",
  )
  assert_eq(deferred.length(), 0)
}
