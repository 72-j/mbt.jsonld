///|
/// 黄金门：重生成 ≡ 入库 gen.mbt（逐字节）。
/// 生成物禁手写（世界宪法 §4.1）；再生通道 = 改 jsonld_gen.toml → moon run src/jsonld/cmd。
/// 对拍口径：parse + validate 全过后，emit_jsonld_skeleton 产出与入库件逐字节相等。
async test "gen golden gate: regenerated skeleton equals committed gen.mbt" {
  let toml_text = @utf8.decode(
    @fs.read_file("./src/jsonld/jsonld_gen.toml").binary(),
  )
  let def = match @fsm.parse_jsonld_gen(toml_text) {
    Ok(def) => def
    Err(msg) => fail("parse rejected: \{msg}")
  }
  match @fsm.validate_jsonld_gen(def) {
    Ok(_) => ()
    Err(msg) => fail("validate rejected: \{msg}")
  }
  let regenerated = @fsm.emit_jsonld_skeleton(def)
  let committed = @utf8.decode(@fs.read_file("./src/jsonld/gen.mbt").binary())
  assert_eq(regenerated, committed)
}
