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

///|
test "html_ld_scripts: markup corner arms" {
  // '<' 残字符 / DOCTYPE / 标签名内杂字符——都不产 script 也不阻断后续
  let scripts = html_scripts_of(
    "< 5<!DOCTYPE html><a!>x<script type=\"application/ld+json\">{\"ok\":1}</script>",
  )
  assert_true(scripts.length() == 1)
  assert_eq(scripts[0].content, "{\"ok\":1}")
}

///|
test "html_ld_scripts: bare attribute value and empty valued attr" {
  // 裸值属性合法识别；空值属性（type=）= 非法媒体类型 → 非 ld+json
  let bare = html_scripts_of(
    "<script type=application/ld+json>{\"bare\":1}</script>",
  )
  assert_true(bare.length() == 1)
  assert_eq(bare[0].content, "{\"bare\":1}")
  let empty_val = html_scripts_of("<script type=>{\"gone\":1}</script>")
  assert_true(empty_val.length() == 0)
}

///|
test "html_ld_scripts: script end-tag corner shapes" {
  // </scriptx 非终止符 → 候选回填续读原文；</script > 带空白 → EndSkip
  let scriptx = html_scripts_of(
    "<script type=\"application/ld+json\">{\"a\":1}</scriptx</script>",
  )
  assert_true(scriptx.length() == 1)
  assert_eq(scriptx[0].content, "{\"a\":1}</scriptx")
  let spaced = html_scripts_of(
    "<script id=\"s\" type=\"application/ld+json\">{\"b\":2}</script >",
  )
  assert_true(spaced.length() == 1)
  assert_true(spaced[0].id_attr == Some("s"))
  assert_eq(spaced[0].content, "{\"b\":2}")
}

///|
test "html_ld_scripts: base href first wins and base without href" {
  // <base href> 首现生效（te020 口径）；无 href 的 <base> 不动基
  let doc = "<head><base href=\"http://a/\"><base href=\"http://b/\"><base></head><script type=\"application/ld+json\">{\"c\":3}</script>"
  let scan = html_ld_scripts(doc)
  assert_true(scan.scripts.length() == 1)
  assert_true(scan.base_href == Some("http://a/"))
}

///|
test "html_percent_decode: mid-string broken hex and raw non-ascii" {
  // '%XX' 破形（第二位非 hex）→ '%' 字面 + 续读；裸非 ASCII 标量直通
  assert_eq(html_percent_decode("a%2gb"), "a%2gb")
  assert_eq(html_percent_decode("月"), "月")
  assert_eq(html_percent_decode("a+b"), "a+b")
}
