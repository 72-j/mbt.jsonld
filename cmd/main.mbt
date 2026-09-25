// ===== jsonld_gen 再生入口 =====
// 用法：moon run src/jsonld/cmd（改 jsonld_gen.toml 后重跑；
// 黄金门 gen_gate_test.mbt 对拍：重生成 ≡ 入库 gen.mbt 逐字节）

///|
async fn main {
  let toml_text = @utf8.decode(
    @fs.read_file("./src/jsonld/jsonld_gen.toml").binary(),
  )
  let def = match @fsm.parse_jsonld_gen(toml_text) {
    Ok(def) => def
    Err(msg) => {
      println("jsonld_gen: parse 拒绝：\{msg}")
      return
    }
  }
  match @fsm.validate_jsonld_gen(def) {
    Ok(_) => ()
    Err(msg) => {
      println("jsonld_gen: validate 拒绝：\{msg}")
      return
    }
  }
  let code = @fsm.emit_jsonld_skeleton(def)
  @fs.write_file("./src/jsonld/gen.mbt", @utf8.encode(code))
  println(
    "jsonld_gen: 已生成 src/jsonld/gen.mbt（steps \{def.steps.length()} / keywords \{def.keyword_dispatch.length()} / iri_rules \{def.iri_rules.length()}）",
  )
}
