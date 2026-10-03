// RDFC-1.0 (URDNA2015) canonicalization, W3C REC 2023-08-22
// (spec.md section 8.132 route A; suite git anchor 15619df2fda7a4ca88308733789b6774517f9638).
// Six-step main algorithm per section 4.4.3 (main), 4.5.2 (issue
// identifier), 4.6.3 (hash first degree quads), 4.7.3 (hash related
// blank node), 4.8.3 (hash n-degree quads); output serialization per
// appendix A canonical N-Quads. Input parses through the fromRDF face
// N-Quads parser (nquads_parse.mbt); SHA-256 (sha256.mbt) supplies the
// bnode ordering keys as lowercase hex strings. Suite anchors live in
// canon_rdfc10_wbtest.mbt (byte-inlined suite pairs); the full 86-entry
// harness is the next battle (canon_rdfc10_test.mbt).

///|
/// Identifier issuer (section 4.5.2): prefix + counter. `issued` maps
/// existing identifiers to issued ones; `order` preserves issuance order
/// because main step 5.3 replays it in the same order. Issuers are shared
/// by reference through the n-degree recursion (section 4.8.3 step
/// 5.4.5.4), so issue() mutates in place.
priv struct C14nIssuer {
  prefix : String
  issued : Map[String, String]
  order : Array[String]
  mut counter : Int
}

///|
/// Issue Identifier (section 4.5.2): an existing mapping wins; a new
/// mapping takes prefix + counter and records its issuance order.
fn C14nIssuer::issue(self : C14nIssuer, existing : String) -> String {
  match self.issued.get(existing) {
    Some(issued) => issued
    None => {
      let issued = self.prefix + self.counter.to_string()
      self.issued[existing] = issued
      self.order.push(existing)
      self.counter = self.counter + 1
      issued
    }
  }
}

///|
/// Copy for the per-permutation issuer copies (section 4.8.3 step
/// 5.4.4.1): fresh issued map and order array carrying the same state.
fn C14nIssuer::fresh_copy(self : C14nIssuer) -> C14nIssuer {
  let issued : Map[String, String] = Map([])
  for existing, mapped in self.issued {
    issued[existing] = mapped
  }
  {
    prefix: self.prefix,
    issued,
    order: self.order.copy(),
    counter: self.counter,
  }
}

///|
/// Hash algorithm option (REC section 3.1 hashAlgorithm; suite pins the
/// SHA384 variant on test075). Default SHA256.
pub(all) enum C14nHashAlgorithm {
  Sha256
  Sha384
} derive(Eq)

///|
/// [0079] 消警：Eq 派生的 equal/not_equal 显式升格（const §5——derive 须同笔补
/// extend；役59 漏此条，2026-10-03 deny-warn 门红暴露）
pub extend C14nHashAlgorithm with Eq::{not_equal, equal}

///|
/// Canonicalization state (section 4.4.3 steps 1-2): the parsed quads,
/// the blank node to quads map (label -> quad indices), the canonical
/// issuer (prefix c14n) and a work budget defending the poison clique
/// suite entry (test074c NegativeEvalTest: signal failure instead of
/// exhausting resources; the real high-complexity tests 044-046 stay
/// orders of magnitude below it).
priv struct C14nState {
  quads : Array[NqQuad]
  bnode_to_quads : Map[String, Array[Int]]
  canonical_issuer : C14nIssuer
  hash_algorithm : C14nHashAlgorithm
  mut work_budget : Int
}

///|
/// Work budget in units of one hash-n-degree call or permutation attempt.
const C14N_WORK_BUDGET : Int = 1000000

///|
/// Steps 1-2: index every quad under each of its blank node components
/// (subject / object / graph name).
fn C14nState::build(
  quads : Array[NqQuad],
  hash_algorithm : C14nHashAlgorithm,
) -> C14nState {
  let unique_quads : Array[NqQuad] = []
  let seen : Map[String, Bool] = Map([])
  for quad in quads {
    let key = c14n_quad_key(quad)
    match seen.get(key) {
      Some(_) => ()
      None => {
        seen[key] = true
        unique_quads.push(quad)
      }
    }
  }
  let bnode_to_quads : Map[String, Array[Int]] = Map([])
  for quad_index, quad in unique_quads {
    for component in c14n_bnode_components(quad) {
      let (label, _position) = component
      match bnode_to_quads.get(label) {
        Some(indices) => indices.push(quad_index)
        None => bnode_to_quads[label] = [quad_index]
      }
    }
  }
  {
    quads: unique_quads,
    bnode_to_quads,
    canonical_issuer: {
      prefix: "c14n",
      issued: Map([]),
      order: [],
      counter: 0,
    },
    hash_algorithm,
    work_budget: C14N_WORK_BUDGET,
  }
}

///|
/// Dedup key for a quad: the four serialized terms with an explicit
/// graph marker (None / Some differs only by arity, never content).
fn c14n_quad_key(quad : NqQuad) -> String {
  let raw_terms = fn(term : NqTerm) -> String {
    c14n_serialize_term(term, fn(_label) { None })
  }
  let graph_marker = match quad.graph {
    Some(graph) => raw_terms(graph)
    None => "-"
  }
  raw_terms(quad.subject) +
  " " +
  raw_terms(quad.predicate) +
  " " +
  raw_terms(quad.object) +
  " " +
  graph_marker
}

///|
/// Blank node components of a quad in spec order with their position
/// markers (sections 4.6.3/4.8.3: s / o / g; the predicate is always an
/// IRI and never a blank node).
fn c14n_bnode_components(quad : NqQuad) -> Array[(String, String)] {
  let components : Array[(String, String)] = []
  match quad.subject {
    NqBnodeTerm(label) => components.push((label, "s"))
    _ => ()
  }
  match quad.object {
    NqBnodeTerm(label) => components.push((label, "o"))
    _ => ()
  }
  match quad.graph {
    Some(NqBnodeTerm(label)) => components.push((label, "g"))
    _ => ()
  }
  components
}

///|
/// Code point order comparison (the spec's universal ordering rule):
/// walk both strings as code point sequences; Char::to_int is the code
/// point. (String::compare is length-first — not the spec order.)
fn c14n_compare(first : String, second : String) -> Int {
  let first_iter = first.iter()
  let second_iter = second.iter()
  let mut first_next = first_iter.next()
  let mut second_next = second_iter.next()
  while first_next != None && second_next != None {
    let first_char = first_next.unwrap()
    let second_char = second_next.unwrap()
    if first_char != second_char {
      return first_char.to_int() - second_char.to_int()
    }
    first_next = first_iter.next()
    second_next = second_iter.next()
  }
  if first_next != None {
    1
  } else if second_next != None {
    -1
  } else {
    0
  }
}

///|
/// Map keys in code point order (the spec's ordered maps all drive their
/// iteration through this: main steps 4-5, section 4.8.3 step 5).
fn c14n_sorted_keys(source : Map[String, Array[String]]) -> Array[String] {
  let keys : Array[String] = []
  for key, _bucket in source {
    keys.push(key)
  }
  keys.sort_by(fn(first, second) { c14n_compare(first, second) })
  keys
}

///|
/// Uppercase hex digit for \uXXXX UCHAR forms (appendix A: HEX digits
/// uppercase; the JCS helper nq_hex_char is lowercase and stays JCS-only).
fn c14n_hex_upper(digit : Int) -> Char {
  let value = if digit < 10 { 48 + digit } else { 55 + digit }
  Int::unsafe_to_char(value)
}

///|
/// Append one \uXXXX escape with uppercase HEX digits.
fn c14n_write_uchar(out : StringBuilder, point : Int) -> Unit {
  out.write_string("\\u")
  out.write_char(c14n_hex_upper(point / 4096 % 16))
  out.write_char(c14n_hex_upper(point / 256 % 16))
  out.write_char(c14n_hex_upper(point / 16 % 16))
  out.write_char(c14n_hex_upper(point % 16))
}

///|
/// STRING_LITERAL_QUOTE canonical escaping (appendix A): ECHAR for
/// BS/HT/LF/FF/CR/quote/backslash; UCHAR for the other control characters
/// (0x00-0x1F), DEL (0x7F) and non-Chars (surrogates); every other code
/// point passes raw (UTF-8 on the wire).
fn c14n_escape_string(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    let point = ch.to_int()
    if point == 92 {
      out.write_string("\\\\")
    } else if point == 34 {
      out.write_string("\\\"")
    } else if point == 10 {
      out.write_string("\\n")
    } else if point == 13 {
      out.write_string("\\r")
    } else if point == 9 {
      out.write_string("\\t")
    } else if point == 8 {
      out.write_string("\\b")
    } else if point == 12 {
      out.write_string("\\f")
    } else if (point >= 0 && point <= 31) ||
      point == 127 ||
      (point >= 0xD800 && point <= 0xDFFF) {
      c14n_write_uchar(out, point)
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// IRI canonical escaping (appendix A): UCHAR only where the IRIREF
/// production forbids the raw character (controls 0x00-0x20, quote, angle
/// brackets, braces, pipe, caret, backtick, backslash); the rest passes
/// raw.
fn c14n_escape_iri(iri : String) -> String {
  let out = StringBuilder()
  for ch in iri {
    let point = ch.to_int()
    let forbidden = point <= 32 ||
      point == 34 ||
      point == 60 ||
      point == 62 ||
      point == 123 ||
      point == 124 ||
      point == 125 ||
      point == 94 ||
      point == 96 ||
      point == 92 ||
      (point >= 0xD800 && point <= 0xDFFF)
    if forbidden {
      c14n_write_uchar(out, point)
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Canonical N-Quads term serialization (appendix A). Blank node labels
/// go through the label override (first-degree _:a/_:z forcing, canonical
/// c14n relabeling, raw passthrough as the total-function fallback);
/// xsd:string datatype is suppressed; langtags lowercase.
fn c14n_serialize_term(term : NqTerm, label : (String) -> String?) -> String {
  match term {
    NqIriTerm(iri) => "<" + c14n_escape_iri(iri) + ">"
    NqBnodeTerm(raw_label) =>
      match label(raw_label) {
        Some(overridden) => "_:" + overridden
        None => "_:" + raw_label
      }
    NqLitTerm(value, datatype, langtag) => {
      let out = StringBuilder()
      out.write_string("\"" + c14n_escape_string(value) + "\"")
      match langtag {
        Some(tag) => out.write_string("@" + nq_lowercase(tag))
        None => ()
      }
      match datatype {
        Some(datatype_iri) =>
          if datatype_iri != XSD_STRING {
            out.write_string("^^<" + c14n_escape_iri(datatype_iri) + ">")
          }
        None => ()
      }
      out.to_string()
    }
  }
}

///|
/// Canonical N-Quads line for one quad (appendix A): terms + optional
/// graph term + " ." — the line feed is part of the form (sorted lines
/// concatenate directly into the canonical document).
fn c14n_quad_line(quad : NqQuad, label : (String) -> String?) -> String {
  let out = StringBuilder()
  out.write_string(c14n_serialize_term(quad.subject, label))
  out.write_string(" ")
  out.write_string(c14n_serialize_term(quad.predicate, label))
  out.write_string(" ")
  out.write_string(c14n_serialize_term(quad.object, label))
  match quad.graph {
    Some(graph) => {
      out.write_string(" ")
      out.write_string(c14n_serialize_term(graph, label))
    }
    None => ()
  }
  out.write_string(" .\n")
  out.to_string()
}

///|
/// Hash First Degree Quads (section 4.6.3): serialize each quad holding
/// the identifier with self forced to _:a and every other blank node to
/// _:z, sort the lines code point order, hash the concatenation.

///|
/// Digest dispatch (the single point where the hash algorithm option
/// materializes; every ordering key goes through here).
fn C14nState::digest_utf8_hex(self : C14nState, input : String) -> String {
  match self.hash_algorithm {
    C14nHashAlgorithm::Sha256 => sha256_utf8_hex(input)
    C14nHashAlgorithm::Sha384 => sha384_utf8_hex(input)
  }
}

///|
/// Hash First Degree Quads (section 4.6.3): serialize each quad holding
/// the identifier with self forced to _:a and every other blank node to
/// _:z, sort the lines code point order, hash the concatenation.
fn C14nState::hash_first_degree(
  self : C14nState,
  identifier : String,
) -> String {
  let lines : Array[String] = []
  match self.bnode_to_quads.get(identifier) {
    Some(quad_indices) =>
      for quad_index in quad_indices {
        let quad = self.quads[quad_index]
        let forced_label = fn(label : String) -> String? {
          if label == identifier {
            Some("a")
          } else {
            Some("z")
          }
        }
        lines.push(c14n_quad_line(quad, forced_label))
      }
    None => ()
  }
  lines.sort_by(fn(first, second) { c14n_compare(first, second) })
  let concatenated = StringBuilder()
  for line in lines {
    concatenated.write_string(line)
  }
  self.digest_utf8_hex(concatenated.to_string())
}

///|
/// Hash Related Blank Node (section 4.7.3): the position marker, then the
/// predicate (every position except g), then the related identifier as
/// canonical label, temporary label, or — when unissued — its first
/// degree hash verbatim (no label prefix).
fn C14nState::hash_related_blank_node(
  self : C14nState,
  related : String,
  quad : NqQuad,
  issuer : C14nIssuer,
  position : String,
) -> String {
  let input = StringBuilder()
  input.write_string(position)
  if position != "g" {
    let predicate_iri = match quad.predicate {
      NqIriTerm(iri) => iri
      _ => ""
    }
    input.write_string("<" + predicate_iri + ">")
  }
  match self.canonical_issuer.issued.get(related) {
    Some(canonical) => input.write_string("_:" + canonical)
    None =>
      match issuer.issued.get(related) {
        Some(temporary) => input.write_string("_:" + temporary)
        None => input.write_string(self.hash_first_degree(related))
      }
  }
  self.digest_utf8_hex(input.to_string())
}

///|
/// Next lexicographic permutation in place (Steinhaus-style
/// next-permutation); false when the sequence is at its last arrangement.
/// Duplicate labels collapse to one arrangement each — semantically
/// equivalent (equal paths never displace the chosen one) and cheaper.
fn c14n_next_permutation(items : Array[String]) -> Bool {
  let length = items.length()
  let mut pivot = length - 1
  while pivot > 0 && c14n_compare(items[pivot - 1], items[pivot]) >= 0 {
    pivot = pivot - 1
  }
  if pivot == 0 {
    return false
  }
  let mut successor = length - 1
  while c14n_compare(items[successor], items[pivot - 1]) <= 0 {
    successor = successor - 1
  }
  let swapped = items[pivot - 1]
  items[pivot - 1] = items[successor]
  items[successor] = swapped
  let mut left = pivot
  let mut right = length - 1
  while left < right {
    let reversed = items[left]
    items[left] = items[right]
    items[right] = reversed
    left = left + 1
    right = right - 1
  }
  true
}

///|
/// Hash N-Degree Quads (section 4.8.3). Mutates path_issuer in place (the
/// recursion shares the permutation's issuer copy by reference, step
/// 5.4.5.4) and returns the hash together with the possibly extended
/// issuer. The work budget gates every recursive call and permutation
/// attempt; an exhausted budget yields an empty hash that the main loop
/// converts into JsonLdError (poison clique, suite test074c).
fn C14nState::hash_n_degree(
  self : C14nState,
  identifier : String,
  path_issuer : C14nIssuer,
) -> (String, C14nIssuer) {
  if self.work_budget <= 0 {
    return ("", path_issuer)
  }
  self.work_budget = self.work_budget - 1
  let hash_to_bnodes : Map[String, Array[String]] = Map([])
  match self.bnode_to_quads.get(identifier) {
    Some(quad_indices) =>
      for quad_index in quad_indices {
        let quad = self.quads[quad_index]
        for component in c14n_bnode_components(quad) {
          let (related, position) = component
          if related != identifier {
            let related_hash = self.hash_related_blank_node(
              related, quad, path_issuer, position,
            )
            match hash_to_bnodes.get(related_hash) {
              Some(bucket) => bucket.push(related)
              None => hash_to_bnodes[related_hash] = [related]
            }
          }
        }
      }
    None => ()
  }
  let data_to_hash = StringBuilder()
  let mut issuer = path_issuer
  for related_hash in c14n_sorted_keys(hash_to_bnodes) {
    data_to_hash.write_string(related_hash)
    let blank_node_list = hash_to_bnodes.get(related_hash).unwrap()
    let working_list = blank_node_list.copy()
    working_list.sort_by(fn(first, second) { c14n_compare(first, second) })
    let mut chosen_path = ""
    let mut chosen_issuer : C14nIssuer? = None
    let mut budget_exhausted = false
    let mut enumeration_done = false
    while !enumeration_done {
      if self.work_budget <= 0 {
        budget_exhausted = true
        enumeration_done = true
        continue
      }
      self.work_budget = self.work_budget - 1
      let mut issuer_copy = issuer.fresh_copy()
      let mut path = ""
      let recursion_list : Array[String] = []
      let mut pruned = false
      for related in working_list {
        match self.canonical_issuer.issued.get(related) {
          Some(canonical) => path = path + "_:" + canonical
          None => {
            if !issuer_copy.issued.contains(related) {
              recursion_list.push(related)
            }
            let temporary = issuer_copy.issue(related)
            path = path + "_:" + temporary
          }
        }
        if chosen_path != "" &&
          path.length() >= chosen_path.length() &&
          c14n_compare(path, chosen_path) > 0 {
          pruned = true
          break
        }
      }
      if !pruned {
        for related in recursion_list {
          let (result_hash, result_issuer) = self.hash_n_degree(
            related, issuer_copy,
          )
          let already_issued = issuer_copy.issue(related)
          path = path + "_:" + already_issued + "<" + result_hash + ">"
          issuer_copy = result_issuer
          if chosen_path != "" &&
            path.length() >= chosen_path.length() &&
            c14n_compare(path, chosen_path) > 0 {
            pruned = true
            break
          }
        }
      }
      if !pruned {
        if chosen_path == "" || c14n_compare(path, chosen_path) < 0 {
          chosen_path = path
          chosen_issuer = Some(issuer_copy)
        }
      }
      if !c14n_next_permutation(working_list) {
        enumeration_done = true
      }
    }
    if budget_exhausted {
      return ("", issuer)
    }
    data_to_hash.write_string(chosen_path)
    match chosen_issuer {
      Some(next_issuer) => issuer = next_issuer
      None => ()
    }
  }
  (self.digest_utf8_hex(data_to_hash.to_string()), issuer)
}

///|
/// Main canonicalization loop (section 4.4.3 steps 3-7): first degree
/// hashes group the blank nodes (step 3); unique-hash nodes take
/// canonical labels immediately (step 4); each remaining group explores
/// n-degree hash paths (step 5) and replays every temporary issuer's
/// order into the canonical issuer; finally all quads serialize under
/// canonical labels and sort code point order (steps 6-7).
fn C14nState::run(
  self : C14nState,
) -> Result[(String, Map[String, String]), JsonLdError] {
  let hash_to_bnodes : Map[String, Array[String]] = Map([])
  for label, _indices in self.bnode_to_quads {
    let first_degree = self.hash_first_degree(label)
    match hash_to_bnodes.get(first_degree) {
      Some(bucket) => bucket.push(label)
      None => hash_to_bnodes[first_degree] = [label]
    }
  }
  for first_degree in c14n_sorted_keys(hash_to_bnodes) {
    let bucket = hash_to_bnodes.get(first_degree).unwrap()
    if bucket.length() == 1 {
      let _issued = self.canonical_issuer.issue(bucket[0])
      let _removed = hash_to_bnodes.remove(first_degree)
    }
  }
  let mut poisoned = false
  for first_degree in c14n_sorted_keys(hash_to_bnodes) {
    let identifier_list = hash_to_bnodes.get(first_degree).unwrap()
    let hash_path_list : Array[(String, C14nIssuer, Int)] = []
    for n in identifier_list {
      match self.canonical_issuer.issued.get(n) {
        Some(_) => ()
        None => {
          let temporary_issuer : C14nIssuer = {
            prefix: "b",
            issued: Map([]),
            order: [],
            counter: 0,
          }
          let _temporary = temporary_issuer.issue(n)
          let (result_hash, result_issuer) = self.hash_n_degree(
            n, temporary_issuer,
          )
          hash_path_list.push(
            (result_hash, result_issuer, hash_path_list.length()),
          )
        }
      }
    }
    hash_path_list.sort_by(fn(first, second) {
      let by_hash = c14n_compare(first.0, second.0)
      if by_hash != 0 {
        by_hash
      } else {
        first.2 - second.2
      }
    })
    for entry in hash_path_list {
      let result_issuer = entry.1
      for existing in result_issuer.order {
        let _canonical = self.canonical_issuer.issue(existing)
      }
    }
    if self.work_budget <= 0 {
      poisoned = true
    }
  }
  if poisoned {
    return Err(
      JsonLdError::Unsupported(
        "RDFC-1.0 canonicalization aborted: work budget exhausted (poison graph)",
      ),
    )
  }
  let lines : Array[String] = []
  for quad in self.quads {
    let canonical_label = fn(label : String) -> String? {
      self.canonical_issuer.issued.get(label)
    }
    lines.push(c14n_quad_line(quad, canonical_label))
  }
  lines.sort_by(fn(first, second) { c14n_compare(first, second) })
  let canonical_form = StringBuilder()
  for line in lines {
    canonical_form.write_string(line)
  }
  Ok((canonical_form.to_string(), self.canonical_issuer.issued))
}

///|
/// Full-option entry (REC section 3.1): the hash algorithm selects the
/// SHA384 variant pinned by suite test075. Output shape matches the
/// mapping variant.
///
/// **真调用点（开工钉，2026-10-03 役62）**：唯一外部调用者 = **套件 harness**
/// `suite_canon_test.mbt`（blackbox `_test.mbt` 伪包，86 例 candidates）——
/// 故本入口**保留 `pub`**；库内其余入口（`rdfc10_canonicalize` /
/// `_with_mapping` / `sha256_hex` / `sha256_utf8_hex` / `sha384_hex` /
/// `sha384_utf8_hex`）真调用点全在包内（内部委托 + wbtest），本轮**已收 `priv`**。
/// **非通用 API 承诺**：暴露面随 harness 裁量收缩（改走内部入口即同笔收 `priv`）。
pub fn rdfc10_canonicalize_with_hash(
  input_nquads : String,
  hash_algorithm : C14nHashAlgorithm,
) -> Result[(String, Map[String, String]), JsonLdError] {
  match nq2_parse(input_nquads) {
    Ok(quads) => C14nState::build(quads, hash_algorithm).run()
    Err(message) => Err(JsonLdError::Syntax(message))
  }
}
