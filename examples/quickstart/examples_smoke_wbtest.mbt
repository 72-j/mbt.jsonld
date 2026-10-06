// ===== 示例冒烟（依 moonttl/src/examples 制）：本体直调进测试宿主 =====
// 断言锚：全 IRI 解析 / 词表落位 / 空白节点展平 / c14n 签发换名。

///|
test "wb·示例冒烟：六算法全链" {
  let report = six_algorithm_report()
  assert_true(report.contains("https://example.org/alice"))
  assert_true(report.contains("\"who\":\"Alice\""))
  assert_true(report.contains("Bob"))
  assert_true(report.contains("_:c14n0"))
  assert_true(report.contains("http://schema.org/name"))
}
