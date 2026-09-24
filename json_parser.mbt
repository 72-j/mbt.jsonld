///|
/// JSON 值（保留键序 + 重复键）
/// 关键：不能用 Map——会丢键序与重复键
pub(all) enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[JsonValue])
  /// 对象：用 Array[(String, JsonValue)] 而非 Map
  /// 保留键序与重复键（JSON-LD @context 合并需要）
  Object(Array[(String, JsonValue)])
} derive(Debug)

///|
/// JSON 解析接口
/// J0 勘定：MoonBit 现成解析器是否保留键序 + 重复键
/// 若不保留，需适配或自建
pub fn parse_json(text : String) -> Result[JsonValue, JsonLdError] {
  // TODO(J1): 绑定解析实现（J0 已勘定 core 解析器可用，选型待拍板）
  ignore(text)
  Err(JsonLdError::Unsupported("parse_json: implementation pending J1"))
}
