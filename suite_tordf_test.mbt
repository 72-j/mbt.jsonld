///|
/// toRdf 套件 harness（J3.0——判定器就位（tordf_judge_test.mbt），管线 J3.1
/// 接线；spec §8 前置勘定）：manifest 驱动 467 例两桶 plain/deferred，pin 闭合。
/// 判定通道（J3.1 起）：正例 = expand → node_to_quads → datasets_isomorphic
/// （expected .nq 经 parse_nquads 归一——RDF Dataset Isomorphism，非 JSON
/// 对拍）；负例 = 管线任一段 Err；句法 = 全程无 Err。选项面 useJCS×23/
/// rdfDirection×4/produceGeneralizedRdf×2 随管线批接线（JCS 独立子役）。
async test "toRdf suite harness: judge ready, all deferred pre-J3.1" {
  let manifest_text = @utf8.decode(
    @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/toRdf-manifest.jsonld").binary(),
  )
  let doc = match @jsonld.parse_json(manifest_text) {
    Ok(doc) => doc
    Err(_) => fail("manifest parse failed")
  }
  let sequence = match json_object_get(doc, "sequence") {
    Some(@jsonld.JsonValue::Array(entries)) => entries
    _ => fail("manifest sequence missing")
  }
  // J3.1 首波迁移（2026-09-28；管线 = to_rdf_document → parse_nquads →
  // datasets_isomorphic； census 416/467——余 51 例挂 J3.2 数值典范形 /
  // J3.3 JCS / J3.4 rdfDirection+generalized / IRI 规则批 / 个案研究）
  let migrated : Array[String] = [
    "#t0001", "#t0002", "#t0003", "#t0004", "#t0005", "#t0006", "#t0007", "#t0008",
    "#t0009", "#t0010", "#t0011", "#t0012", "#t0013", "#t0014", "#t0015", "#t0016",
    "#t0017", "#t0018", "#t0019", "#t0020", "#t0023", "#t0024", "#t0025", "#t0026",
    "#t0027", "#t0028", "#t0029", "#t0030", "#t0031", "#t0032", "#t0033", "#t0034",
    "#t0036", "#t0113", "#t0114", "#t0115", "#t0116", "#t0117", "#t0119", "#t0128",
    "#t0130", "#t0120", "#t0121", "#t0122", "#t0123", "#t0124", "#t0125", "#t0126",
    "#t0127", "#t0129", "#t0131", "#t0132", "#t0133", "#tc001", "#tc002", "#tc003",
    "#tc004", "#tc005", "#tc006", "#tc007", "#tc008", "#tc009", "#tc010", "#tc011",
    "#tc012", "#tc013", "#tc014", "#tc015", "#tc016", "#tc017", "#tc018", "#tc019",
    "#tc020", "#tc021", "#tc022", "#tc023", "#tc024", "#tc025", "#tc026", "#tc027",
    "#tc028", "#tc029", "#tc030", "#tc031", "#tc032", "#tc033", "#tc034", "#tc035",
    "#tc036", "#tc037", "#tc038", "#tdi01", "#tdi02", "#tdi03", "#tdi04", "#tdi05",
    "#tdi06", "#tdi07", "#tdi08", "#te001", "#te002", "#te003", "#te004", "#te005",
    "#te006", "#te007", "#te008", "#te009", "#te010", "#te011", "#te012", "#te013",
    "#te015", "#te016", "#te017", "#te018", "#te019", "#te020", "#te021", "#te022",
    "#te023", "#te024", "#te025", "#te026", "#te027", "#te028", "#te029", "#te030",
    "#te032", "#te033", "#te034", "#te035", "#te037", "#te038", "#te039", "#te040",
    "#te041", "#te042", "#te043", "#te044", "#te045", "#te046", "#te047", "#te048",
    "#te049", "#te050", "#te051", "#te052", "#te053", "#te054", "#te055", "#te056",
    "#te057", "#te058", "#te059", "#te060", "#te062", "#te063", "#te064", "#te065",
    "#te066", "#te067", "#te068", "#te069", "#te070", "#te071", "#te072", "#te073",
    "#te074", "#te076", "#te077", "#te078", "#te079", "#te080", "#te081", "#te082",
    "#te083", "#te084", "#te085", "#te086", "#te087", "#te088", "#te089", "#te090",
    "#te091", "#te092", "#te093", "#te094", "#te095", "#te096", "#te097", "#te098",
    "#te099", "#te100", "#te101", "#te102", "#te103", "#te104", "#te105", "#te106",
    "#te107", "#te109", "#te110", "#te111", "#te112", "#te113", "#te114", "#te115",
    "#te116", "#te117", "#te118", "#te119", "#te120", "#te121", "#te122", "#te123",
    "#te124", "#te125", "#te126", "#te127", "#te128", "#te129", "#te130", "#tec01",
    "#tec02", "#tem01", "#ten01", "#ten02", "#ten03", "#ten04", "#ten05", "#ten06",
    "#tep02", "#tep03", "#ter01", "#ter02", "#ter03", "#ter04", "#ter05", "#ter06",
    "#ter07", "#ter08", "#ter09", "#ter10", "#ter11", "#ter12", "#ter13", "#ter14",
    "#ter15", "#ter17", "#ter18", "#ter19", "#ter20", "#ter21", "#ter22", "#ter23",
    "#ter24", "#ter25", "#ter26", "#ter27", "#ter28", "#ter29", "#ter30", "#ter31",
    "#ter32", "#ter33", "#ter34", "#ter35", "#ter36", "#ter37", "#ter38", "#ter39",
    "#ter40", "#ter41", "#ter42", "#ter43", "#ter44", "#ter48", "#ter49", "#ter50",
    "#ter51", "#ter52", "#ter53", "#ter54", "#ter55", "#ter56", "#tin01", "#tin02",
    "#tin03", "#tin04", "#tin05", "#tin07", "#tin08", "#tin09", "#tli01", "#tli02",
    "#tli03", "#tli04", "#tli05", "#tli06", "#tli07", "#tli08", "#tli09", "#tli10",
    "#tli13", "#tli14", "#tli11", "#tli12", "#tm001", "#tm002", "#tm003", "#tm004",
    "#tm005", "#tm006", "#tm007", "#tm008", "#tm009", "#tm010", "#tm011", "#tm012",
    "#tm013", "#tm014", "#tm015", "#tm016", "#tm017", "#tm018", "#tm019", "#tm020",
    "#tn001", "#tn002", "#tn003", "#tn004", "#tn005", "#tn006", "#tn007", "#tn008",
    "#tnt01", "#tnt02", "#tnt03", "#tnt04", "#tnt05", "#tnt06", "#tnt07", "#tnt08",
    "#tnt09", "#tnt10", "#tnt11", "#tnt12", "#tnt13", "#tnt14", "#tnt15", "#tnt16",
    "#tp001", "#tp002", "#tp003", "#tp004", "#tpi01", "#tpi02", "#tpi03", "#tpi04",
    "#tpi05", "#tpi06", "#tpi07", "#tpi08", "#tpi09", "#tpi10", "#tpi11", "#tpr01",
    "#tpr02", "#tpr03", "#tpr04", "#tpr05", "#tpr06", "#tpr08", "#tpr09", "#tpr10",
    "#tpr11", "#tpr12", "#tpr13", "#tpr14", "#tpr15", "#tpr16", "#tpr17", "#tpr18",
    "#tpr19", "#tpr20", "#tpr21", "#tpr22", "#tpr23", "#tpr24", "#tpr25", "#tpr26",
    "#tpr27", "#tpr28", "#tpr29", "#tpr30", "#tpr31", "#tpr32", "#tpr33", "#tpr34",
    "#tpr35", "#tpr36", "#tpr37", "#tpr38", "#tpr39", "#tpr40", "#tpr41", "#tpr42",
    "#tpr43", "#tso01", "#tso02", "#tso03", "#tso05", "#tso06", "#tso07", "#tso08",
    "#tso09", "#tso10", "#tso11", "#tso12", "#tso13", "#ttn01", "#ttn02", "#twf01",
    "#twf02", "#twf03", "#twf04", "#twf05", "#twf07", "#t0022", "#t0035", "#te031",
    "#te061", "#trt01", "#tjs01", "#tjs02", "#tjs03", "#tjs04", "#tjs05", "#tjs06",
    "#tjs07", "#tjs08", "#tjs09", "#tjs10", "#tjs11", "#tjs12", "#tjs13", "#tjs14",
    "#tjs15", "#tjs16", "#tjs17", "#tjs18", "#tjs19", "#tjs20", "#tjs21", "#tjs22",
    "#tjs23", "#t0118", "#tdi09", "#tdi10", "#tdi11", "#tdi12", "#te075", "#te014",
    "#te036", "#te108", "#tin06",
  ]
  let deferred : Array[String] = []
  let plain : Array[String] = []
  let mut parsed_ok = 0
  let mut parse_err = 0
  for entry in sequence {
    let id = match json_string_get(entry, "@id") {
      Some(id) => id
      None => continue
    }
    // 输入读入 + 解析覆盖通道：全部 467 输入过 parse_json（J0 口径持续验证）
    let input_path = json_string_get(entry, "input")
    if input_path is Some(p) {
      let text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + p).binary(),
      )
      match @jsonld.parse_json(text) {
        Ok(_) => parsed_ok += 1
        Err(_) => parse_err += 1
      }
    }
    // 三态判定（manifest @type）
    let mut is_negative = false
    let mut is_syntax = false
    match json_object_get(entry, "@type") {
      Some(@jsonld.JsonValue::Array(kinds)) =>
        for kind in kinds {
          match kind {
            @jsonld.JsonValue::String(k) => {
              if k == "jld:NegativeEvaluationTest" {
                is_negative = true
              }
              if k == "jld:PositiveSyntaxTest" {
                is_syntax = true
              }
            }
            _ => ()
          }
        }
      _ => ()
    }
    if migrated.contains(id) {
      plain.push(id)
      // 判定管线（J3.1）：expand → node_to_quads → 判定器同构对拍
      // options/preload = harness 全同装配（expand 侧同款垫片——ctx §3 纪律）
      let p = match input_path {
        Some(p) => p
        None => fail("\{id}: migrated but no input")
      }
      let input_text = @utf8.decode(
        @fs.read_file("./src/jsonld/.rdf-tests/json-ld-api/" + p).binary(),
      )
      let context_map : Map[String, String] = Map([])
      match json_object_get(entry, "option") {
        Some(option_value) =>
          match json_string_get(option_value, "expandContext") {
            Some(context_ref) => {
              let tests_anchor = "https://w3c.github.io/json-ld-api/tests/"
              load_one_context(tests_anchor, context_ref, context_map)
            }
            None => ()
          }
        None => ()
      }
      match @jsonld.parse_json(input_text) {
        Ok(parsed_input) =>
          match base_for_entry(entry) {
            Some(anchor_url) =>
              preload_contexts(anchor_url, parsed_input, context_map)
            None => ()
          }
        Err(_) => ()
      }
      let options = options_for(entry, context_map)
      match @jsonld.to_rdf_document(input_text, options) {
        Err(_) => if !is_negative { fail("\{id}: 正例管线报错") }
        Ok(quads) =>
          if is_negative {
            fail("\{id}: 负例意外全绿")
          } else if !is_syntax {
            let expect_path = match json_string_get(entry, "expect") {
              Some(ep) => ep
              None => fail("\{id}: 正例无 expect")
            }
            let expect_text = @utf8.decode(
              @fs.read_file(
                "./src/jsonld/.rdf-tests/json-ld-api/" + expect_path,
              ).binary(),
            )
            let expected = match parse_nquads(expect_text) {
              Ok(qs) => qs
              Err(m) => fail("\{id}: expected 解析失败 \{m}")
            }
            let ours = match parse_nquads(render_nq(quads)) {
              Ok(qs) => qs
              Err(m) => fail("\{id}: 产物解析失败 \{m}")
            }
            if !datasets_isomorphic(ours, expected) {
              fail("\{id}: 数据集不同构")
            }
          }
      }
    } else {
      deferred.push(id)
    }
  }
  // pin 闭合：桶总和 == 普查数（467 = 345 正 + 106 负 + 16 句法——spec §8.1）
  assert_eq(deferred.length(), 0)
  assert_eq(plain.length(), 467)
  // 复核面自报行（J4；suite-review.txt 抽取源——勿改格式）
  println(
    "[toRdf] entries=\{sequence.length()} plain=\{plain.length()} deferred=\{deferred.length()}",
  )
  assert_eq(parsed_ok + parse_err, 467)
  assert_true(parse_err == 0)
}
