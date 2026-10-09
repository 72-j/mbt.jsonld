# jsonld · 复核卷（review）

定位：本卷是 jsonld 子项目的**复核面**落点（复核表指引 + 缺口解释表）。
口径：`bangto/world/review-surface-template.meta.md`（六步法 + 四件 + 覆盖边界）
与 `bangto/world/const.md` §6.5（复核面七条）；本地三件套纪律见 `const.md` §6.4。
权威实例（先例）：`moonttl/suite-review.txt` + `moonttl/review.md` §1.1/§1.2。

## 1.1 复核表指引（套件面）

- **被复核面**：JSON-LD 官方套件面——`expand / toRdf / flatten / compact / frame /
  fromRdf / html / canon` 八个 manifest 驱动 harness（1437 条目 + compact 1 例留册）。
- **自报行来源**：`moon test` 的
  `[<面>] entries=N plain=N deferred=N` 行（8 个 harness 的 `println` 自报，
  **与 pin 断言同处**——改自报格式或数字即 `moon test` 红）。
- **复核表**：`suite-review.txt`（**生成物，勿手改**；同文件头含整段可复现命令）。
- **复现命令**（与表头一字不差）：

  ```sh
  cd jsonld
  { cat suite-review.header.txt
    moon test 2>&1 \
      | grep -oE '^\[[a-zA-Z]+\] entries=[0-9]+ plain=[0-9]+ deferred=[0-9]+' | sort -u
  } > suite-review.txt
  ```

  **两判据分开核**（`const.md` §6.4「复核表两判据」）：

  ```sh
  # ① 幂等（同命令连跑两次一致；防抖动）
  { cat suite-review.header.txt
    moon test 2>&1 \
      | grep -oE '^\[[a-zA-Z]+\] entries=[0-9]+ plain=[0-9]+ deferred=[0-9]+' | sort -u
  } > /tmp/sr-a.txt
  # …同命令再来一次 → /tmp/sr-b.txt
  diff /tmp/sr-a.txt /tmp/sr-b.txt        # 空 = 幂等（2026-10-03 实证空）

  # ② 可复现（复跑 vs 入库表一致；防漂移）
  diff /tmp/sr-a.txt suite-review.txt   # 空 = 可复现（同笔入库即此表）
  ```
- **覆盖边界**：见表头"覆盖边界"节（不覆盖 IR/产物面、覆盖率面、语义内部面、性能面）。
  覆盖率面已另立独立基线：`coverage-baseline.txt` 棘轮 ≤ 235（役C5 换带，
  2026-10-09；沿革 608 役65 立阈 → C1–C3 战役 689→237 活线清零后锁到实测 →
  役P1 码变 −2，C5 复测 235 同笔换带；只降不升）——复核表不含它，两账各管一面。

## 1.2 缺口解释表（套件面）

类别词表：`[设计]`（有意不做/规范允许取舍）/ `[立案]`（已立案待做，附重评估条件）/
`[未闭]`（应做未做，事故）。

| # | 缺口 | 类别 | 理由 | 重评估条件 | 台账落点 |
|---|---|---|---|---|---|
| 1 | `compact #t0038` "Index map round-tripping"（JSON-LD 1.0 复杂往返例，Drupal 案）未入 plain（compact 面 = 246 条 / plain 245 / deferred 1） | `[设计]` | **版次越界排除**（非缺口、非分叉）：specVersion = json-ld-1.0——其 expected（`title:/value`）是 **1.0 压缩算法遗留形态**，已被 JSON-LD 1.0 勘误改判；1.1 API §6.2 IRI Compaction 要求候选 term 具 **true prefix flag**（map 形缺省 false），故 1.1 处理器（含 1.0 processingMode）**如实产全 IRI 形态**（权威 oracle = #tp001，与 #t0038 同以 processingMode 1.0 运行）。参考实现 jsonld.js 对 specVersion=1.0 的 compact 例**整体跳过**（`tests/test.js` skip 表）。实测：放开 1.0 前缀资格 → #tp001 转红。证据三件见 `spec.md` §8.91.1 | 若另立 1.0 引擎一致性口径时（1.1 口径下不重估） | `spec.md` §8.91.1（新裁定）+ 同形异判表「版次越界族」；`todo.md` 役63 |

**其余七面零缺口**（expand 385/385、toRdf 467/467、flatten 58/58、frame 92/92、
fromRdf 54/54、html 50/50、canon 86/86——全 plain、零 deferred；由各 harness 的 pin
断言自证，见复核表）。

## 1.3 特性面余量（非套件面；2026-10-06 立案）

本节记**特性面**余量——不属于八面套件条目，与 §1.2 分账。

- **Streaming（json-ld11-streaming 流式文档形）**——类别 `[立案]`（**不排期**；
  与 framing / canonicalization 同族：独立规范，触发即成战线）。
  - **现状**：无实现。役65 定位 = 六算法 + RDFC-1.0 + JCS + HTML（`spec.md` §9），
    语料圈三套件无 Streaming 面（无门可守）。
  - **架构异构**：现实现 = 树递归纯函数（ADR-JL-4，`JsonValue` 全量内存）；
    流式 = 事件驱动增量管线（边解析边发事件、`@context` 前置约束）——
    换骨架，非加函数。
  - **触发条件（二选一即重估立案）**：① 语料圈出现 json-ld11-streaming
    官方套件（可立门）；② 消费端出现真实流式需求（用例驱动）。
  - 台账落点：`spec.md` §9（定位裁定）+ 本节。

## 1.4 评审役（2026-10-09；用户立项，四面全打）

立项三钉：**范围钉** = 四面全打，不查代码质量/性能/覆盖率复测（只核账面互指）；
**判据钉** = 每面判据 + 红线（数字不一致/锚漂移/条件失效即红，红即停即报）；
**产出钉** = 本节。时间盒本日；独立性 = 结论唯命令输出/自报行，本会话经手项
（b313589 清账 / 8846ffe 换带）不豁免同过门。

### 面1 账实相符面 —— 绿（finding 1 顺手修已落）

- 五账互指逐项核：suite **1438 = plain 1437 + deferred 1**（suite-review 自报行
  ↔ CHANGELOG ↔ consistency-baseline ↔ todo 状态表 ↔ 本卷 §1.2）✓；
  **852 = expand 385 + toRdf 467** ✓；六面 58/245+1/92/54/50/86 ✓；
  覆盖率 **235** 四处同笔（coverage-baseline 头 / spec §9.4 / 本卷 §1.1 /
  consistency-baseline 注记）✓；perf 判据带与批7 读数同笔 ✓。
- **finding 1（顺手修）**：`perf-baseline.txt` 头部状态行滞留「只测不优/优化前
  快照」口径，与卷尾批7 读数自相矛盾 → 同笔改「役P1 收官」态。
- 注记（非红）：CHANGELOG 覆盖率行 = 0.1.0 时点快照（608/606）——发版历史
  不动，下版条目随 235 更新。

### 面2 API 承诺面 —— 绿（finding 2/3/4 均非红）

- 17 pub fn 全数在册、CHANGELOG 所列 API 全存在 ✓；`JsonLdError` 九变体 ✓；
  spec 侧 API 承诺（html_script_source / expand_document / json_canonical /
  load_context 等）逐一对 `.mbti` 存在 ✓。
- **finding 2**：`jsonld_keyword_route`（单数；9cbe6b9 init 既有）0.1.0
  CHANGELOG 未列。
- **finding 3**：CHANGELOG「全量选项面」列 11/12——`expand_context : JsonValue?`
  （init 既有）漏列。
- **finding 4（下版必记）**：役P1 后 `.mbti` 可见面漂移（批3 ActiveContext
  +3 mut 字段等）——0.1.0 后变化，下版 CHANGELOG「变更」节须收。

### 面3 spec ↔ 码面 —— 绿（六案抽核全中；finding 5 口径注记已落）

- ContextOverflow 深度限 32（REC 4.1.2）：`types.mbt:11` +
  `context.mbt:118`（CONTEXT_CHAIN_LIMIT = 32）+ `expand_standard.mbt:3471`
  发射点 ✓。
- load_context_document 钩子单点：`expand_standard.mbt:3295` ✓。
- compact #t0038 版次越界 + #tp001 权威 oracle：`suite_compact_test.mbt:138`
  ✓。
- RDFC-1.0 route A + suite git anchor：`canon_rdfc10.mbt:2`（双向锚）✓。
- fromRDF §8.130/§8.131 钉：`from_rdf.mbt:2`（双向锚）✓。
- 壬子批 #t0034/#t0114 + merge_property_values 槽位语义：
  `expand_standard.mbt:822-824/1248-1252` ✓。
- **finding 5（口径注记，非红）**：b313589 清账位移（expand 净 −15 /
  engine −4 / canon −5 / from_rdf −2，非均匀）后，coverage-baseline /
  根 AGENTS §六 / todo 册上行号锚 = 位移前历史口径——六族论证系结构性论证
  不依赖行号复现，按日期锚定维持；口径行已加 coverage-baseline 头部。

### 面4 圈外面 —— 绿（三案重评估条件全未触发）

- remote-doc 18 例：定位裁定（通用库无内置网络 I/O，`load_context` 注入）
  仍成立；CHANGELOG 设计边界 + spec §8.39 表格在册 ✓。
- Streaming [立案]：触发①官方套件未出现（.rdf-tests 仅 api/framing/canon
  三套）②消费端需求无案 → 维持不排期 ✓。
- compact #t0038 [设计]：重评估条件（另立 1.0 引擎一致性口径）未触发 ✓。

### 终判

四面全绿；**红 0**；finding 5 条（1 顺手修已落 + 1 口径注记已落 +
2 CHANGELOG 漏登记 + 1 下版必记）。无未闭事故，发布门面维持全绿。

## 1.5 发布合规检查（2026-10-09；评审役后独立终检）

八道门：①仓态（两仓净 + HEAD==origin + gitlink 同步）②全门（fmt --check /
.mbti 零差 / suite + deny-warn）③语料锁版 ④主仓黄金门（skelgen/jsonld_gen
1/1）⑤版本面（moon.mod 0.1.0 + CLI 冒烟）⑥评审役账在册 ⑦const.md §6 红线册
⑧八面自报行一字不动——七绿一红，红已处置。

- **红 R-1（已处置，b 路功能补齐）**：`json_canonical` 三处宣称 JCS（RFC 8785）
  （README / CHANGELOG / CLI help），实现实为对拍归一器（键序 `String::compare`
  假序、返 JsonValue、无 JCS 数词形/转义语义）；真 JCS 在 to_rdf.mbt J3.3
  （#tjs01~23 oracle）未暴露 pub。冒烟实证：CLI 出长度序 @id/ex:p/@context，
  JCS 应为码点序 @context/@id/ex:p。
  **处置落码**：`jcs_serialize` 晋 pub（to_rdf.mbt，nq_jcs 包装，.mbti +1）+
  CLI json-canonical 换线接真品（输出码点序实证 ✓）+ `json_canonical` 文档
  重定位（比对归一器，非 JCS）+ README 四处/quickstart ⑦节同步 + 钉测 +1
  （键序反例即红；suite 534→**535**）。
- **finding 6（已修）**：语料锁版出生错配——`rdf-canon/manifest.csv` 自 J7
  入树未变而 SUMS 记数不符（同笔内 SUMS 先算 manifest 后改），SHA256SUMS
  同笔修锁（b30d…→7b83…），复验 **3068/3068 OK**。
- **finding 7（下版更正）**：CHANGELOG「2626 件」= J0 单套件旧口径，现行
  锁版实为 3068 件（三套件）。
- 终判：**八道全绿**；R-1 落码后 suite 535 + deny-warn + .mbti +1（预期）
  + CLI JCS 序实证 ✓——发布门面就绪。
