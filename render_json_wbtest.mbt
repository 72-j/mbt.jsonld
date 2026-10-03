// 役65 库化整形——render_json 晋 pub 白盒钉（转义门 + 往返值等价 + 键序保真）。
// 前科：原 jv_render 字符串零转义带病（含 `"` 晋 pub 会产非法 JSON；
// html 50/50 全绿纯因无此形输入）——本件钉死该族。

///|
test "render_json: string escaping gate" {
  // `"` `\` 控制字符全转义；\b\f\n\r\t 命名形，其余 \u00XX 大写十六进制
  let c1 = Int::unsafe_to_char(1).to_string()
  let c8 = Int::unsafe_to_char(8).to_string()
  let c12 = Int::unsafe_to_char(12).to_string()
  let tricky = "a\"b\\c\nd\te" + c1 + "f" + c12 + "g\rh" + c8 + "i"
  assert_eq(
    render_json(JsonValue::String(tricky)),
    "\"a\\\"b\\\\c\\nd\\te\\u0001f\\fg\\rh\\bi\"",
  )
}

///|
test "render_json: round-trip value equality" {
  // render∘parse 往返值等价（转义族 + 数词形族 + 嵌套族）
  let c127 = Int::unsafe_to_char(0x7f).to_string()
  let samples : Array[JsonValue] = [
    JsonValue::String("quote\"back\\slash\nnewline"),
    JsonValue::String("x" + c127 + "y"), // DEL 0x7F >= 0x20 原样直通
    JsonValue::Number(0.1),
    JsonValue::Number(1.0),
    JsonValue::Number(-2.5e-7),
    JsonValue::Number(1.0e21),
    JsonValue::Number(3.0),
    JsonValue::Array([
      JsonValue::Null,
      JsonValue::Bool(true),
      JsonValue::String("x" + c127 + "y"),
    ]),
    JsonValue::Object([
      ("k", JsonValue::String("\t")),
      ("m", JsonValue::Number(3.0)),
    ]),
  ]
  for sample in samples {
    let text = render_json(sample)
    match parse_json(text) {
      Ok(back) => assert_true(back == sample)
      Err(_) => {
        println("render produced invalid JSON: \{text}")
        assert_true(false)
      }
    }
  }
}

///|
test "render_json: min-JSON shape and key order preserved" {
  // 零空白分隔 + 键序原样（≠ json_canonical：本函数不做规范形）
  assert_eq(
    render_json(
      JsonValue::Object([
        ("b", JsonValue::Number(1.0)),
        ("a", JsonValue::Array([JsonValue::String("s")])),
      ]),
    ),
    "{\"b\":1,\"a\":[\"s\"]}",
  )
}
