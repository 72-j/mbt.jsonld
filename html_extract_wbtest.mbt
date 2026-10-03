// J9 HTML 面——扫描器白盒钉（常驻件：扫描器是持久面，钉其行为边界）。
// 全 assert 形；byte-inlined，不落探针文件。

///|
/// wbtest 本地取件助手（html_ld_scripts 返回扫描产物束）
fn html_scripts_of(html : String) -> Array[HtmlScript] {
  html_ld_scripts(html).scripts
}

///|
test "html_ld_scripts: single ld+json script with id" {
  let scripts = html_scripts_of(
    "<html><head><script id=\"first\" type=\"application/ld+json\">\n{\"a\":1}\n</script></head></html>",
  )
  assert_true(scripts.length() == 1)
  assert_eq(scripts[0].content, "\n{\"a\":1}\n")
  assert_true(scripts[0].id_attr == Some("first"))
}

///|
test "html_ld_scripts: skips non-ld+json and non-script tags" {
  let scripts = html_scripts_of(
    "<script type=\"application/json\">{\"x\":2}</script><pre type=\"application/ld+json\">{\"y\":3}</pre><script type=\"APPLICATION/LD+JSON\">{\"z\":4}</script>",
  )
  assert_true(scripts.length() == 1)
  assert_eq(scripts[0].content, "{\"z\":4}")
  assert_true(scripts[0].id_attr == None)
}

///|
test "html_ld_scripts: comment outside script does not hide script" {
  let scripts = html_scripts_of(
    "<!-- <script type=\"application/ld+json\">{\"ghost\":1}</script> --><script id=\"real\" type=\"application/ld+json\">{\"real\":1}</script>",
  )
  assert_true(scripts.length() == 1)
  assert_eq(scripts[0].content, "{\"real\":1}")
  assert_true(scripts[0].id_attr == Some("real"))
}

///|
test "html_ld_scripts: textContent keeps comments and entities verbatim" {
  // e014/te010 oracle：原文直通——注释与实体都不解码
  let scripts = html_scripts_of(
    "<script type=\"application/ld+json\">A<!--x-->B&lt;C</script>",
  )
  assert_eq(scripts[0].content, "A<!--x-->B&lt;C")
}

///|
test "html_ld_scripts: EOF truncation closes script" {
  let scripts = html_scripts_of(
    "<script type=\"application/ld+json\">{\"a\":1}",
  )
  assert_true(scripts.length() == 1)
  assert_eq(scripts[0].content, "{\"a\":1}")
}

///|
test "html_ld_scripts: multi-script document order" {
  let scripts = html_scripts_of(
    "<script id=\"one\" type=\"application/ld+json\">{\"a\":1}</script><script id=\"two\" type=\"application/ld+json\">{\"b\":2}</script>",
  )
  assert_true(scripts.length() == 2)
  assert_eq(scripts[0].content, "{\"a\":1}")
  assert_eq(scripts[1].content, "{\"b\":2}")
  assert_true(scripts[1].id_attr == Some("two"))
}

///|
test "html_percent_decode: ascii and percent forms" {
  assert_eq(html_percent_decode("second"), "second")
  assert_eq(html_percent_decode("a%20b"), "a b")
  assert_eq(html_percent_decode("%E6%9C%88"), "月")
  assert_eq(html_percent_decode("bad%2"), "bad%2")
}
