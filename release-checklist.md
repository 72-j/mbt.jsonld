# 发版清单（release checklist）— thy1016/jsonld 0.1.1

**状态（2026-10-09）：发版候选达成——发布合规八道门全绿（`review.md` §1.5）+
评审役四面全绿（§1.4）；发布路径裁 = 用户本机 `moon publish`（Claude 侧不执行，
moonttl 同款）；余项 = 用户择时发布。**

**发版判据不是"动作执行了"，是"第三方能按账复现出同一结论"。**
清单本身可复核：每项带判据与取证位置。

## 第一段：CI 确认（降级叙事）

| # | 项 | 判据 | 状态 / 取证 |
|---|---|---|---|
| 1 | 托管 CI | 有则推送即有 run；无则降级叙事写清 | ☑ **无托管 CI**（子仓无 workflows）——门 = 本地全绿 + 复核面矩阵（下方）人工复跑；perf P1「必先过」同为人工门口径（perf-baseline 批7 ②），两处口径一致 |

## 第二段：发版账收口

| # | 项 | 判据 | 状态 / 取证 |
|---|---|---|---|
| 2 | 发版清单 | 清单本身可复核（每项有判据） | ☑ 本文件 |
| 3 | 版本 bump 三处一致 | moon.mod = CHANGELOG = README 指针 | ☑ moon.mod `0.1.1`；☑ CHANGELOG `## 0.1.1（2026-10-09）`；☑ README L203「版本沿革见 CHANGELOG.md」（语义化引用，无内嵌版本号） |
| 4 | 对外变更日志 | 对外可读，区别内部 todo/review | ☑ CHANGELOG 0.1.1：新增 API / 修正 / 勘误（0.1.0 补遗四件）/ 测试与质量 四节 |
| 5 | README 能力面 | 引用同一数字源 | ☑ JCS 节指向 `jcs_serialize`（R-1 兑现）；套件计数引用 suite-review（1438） |
| 6 | 复核面收口 | 附复现命令 + 冷跑留证（矩阵见下） | ☑ 四账口径齐（§1.5 八道门取证） |
| 7 | 评审收口 | 无未闭红 | ☑ 评审役四面绿红 0（§1.4）+ 发布合规红 R-1 已处置（§1.5）；finding 7/下版项（CHANGELOG 件数等）已随 0.1.1 勘误节兑现 |

## 第三段：发版动作

| # | 项 | 判据 | 状态 / 取证 |
|---|---|---|---|
| 8 | 预检（用户本机） | 四门 verbatim：版本三处一致 grep 原样 ✓ · `moon check --deny-warn` ✓ · `moon fmt --check` ✓ · `moon publish --dry-run` 验收行 | ☑ **2026-10-09 过**——服务器验收行在册："Server status: 202 Accepted, detail: Dry run completed successfully. No changes were made. The dry-run was made for package thy1016/jsonld version 0.1.1."；尾行 `Error: \`moon publish\` failed` = 已勘 CLI 怪癖（202 尾步报失败），**认验收行不认退出码** |
| 9 | 注册表槽位 | 0.1.1 槽位空闲 | ☑ 2026-10-09 实查 `mooncakes.io/api/v0/search?kw=jsonld`：**thy1016/jsonld 不在册**（0.1.0 未 publish）——0.1.0/0.1.1 槽位均空闲 |
| 10 | 真发布（用户本机） | `moon publish` 成功判据 = **注册表回查**（非退出码）：`search?kw=thy1016` 出 thy1016/jsonld 0.1.1 | ☑ **2026-10-09 过**——注册表回查：`thy1016/jsonld 0.1.1 downloads: 1 yanked: False` 在册 |
| 11 | tag | 轻量 tag 钉发版笔 | ⬜ `v0.1.1` 钉 CHANGELOG/bump 笔；`v0.1.0` 回溯补钉 `67139a7`（发布前收口笔，moonttl 全版本有 tag 同款） |
| 12 | 两仓成对推送 | 子仓 → 主仓指针，先子后主 | ☑ 每笔已按序执行；tag 后再推一次即闭环 |

## 复核面矩阵（对外可复现形态；cwd = 子仓根）

| 面 | 表 | 口径 | 复现命令 | 冷跑留证（2026-10-09） |
|---|---|---|---|---|
| 套件自报行 | `suite-review.txt` | 默认档 | `{ cat suite-review.header.txt; moon test 2>&1 \| grep -oE '^\[[a-zA-Z]+\] entries=[0-9]+ plain=[0-9]+ deferred=[0-9]+' \| sort -u; } > /tmp/sr.txt && diff /tmp/sr.txt suite-review.txt` | 空 = 可复现 ✓（幂等双证 §1.1） |
| 覆盖率 | `coverage-baseline.txt` | 棘轮 ≤235 | `moon coverage clean && moon test --enable-coverage > /dev/null && moon coverage analyze -p thy1016/jsonld \| tail -1` | **235**（C5 换带，三连幂等）✓ |
| 性能回归门 | `perf-baseline.txt` | native · bench 十场景 | `moon run cmd/bench 2>/dev/null \| grep '^\[bench\]'` | 判据带 [158,165] / 回归 >10% 即红（役P1 收官读数在册） |
| 一致性 | `consistency-baseline.txt` | J0 852/852 | 同 suite（expand 385 + toRdf 467 子集） | 852/852 ✓ |
| 语料锁版 | `.rdf-tests/SHA256SUMS` | 3068 件 | `sha256sum -c .rdf-tests/SHA256SUMS` | **3068/3068 OK** ✓ |
| 黄金门 | 主仓 `skelgen/jsonld_gen` | 三表→gen.mbt 逐字节 | 主仓根 `moon test skelgen/jsonld_gen` | 1/1 ✓ |
