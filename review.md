# src/jsonld · 复核卷（review）

定位：本卷是 jsonld 子项目的**复核面**落点（复核表指引 + 缺口解释表）。
口径：`bangto/world/review-surface-template.meta.md`（六步法 + 四件 + 覆盖边界）
与 `bangto/world/const.md` §6.5（复核面七条）；本地三件套纪律见 `const.md` §6.4。
权威实例（先例）：`src/ttl/suite-review.txt` + `src/ttl/review.md` §1.1/§1.2。

## 1.1 复核表指引（套件面）

- **被复核面**：JSON-LD 官方套件面——`expand / toRdf / flatten / compact / frame /
  fromRdf / html / canon` 八个 manifest 驱动 harness（1437 条目 + compact 1 例留册）。
- **自报行来源**：`moon test src/jsonld` 的
  `[<面>] entries=N plain=N deferred=N` 行（8 个 harness 的 `println` 自报，
  **与 pin 断言同处**——改自报格式或数字即 `moon test` 红）。
- **复核表**：`src/jsonld/suite-review.txt`（**生成物，勿手改**；同文件头含整段可复现命令）。
- **复现命令**（与表头一字不差）：

  ```sh
  cd /home/thy/moonttl
  { cat src/jsonld/suite-review.header.txt
    moon test src/jsonld 2>&1 \
      | grep -oE '^\[[a-zA-Z]+\] entries=[0-9]+ plain=[0-9]+ deferred=[0-9]+' | sort -u
  } > src/jsonld/suite-review.txt
  ```

  **两判据分开核**（`const.md` §6.4「复核表两判据」）：

  ```sh
  # ① 幂等（同命令连跑两次一致；防抖动）
  { cat src/jsonld/suite-review.header.txt
    moon test src/jsonld 2>&1 \
      | grep -oE '^\[[a-zA-Z]+\] entries=[0-9]+ plain=[0-9]+ deferred=[0-9]+' | sort -u
  } > /tmp/sr-a.txt
  # …同命令再来一次 → /tmp/sr-b.txt
  diff /tmp/sr-a.txt /tmp/sr-b.txt        # 空 = 幂等（2026-10-03 实证空）

  # ② 可复现（复跑 vs 入库表一致；防漂移）
  diff /tmp/sr-a.txt src/jsonld/suite-review.txt   # 空 = 可复现（同笔入库即此表）
  ```
- **覆盖边界**：见表头"覆盖边界"节（不覆盖 IR/产物面、覆盖率面、语义内部面、性能面）。

## 1.2 缺口解释表（套件面）

类别词表：`[设计]`（有意不做/规范允许取舍）/ `[立案]`（已立案待做，附重评估条件）/
`[未闭]`（应做未做，事故）。

| # | 缺口 | 类别 | 理由 | 重评估条件 | 台账落点 |
|---|---|---|---|---|---|
| 1 | `compact #t0038` "Index map round-tripping"（JSON-LD 1.0 复杂往返例，Drupal 案）未迁 plain（compact 面 = 246 条 / plain 245 / deferred 1） | `[立案]` | 1.0 模式下 index map 的往返语义细节（1.0 无 `@index` 容器语义的一致性差异），需与「1.0 index map 裁量」一并定；**非**实现停滞（expand/toRdf 面同一语义已全绿） | 擂台口径涉及 JSON-LD 1.0 compact 往返时开；或 `t0038` 分叉裁量落笔时 | `todo.md` §J2（compact 面留册）；裁量结论入 `spec.md` §8（模式分叉节） |

**其余七面零缺口**（expand 385/385、toRdf 467/467、flatten 58/58、frame 92/92、
fromRdf 54/54、html 50/50、canon 86/86——全 plain、零 deferred；由各 harness 的 pin
断言自证，见复核表）。
