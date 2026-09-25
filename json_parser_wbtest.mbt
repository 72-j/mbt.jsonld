///|
/// json_parser 包装层测试（白盒：直用同包符号）
/// 口径钉子（J0 勘定）：重复键 last-wins 占首现位 / 键序 ≈ 首现序 /
/// 数词形取 double 值 / 语法错误 → JsonLdError::Syntax

///|
test "parse scalars" {
  assert_true(parse_json("null") is Ok(Null))
  assert_true(parse_json("true") is Ok(Bool(true)))
  assert_true(parse_json("false") is Ok(Bool(false)))
  assert_true(parse_json("42") is Ok(Number(42.0)))
  assert_true(parse_json("-1.5") is Ok(Number(-1.5)))
  assert_true(parse_json("\"hi\"") is Ok(String("hi")))
}

///|
test "parse nested structure preserves first-occurrence key order" {
  assert_true(
    parse_json("{\"b\":1,\"a\":[2,null]}")
    is Ok(Object([("b", Number(1.0)), ("a", Array([Number(2.0), Null]))])),
  )
}

///|
test "duplicate keys fold last-wins at first position (J0 口径钉子)" {
  assert_true(
    parse_json("{\"a\":1,\"b\":2,\"a\":3}")
    is Ok(Object([("a", Number(3.0)), ("b", Number(2.0))])),
  )
}

///|
test "syntax error maps to JsonLdError::Syntax" {
  match parse_json("{bad") {
    Err(Syntax(_)) => ()
    _ => fail("expected JsonLdError::Syntax")
  }
}

///|
test "unicode string preserved" {
  assert_true(parse_json("\"中文→🚀\"") is Ok(String("中文→🚀")))
}

///|
test "empty containers" {
  assert_true(parse_json("[]") is Ok(Array([])))
  assert_true(parse_json("{}") is Ok(Object([])))
}
