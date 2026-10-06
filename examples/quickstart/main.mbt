// ===== jsonld 示例：六算法全链走览 =====
// 依 ttl/src/examples 制（役 A 结构性裁决）：main 只留进程入口，
// 本体 six_algorithm_report() 进测试宿主（examples_smoke_wbtest.mbt 直调）。
// 库 API = 纯同步 String→Result，示例零 fs / 零 async、零新增依赖。

///|
/// 进程入口（依制：本体在 six_algorithm_report，wbtest 直调；main 只打印）。
fn main {
  println(six_algorithm_report())
}

///|
/// 报告节标题行。
fn section(title : String, body : String) -> String {
  "=== \{title} ===\n\{body}\n"
}
