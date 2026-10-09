// ===== jsonld 性能基线 harness（常备；役P1 立法，2026-10-09）=====
// 口径：native 后端（preferred_target）；计时 = @async.now()（ms 墙钟）；
//       每场景 warmup 1 + k=5 计时取**中位数**（读数 = perf-baseline.txt）。
// 语料：进程内确定性生成（零仓库膨胀；形状注记同笔入 perf-baseline.txt）。
// 自报行（与套件自报同族，greppable）：
//       `[bench] scenario=<名> n=<规模> median=<ms>ms k=5 runs=[...]`
// 判据线：任一场景中位数回归 >10%（超噪声带）即红——perf-baseline.txt 头。
// 前检纪律：计时前每场景先跑一次**结构断言**（Ok + 规模哨兵）——计错误结果
//       即垃圾读数（⑤勘定工具自身可能被污染；J2 fixture 教训）。

///|
fn main {
  bench_all()
}

///|
fn bench_all() -> Unit {
  scenario_parse_wide()
  scenario_scoped_heavy()
  scenario_expand_wide()
  scenario_expand_deep()
  scenario_expand_nest()
  scenario_compact_wide()
  scenario_flatten_wide()
  scenario_to_rdf_wide()
  scenario_from_rdf_wide()
  scenario_canon_chain()
}

///|
/// 计时轮：warmup 1 + k 次取中位数。返回（中位数 ms，各次读数展示串）。
fn time_median(k : Int, f : () -> Unit) -> (Int, String) {
  f() // warmup：页缓存 / 分配器稳定
  let runs : Array[Int] = []
  for _ in 0..<k {
    let t0 = @async.now()
    f()
    runs.push((@async.now() - t0).to_int())
  }
  runs.sort_by(fn(a, b) { a.compare(b) })
  let disp = StringBuilder()
  for i in 0..<runs.length() {
    if i > 0 {
      disp.write_string(",")
    }
    disp.write_string(runs[i].to_string())
  }
  (runs[runs.length() / 2], disp.to_string())
}

///|
fn report(scenario : String, n : Int, median : Int, runs : String) -> Unit {
  println(
    "[bench] scenario=\{scenario} n=\{n} median=\{median}ms k=5 runs=\{runs}",
  )
}

///|
fn fail(scenario : String, why : String) -> Unit {
  println("[bench-fail] scenario=\{scenario} why=\{why}")
}

///|
/// 全场景共用 options（与 cmd/main make_options 同款缺省；base None）。
fn bench_options() -> @jsonld.JsonLdOptions {
  {
    base: None,
    expand_context: None,
    processing_mode: @jsonld.ProcessingMode::JsonLd11,
    load_context: None,
    rdf_direction: None,
    produce_generalized_rdf: false,
    compact_arrays: true,
    compact_to_relative: true,
    frame_expansion: false,
    omit_graph: false,
    use_native_types: false,
    use_rdf_type: false,
  }
}

// ===== 语料生成（确定性；形状注记见 perf-baseline.txt）=====

///|
/// wide：单节点 N 属性（http://ex/p<i> = "v<i>"）。
/// expand / compact / toRdf / flatten / parse 五场景共用形状。
fn gen_wide_doc(n : Int) -> String {
  let sb = StringBuilder()
  sb.write_string("{\"@id\":\"http://ex/root\"")
  for i in 0..<n {
    sb.write_string(",\"http://ex/p")
    sb.write_string(i.to_string())
    sb.write_string("\":\"v")
    sb.write_string(i.to_string())
    sb.write_string("\"")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
/// wide 配套 compact context：每属性一个短 term（p<i> → http://ex/p<i>）。
fn gen_wide_ctx(n : Int) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  for i in 0..<n {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"p")
    sb.write_string(i.to_string())
    sb.write_string("\":\"http://ex/p")
    sb.write_string(i.to_string())
    sb.write_string("\"")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
/// deep：链式嵌套 D 层（每层 http://ex/p + http://ex/n 下钻；底层哨兵 http://ex/bottom）。
fn gen_deep_doc(depth : Int) -> String {
  let sb = StringBuilder()
  for _ in 0..<depth {
    sb.write_string("{\"http://ex/p\":\"v\",\"http://ex/n\":")
  }
  sb.write_string("{\"http://ex/p\":\"v\",\"http://ex/bottom\":true}")
  for _ in 0..<depth {
    sb.write_string("}")
  }
  sb.to_string()
}

///|
/// nest：单节点 M 属性、每属性经 @nest 入**互异** nest 键（合并机制全展开）。
/// nest 别名 term **前置 + 简单形**（勘定：td 对象形 + 前向引用 = 引擎拒——
/// 别名查表只见已处理面；套件无 oracle，挂账不扩，见 perf-baseline.txt §勘定发现）。
fn gen_nest_ctx(m : Int) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  for i in 0..<m {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"n")
    sb.write_string(i.to_string())
    sb.write_string("\":\"@nest\"")
  }
  for i in 0..<m {
    sb.write_string(",\"t")
    sb.write_string(i.to_string())
    sb.write_string("\":{\"@id\":\"http://ex/t")
    sb.write_string(i.to_string())
    sb.write_string("\",\"@nest\":\"n")
    sb.write_string(i.to_string())
    sb.write_string("\"}")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
/// nest 配套文档：term 名直用——**发裸体**（无外括号；与 context 同拼一根对象）。
fn gen_nest_doc(m : Int) -> String {
  let sb = StringBuilder()
  for i in 0..<m {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"t")
    sb.write_string(i.to_string())
    sb.write_string("\":\"x")
    sb.write_string(i.to_string())
    sb.write_string("\"")
  }
  sb.to_string()
}

///|
/// fromRdf 语料：N 条独立三元组（s<i> p v<i>）。
fn gen_nquads_flat(n : Int) -> String {
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_string("<http://ex/s")
    sb.write_string(i.to_string())
    sb.write_string("> <http://ex/p> \"v")
    sb.write_string(i.to_string())
    sb.write_string("\" .\n")
  }
  sb.to_string()
}

///|
/// canon 语料：N 环 bnode 链（每环 2 条：值 + 下钻）——n-degree 哈希沿线展开。
fn gen_nquads_chain(n : Int) -> String {
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_string("_:b")
    sb.write_string(i.to_string())
    sb.write_string(" <http://ex/p> \"v")
    sb.write_string(i.to_string())
    sb.write_string("\" .\n_:b")
    sb.write_string(i.to_string())
    sb.write_string(" <http://ex/n> _:b")
    sb.write_string((i + 1).to_string())
    sb.write_string("\" .\n")
  }
  sb.to_string()
}

// ===== 场景 =====

///|
/// parse 分解列：wide 文档纯解析（parse_json）——算法面成本 = 总成本 − 解析。
fn scenario_parse_wide() -> Unit {
  let n = 20000
  let doc = gen_wide_doc(n)
  match @jsonld.parse_json(doc) {
    Ok(jv) =>
      if @jsonld.render_json(jv).length() < doc.length() / 2 {
        fail("parse_wide", "parsed value implausibly small")
        return
      }
    Err(_) => {
      fail("parse_wide", "parse err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() { let _ = @jsonld.parse_json(doc) })
  report("parse_wide", n, median, runs)
}

///|
fn scenario_expand_wide() -> Unit {
  let n = 20000
  let doc = gen_wide_doc(n)
  match @jsonld.expand_document(doc, bench_options()) {
    Ok(jv) => {
      let out = @jsonld.render_json(jv)
      if out.find("http://ex/p0") is None ||
        out.find("http://ex/p\{n - 1}") is None {
        fail("expand_wide", "sentinel props missing (truncated corpus?)")
        return
      }
    }
    Err(_) => {
      fail("expand_wide", "expand err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.expand_document(doc, bench_options())
  })
  report("expand_wide", n, median, runs)
}

///|
fn scenario_expand_deep() -> Unit {
  // depth=800：core @json.parse 默认最大嵌深 1024（J0 勘定），贴近上限取信号；
  // 递归/分派成本渐近段形态注记见 perf-baseline.txt。
  let depth = 800
  let doc = gen_deep_doc(depth)
  match @jsonld.expand_document(doc, bench_options()) {
    Ok(jv) =>
      if @jsonld.render_json(jv).find("http://ex/bottom") is None {
        fail("expand_deep", "bottom sentinel missing (depth truncated?)")
        return
      }
    Err(_) => {
      fail("expand_deep", "expand err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.expand_document(doc, bench_options())
  })
  report("expand_deep", depth, median, runs)
}

///|
fn scenario_expand_nest() -> Unit {
  let m = 2000
  let ctx = gen_nest_ctx(m)
  let doc = gen_nest_doc(m)
  let full = "{\"@context\":\{ctx},\{doc}}"
  match @jsonld.expand_document(full, bench_options()) {
    Ok(jv) => {
      // 展开语义：nest 属性上浮——产出**无** "@nest" 键，哨兵 = 首末属性 IRI 在场
      let out = @jsonld.render_json(jv)
      if out.find("\"@nest\"") is Some(_) {
        fail("expand_nest", "@nest keys survived expansion (semantics broken?)")
        return
      }
      if out.find("http://ex/t0") is None || out.find("http://ex/t1999") is None {
        fail("expand_nest", "sentinel props missing (truncated corpus?)")
        return
      }
    }
    Err(_) => {
      fail("expand_nest", "expand err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.expand_document(full, bench_options())
  })
  report("expand_nest", m, median, runs)
}

///|
fn scenario_compact_wide() -> Unit {
  let n = 20000
  let doc = gen_wide_doc(n)
  let ctx = gen_wide_ctx(n)
  match @jsonld.compact_document(doc, ctx, bench_options()) {
    Ok(jv) => {
      let out = @jsonld.render_json(jv)
      if out.find("\"p0\"") is None || out.find("\"p\{n - 1}\"") is None {
        fail("compact_wide", "sentinel terms missing (truncated corpus?)")
        return
      }
    }
    Err(_) => {
      fail("compact_wide", "compact err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.compact_document(doc, ctx, bench_options())
  })
  report("compact_wide", n, median, runs)
}

///|
fn scenario_flatten_wide() -> Unit {
  let n = 20000
  let doc = gen_wide_doc(n)
  match @jsonld.flatten_document(doc, bench_options()) {
    Ok(jv) => {
      let out = @jsonld.render_json(jv)
      if out.find("http://ex/root") is None {
        fail("flatten_wide", "root IRI missing")
        return
      }
    }
    Err(_) => {
      fail("flatten_wide", "flatten err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.flatten_document(doc, bench_options())
  })
  report("flatten_wide", n, median, runs)
}

///|
fn scenario_to_rdf_wide() -> Unit {
  let n = 20000
  let doc = gen_wide_doc(n)
  match @jsonld.to_rdf_document(doc, bench_options()) {
    Ok(quads) =>
      if quads.length() != n {
        fail("to_rdf_wide", "quad count \{quads.length()} != \{n}")
        return
      }
    Err(_) => {
      fail("to_rdf_wide", "toRdf err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.to_rdf_document(doc, bench_options())
  })
  report("to_rdf_wide", n, median, runs)
}

///|
fn scenario_from_rdf_wide() -> Unit {
  // n=4000：首轮实测 n=20000 中位数 25.4s（runs 13.7~37.8s，方差大）——
  // fromRdf 是**头号热点信号**（P3 勘定主发现）；规模降到基线套件可承受量级，
  // 扩散律（线性 vs 二次）留探针批专测。
  let n = 4000
  let nq = gen_nquads_flat(n)
  match @jsonld.from_rdf_document(nq, bench_options()) {
    Ok(jv) => {
      let out = @jsonld.render_json(jv)
      if out.find("http://ex/s\{n - 1}") is None {
        fail("from_rdf_wide", "last subject missing (truncated corpus?)")
        return
      }
    }
    Err(_) => {
      fail(
        "from_rdf_wide", "fromRdf err (复现：moon run cmd/main 同输入)",
      )
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.from_rdf_document(nq, bench_options())
  })
  report("from_rdf_wide", n, median, runs)
}

///|
fn scenario_canon_chain() -> Unit {
  let n = 1500
  let nq = gen_nquads_chain(n)
  match
    @jsonld.rdfc10_canonicalize_with_hash(nq, @jsonld.C14nHashAlgorithm::Sha256) {
    Ok((canonical, _issued)) =>
      if canonical.length() < n * 20 {
        fail("canon_chain", "canonical output implausibly small")
        return
      }
    Err(_) => {
      fail("canon_chain", "canon err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.rdfc10_canonicalize_with_hash(
      nq,
      @jsonld.C14nHashAlgorithm::Sha256,
    )
  })
  report("canon_chain", n, median, runs)
}

///|
/// scoped_heavy（役P1 批7 转正——**COW 回归门**；批6 双判据的负载线钉）：
/// J2 同形 = N 节点 × term-ful property-scoped 应用（父 context 200 terms；
/// 每节点 sc 触发 process_context :3564 克隆径）。守什么：context 克隆路径
/// 的份额与线性（批6 实测 158ms/2000×200 = 0.38µs/term，O(N×T)）——谁动
/// context 复制/共享语义（含 COW），此场景先红。
fn scenario_scoped_heavy() -> Unit {
  let n_nodes = 2000
  let n_terms = 200
  let sb = StringBuilder()
  sb.write_string("{\"@context\":{")
  for i in 0..<n_terms {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"t")
    sb.write_string(i.to_string())
    sb.write_string("\":\"http://ex/t")
    sb.write_string(i.to_string())
    sb.write_string("\"")
  }
  // sc：td 带 @context（property-scoped；含 term 条目 ⇒ 克隆径）
  sb.write_string(
    ",\"sc\":{\"@id\":\"http://ex/sc\",\"@context\":{\"extra\":\"http://ex/extra\"}}",
  )
  sb.write_string("},\"@graph\":[")
  for i in 0..<n_nodes {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"@id\":\"http://ex/n")
    sb.write_string(i.to_string())
    sb.write_string("\",\"sc\":{\"extra\":\"v\"}}")
  }
  sb.write_string("]}")
  let doc = sb.to_string()
  match @jsonld.expand_document(doc, bench_options()) {
    Ok(jv) => {
      let out = @jsonld.render_json(jv)
      // 哨兵：scoped context 已应用（extra 展开在场）+ 全节点数保真
      if out.find("http://ex/extra") is None {
        fail("scoped_heavy", "scoped ctx not applied (clone path idle?)")
        return
      }
      if out.find("http://ex/n1999") is None {
        fail("scoped_heavy", "sentinel node missing (truncated corpus?)")
        return
      }
    }
    Err(_) => {
      fail("scoped_heavy", "expand err (复现：moon run cmd/main 同输入)")
      return
    }
  }
  let (median, runs) = time_median(5, fn() {
    let _ = @jsonld.expand_document(doc, bench_options())
  })
  report("scoped_heavy", n_nodes, median, runs)
}
