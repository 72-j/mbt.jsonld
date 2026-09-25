///|
/// JSON 值（内部文档模型）
/// 实施卷口径（spec.md §7 / J0 勘定 2026-09-25）：包装官方 core 解析器
/// （moonbitlang/core/json，工具链内置零依赖），不自建解析层。
/// Object 收有序对——core 按 Map 折叠后转出：重复键 last-wins（占首现位）、
/// 键序 ≈ 首现序（1.1 算法按属性排序 + 输出侧自排序，键序挂账 J2 对拍收口）。
pub(all) enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[JsonValue])
  /// 对象：有序对数组而非 Map——模型面保「键 → 值」成对形状（core 侧折叠语义见上）
  Object(Array[(String, JsonValue)])
} derive(Debug)

///|
/// JSON 解析接口：官方解析器包装
/// 挂账注记（J0）：数词形超 double 精确域时 core 留 `repr~`，本层暂弃——
/// toRDF 数词形按值还是按原文，J3 对套件实证（DataRoundTripping 族 + useJCS 23 例）后再定。
pub fn parse_json(text : String) -> Result[JsonValue, JsonLdError] {
  let parsed = try @json.parse(text) catch {
    err => return Err(JsonLdError::Syntax("JSON parse error: \{err}"))
  } noraise {
    v => v
  }
  Ok(json_to_value(parsed))
}

///|
/// core Json → JsonValue 绑定
fn json_to_value(value : Json) -> JsonValue {
  match value {
    Json::Null => JsonValue::Null
    Json::True => JsonValue::Bool(true)
    Json::False => JsonValue::Bool(false)
    Json::Number(n, ..) => JsonValue::Number(n)
    Json::String(s) => JsonValue::String(s)
    Json::Array(items) => JsonValue::Array(items.map(json_to_value))
    Json::Object(fields) => {
      let pairs : Array[(String, JsonValue)] = []
      for name, item in fields {
        pairs.push((name, json_to_value(item)))
      }
      JsonValue::Object(pairs)
    }
  }
}
