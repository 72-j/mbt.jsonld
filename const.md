# JSON-LD 子项目 · const.md（红线）

## 0 定位
本子项目是 MoonTTL 的第四个能力面（前三个：N-Quads/N-Triples、TriG/Turtle、N3）。
但它**不是第四方言**——计算模型不同（树递归 + 算法，非词法状态机）。

## 1 架构红线
- **不升级 trig_fsm_gen**。jsonld_gen 是独立程序。
- **不叫 "TOML 3.0"**。JSON-LD 的 TOML 是独立 schema，与 FSM TOML 并列。
- **不共享框架，只共享库**（TOML 读、代码 emit、测试 harness）。
- **不硬套 FSM 形状**：TrigEvent/TrigState/step()/slot_stack 一律不搬。
- **不把递归策略塞进表**：能机械枚举的进表，不能的留手写。

## 2 三层职责红线
- **gen 产调度骨架**（从 TOML 的步骤表/分派表/IRI 规则表）。
- **手写产递归策略**（expansion 递归、@list/@nest/@included、toRDF 图构造）。
- **运行时解 JSON**（用 MoonBit 现成 JSON 解析器）。
- gen 不碰 JSON 文本；gen 不产递归策略。

## 3 对账红线（承袭世界宪法 §6）
- 骨架 vs 手写：**接口一致 + 步骤覆盖 + 值级对拍**，三者缺一不可。
- 未解释缺口 = 0，不是债务清零（缺口有解释即合格）。
- 复核面：JSON-LD 一致性面（照 review-surface-template 六步走）。

## 4 门红线
- 官方 json-ld-api toRDF 套件：全通过，缺口逐条有解释。
- 覆盖率棘轮：新包独立基线，只升不降（同笔跟升/跟降 + 沿革）。
- 值级对拍：expansion 后节点对象图、toRDF 后四元组，逐值对拍。
- 冷缓存复测 + 按 target（wasm/native）跑——门绿必须注明这两条。

## 5 禁止事项
- 禁止为复用 FSM 链而硬套表源（"两头都不像"）。
- 禁止把"搜索框架"的形状套到 JSON-LD 上（JSON-LD 无搜索）。
- 禁止为性能追 100% 覆盖率而造无断言测试。
- 禁止"顺手清"——一笔一账，独立役独立门况。