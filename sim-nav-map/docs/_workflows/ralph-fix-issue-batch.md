# Ralph Workflow: Fix Issue Batch

> **用法**
>
> ```
> /ralph-loop:ralph-loop @addons/sim-nav-map/docs/_workflows/ralph-fix-issue-batch.md \
>   --completion-promise "BATCH_COMPLETE" \
>   --max-iterations 60
> ```
>
> 启动前先按 [启动准备](#启动准备) 段把 queue 写进 state 文件。

## 目标

按你给的顺序串行修 `addons/sim-nav-map/docs/issues/` 里的多个 issue。每个 issue 走对应的状态机分支（A/B/C/D/E）跑到完成，自动写 Resolution / 更新 BASELINE / 注册 smoke / submodule commit + 主仓 bump pointer。所有 issue 走完发 `<promise>BATCH_COMPLETE</promise>`。

## 适用 / 不适用

**适用**：
- 已经在 `addons/sim-nav-map/docs/issues/` 里的 issue（`<id>.md` 文件已存在，模板五段齐：Symptoms / Root cause / Proposed fix / Repro / Verify）
- 修复改动**全部在 `addons/sim-nav-map/` submodule 内**（不需要改 `scripts/` / `scenes/` / 主仓其他文件）

**不适用**：
- PROCESS-001 本身（无代码任务，由 D 分支顺带回填 worked examples）
- 还没建 issue 文件的新 bug（先建 issue 再 ralph）
- 改动溢出到主仓代码的 issue（每轮自检；发现立刻 abort 该 issue）

## State 文件

路径：`addons/sim-nav-map/docs/_workflows/.ralph-state-fix-issue-batch.md`

**首次启动前**人类创建并填好 `queue`。**每轮 ralph 必读必写**。`.gitignore` 已忽略（**不**进 submodule 历史）。

格式：

```markdown
# Ralph Fix Issue Batch State

started_at: 2026-05-07T15:00:00
last_iteration_at: 2026-05-07T15:23:11
iteration_count: 12

## queue
- CORE-001
- CORE-005
- CORE-007

## current
id: CORE-005
branch: A
sub_step: 3
sub_iteration: 1
last_smoke_result: PASS

## done
- CORE-001 (resolved 2026-05-07T15:18:00, submodule_commit abc1234, mainrepo_commit def5678)

## aborted
(empty)

## notes
- (free-form notes)
```

字段：
- `queue` — 待做 ID 顺序列表，ralph 从顶部弹
- `current` — 当前正处理的 issue（id / branch / sub_step / sub_iteration / last_smoke_result）
- `done` — 已完成（按完成顺序追加，含两个 commit hash）
- `aborted` — 因故放弃（含 reason）
- `notes` — 自由备注

## Per-iteration 流程

**重要原则**：

1. **信任文件，不信任 head**。ralph 是同一 conversation 多轮（`--continue`），head 会累积上下文。每轮第一步从 state 文件 / issue 文件 / `git status` 重建当前状态。head 里的判断与文件冲突 → 以文件为准。
2. **sub_step 是断点 marker，不是 throttle**。每轮做尽可能多 sub_step，直到 issue 完成、abort、或确实需要终止本轮（连续多次 fail）。**一轮做完一整个 issue（13 个 sub_step）是常态**。

每轮 ralph 按下面顺序执行：

### Step 0: 读 state

读 state 文件。不存在 → 输出 `ABORT: state file missing — please initialize before starting ralph.` 然后 `<promise>BATCH_ABORTED: state missing</promise>`。

### Step 1: 决定本轮做什么

- `current` 不空 → 继续这个 issue 的 sub_step
- `current` 空且 `queue` 不空 → 从 queue 顶部弹一个 ID 设成 `current`，进 Step 2 选 branch
- `current` 空且 `queue` 空 → 进 Step 99（终止）

### Step 2: 选 branch（仅当刚弹新 issue）

读 issue 文件 `addons/sim-nav-map/docs/issues/<id>.md`，按下表选 branch 写回 state：

| 条件 | branch | 服务 |
|---|---|---|
| Repro = `smoke (FAIL)` 且 Layer = core | A | CORE-001/003/004/005/006/007 |
| Repro = `text` + Manual recipe 提到 "instrumentation pending" | B | CORE-008/009 |
| Repro = `text` + Manual recipe 提到 "adversarial scenario pending" | C | CORE-002 |
| Layer = lab + Repro = `smoke (FAIL)` | D | LAB-001/002/003 |
| Repro = `smoke (PASS lock-in)` | E | LAB-004/005 |

### Step 3: 执行 branch 子流程

#### Branch A: Direct fix

服务：CORE-001/003/004/005/006/007

sub_steps：

1. **读 issue 完整文件 + 0 A.D. reference**（issue 文件 0 A.D. reference 段列了路径）。0 A.D. 是 ground truth，不参考已删除的 AI summary notes。
2. **应用 Proposed fix** —— 只改 issue Proposed fix 段 + Verify 段提到的文件。
3. **跑 repro smoke**：`godot --headless --path . <repro tscn 路径> > /tmp/repro.txt 2>&1`
   - 未 PASS → 回 sub_step 2（同 sub_iteration，循环改）
4. **跑 simnav/smoke + zeroadlab/smoke 全绿**：`./tools/run_tests.ps1 simnav/smoke rtslab/smoke`
   - 有 FAIL → `git -C addons/sim-nav-map checkout .`（**回退本轮全部代码改动**），state.notes 记 "regression in <smoke>"，sub_iteration += 1，回 sub_step 2
5. **更新 issue 文件**：
   - Status: `open` → `resolved`
   - 加 Resolution 段（commit hash 先写 `<TBD>`，最后回填）：
     ```markdown
     ## Resolution
     - submodule commit: <TBD>
     - smoke: <repro tscn 路径>
     - 0 A.D. files checked: <从 issue 0 A.D. reference 段抄>
     - baseline impact: <相关 BASELINE 行/数字 / "none">
     ```
6. **注册 smoke 到 `addons/sim-nav-map/tests/test_groups.json`**：repro tscn 加进 `simnav/smoke` 组
7. **更新 `addons/sim-nav-map/docs/issues/BASELINE.md`**：
   - "Known correctness limits" 段：删该 issue 行（如有）
   - "Lab metrics" 表：core issue 通常不动 lab 数字，跳过
8. **更新 `addons/sim-nav-map/docs/issues/README.md` index**：该行 `Status: open` → `resolved`，Repro 列 `smoke (FAIL)` → `smoke (PASS)`
9. **更新 `addons/sim-nav-map/docs/public-api.md`**（仅当 issue 加新 public API：CORE-004 / CORE-006）：加 method 签名 + 行为说明
10. **submodule commit**：
    ```bash
    git -C addons/sim-nav-map status                       # 检查文件清单
    git -C addons/sim-nav-map add <精确文件列表>           # 不用 add . / -A
    git -C addons/sim-nav-map commit -m "fix(sim-nav-map): resolve <ID> — <一行摘要>"
    git -C addons/sim-nav-map rev-parse HEAD               # 拿 hash
    ```
11. **回填 commit hash**：用 Edit 把 issue 文件 Resolution 段 `<TBD>` 替换成实际 hash；`git -C addons/sim-nav-map add <issue文件>` + `git -C addons/sim-nav-map commit --amend --no-edit`
12. **主仓 bump pointer**：
    ```bash
    git add addons/sim-nav-map
    git commit -m "chore: bump sim-nav-map (resolve <ID>)"
    git rev-parse HEAD                                     # 拿 hash
    ```
13. **更新 state**：`done` 追加 `<ID>` (含两个 commit hash)；`current` 清空；进 Step 0 跑下一轮

**A 分支单 issue 上限**：sub_iteration ≥ 5 → abort（reason: "5 iterations no green smoke"）。

#### Branch B: Add instrumentation then fix

服务：CORE-008（A* expansion counter）/ CORE-009（heap per-op timing）

sub_steps：

1. **读 issue + 0 A.D. reference**
2. **加 instrumentation**（按 issue Smoke deliverable 段）：
   - CORE-008: 在 `sim_nav_vertex_pathfinder.gd` 加 A* 节点 expansion counter，暴露给 result metadata 或 debug-only export
   - CORE-009: 在 `sim_nav_pathfinder_heap.gd` 加 per-op (insert/pop) 计时，暴露给 debug
3. **写新 smoke**（按 issue Smoke deliverable 段建 `tests/repro/repro_<id>_*.gd` + tscn）
4. **跑新 smoke 必须 FAIL**（instrumentation 加完但 fix 还没做，理应 FAIL）—— 未 FAIL → 改 smoke 直到 FAIL（这是 ralph 探索"失败信号成立"）
5. **应用 Proposed fix**
6. **跑新 smoke 必须 PASS** —— 未 PASS → 回 sub_step 5
7. 之后走 Branch A sub_step 4-13（simnav/smoke + zeroadlab/smoke 全绿 / 更新 issue / commit / bump）

**B 分支单 issue 上限**：sub_iteration ≥ 8。

#### Branch C: Find adversarial scenario then fix

服务：CORE-002

sub_steps：

1. **读 issue + 0 A.D. reference**（CheckLineMovement 在 0 A.D. Pathfinding.cpp）
2. **跑 lab 找候选 waypoint pair**：跑 `./tools/run_tests.ps1 rtslab/smoke`，扫日志找 long-path refined waypoint pair；候选 = 看起来 graze 角的
3. **Bresenham 验证候选**：对每个候选独立用 Bresenham iterator 走 navcell，断言"是否有 blocked cell 被穿过"
4. **找到对抗场景** → 提取最小复现：static OBB 配置 + start/goal + clearance class
5. **写 FAIL smoke** `tests/repro/repro_core_002_long_path_los_sampling.gd` + tscn
6. **跑必须 FAIL**
7. 之后走 Branch A sub_step 2-13（应用 Proposed fix / 后续）

**C 分支单 issue 上限**：sub_iteration ≥ 6 → abort（reason: "no adversarial scenario found"）。

#### Branch D: Triage then fix（PROCESS-001）

服务：LAB-001/002/003

sub_steps：

1. **读 issue + PROCESS-001**
2. **提取 lab 失败场景最小 setup**（从 issue Repro 段抠 setup_default + tick + 触发条件，如 "step 20 后 drop static obstacle on blue_0"）
3. **写 core-only 等价 smoke** `addons/sim-nav-map/tests/repro/repro_<lab-id>_core_only.gd`：跑同样的 path query / passability / timing 但**不经过 lab movement / separation 层**
4. **跑 core-only smoke**：
   - **core 也复现 / 也慢** → bug 在 core；issue 文件加 `## Triaged: core` 段（含 core-only smoke 路径 + 决策原因）→ 后续按 A 分支步骤改 core
   - **core OK** → bug 在 lab；issue 文件加 `## Triaged: lab` 段 → 改 `examples/0ad-rts-pathfinding-lab/` 内文件
5. **应用对应层的 fix**
6. **跑 lab repro smoke 必须 PASS**
7. **跑 simnav/smoke + zeroadlab/smoke 全绿**
8. **回填 PROCESS-001 worked example**：在 `process-001-core-lab-proof-protocol.md` `## Worked examples` 段加一行（含 lab-id / core-only smoke 路径 / 决策结果）
9. 之后走 Branch A sub_step 5-13（更新 issue / BASELINE / submodule commit / 主仓 bump）

**D 分支单 issue 上限**：sub_iteration ≥ 8。

#### Branch E: Lock-in completion

服务：LAB-004 / LAB-005

**LAB-004** sub_steps：
1. 在 `examples/0ad-rts-pathfinding-lab/` 找当前 `ARRIVE_MAX_OVERLAP` / arrival radius / formation slot spacing 写法分散的所有点
2. 抽统一常量：`ACTIVE_*` / `IDLE_*` + overlap matrix 文档（写进 issue 文件 / `examples/0ad-rts-pathfinding-lab/README.md` 看哪个合适）
3. 跑 simnav/smoke + zeroadlab/smoke 全绿（重构无回归）
4. 写 adversarial smoke `repro_lab_004b_*.gd`（按 issue "Adversarial scenario still pending" 描述：rapid obstacle edits during arrival, edge-adjacent target, blocker-near-target packing），断言 overlap matrix 阈值
5. 跑 adversarial smoke 必须 PASS（lock-in 性质：现有行为对的，smoke 锁定）
6. 之后走 Branch A sub_step 5-13

**LAB-005** sub_steps：
1. 给 `unit.target` / `unit.path_target` 加 docstring（说明语义 + 引用 LAB-005 ID）
2. Audit `examples/0ad-rts-pathfinding-lab/frontend/` 命令 marker 引用的字段（确认引用 `target` 不是 `path_target`）
3. 跑 simnav/smoke + zeroadlab/smoke 全绿
4. 之后走 Branch A sub_step 5-13

**E 分支单 issue 上限**：sub_iteration ≥ 5。

### Step 99: 终止

queue 空且 current 空 → 输出：

```
<promise>BATCH_COMPLETE: status=done, done=<count_done>, aborted=<count_aborted>, total=<count_started></promise>

Done:
- <列表，含 commit hashes>

Aborted:
- <列表，含 reason>
```

## Scope 约束

### DO

- 一轮只摸 1 个 issue 的代码（+ 该 issue 的 cross-ref 文件：BASELINE / test_groups.json / public-api.md / README index）
- 每修完一个 issue 立即 **2 个独立 commit**（submodule + 主仓 bump）
- `git -C addons/sim-nav-map status` 在 commit 前看清楚文件清单
- 用 `git -C addons/sim-nav-map add <精确文件>`，**不用** `git add .` / `git add -A`
- 跑 `simnav/smoke` + `rtslab/smoke` 全绿才算 issue done
- 改完每个 issue 也更新对应行 README index

### DO NOT

- 一轮里同时改两个 issue 的相关代码
- 跳过 smoke run
- 用 `git add .` / `git add -A`（违反主仓 memory 里"只 commit 自己改的文件"）
- 一个 commit 服务多个 issue
- 改 PROCESS-001 文件本身（除 D 分支 sub_step 8 的 worked example 回填）
- 改 `scripts/` / `scenes/` / 主仓任何代码 —— 发现需要主仓改动 → 立刻 abort 该 issue（reason: "needs main-repo change, out of scope"）
- 跨 issue 复制粘贴未审过的代码

## 启动准备

人类（你）做一次：

1. **创建 state 文件** `addons/sim-nav-map/docs/_workflows/.ralph-state-fix-issue-batch.md`，把 queue 按依赖顺序填好（见下文 [推荐 queue 顺序](#推荐-queue-顺序)）
2. **加 .gitignore**：在 `addons/sim-nav-map/.gitignore` 末尾加 `docs/_workflows/.ralph-state-*.md`（state 文件不进 submodule 历史）
3. **启动 ralph**：
   ```
   /ralph-loop:ralph-loop @addons/sim-nav-map/docs/_workflows/ralph-fix-issue-batch.md \
     --completion-promise "BATCH_COMPLETE" \
     --max-iterations 60
   ```

`--max-iterations 60` 估算：14 个 issue × 平均 4 sub_iteration ≈ 56。少跑想停给 `--max-iterations 30` 做小批量。

## 推荐 queue 顺序

（按"依赖 + 风险递增"，可以分批跑，不必一次 14 个）

**第一波（A 分支，无依赖，启用 ralph 的 sanity check）**：
1. CORE-001 (P0, 单文件改 vertex outset)
2. CORE-006 (P2, 加 setter API)

**第二波（A 分支，CORE-005 → CORE-007 是硬依赖）**：

3. CORE-005 (P1, 加 CLEARANCE_EXTENSION_RADIUS)
4. CORE-007 (P3, AABB rasterize)

**第三波（A 分支，相对独立）**：

5. CORE-003 (P0, hierarchical region 遍历)
6. CORE-004 (P1, set_bounds API)

**第四波（B 分支，instrumentation 类）**：

7. CORE-008 (P3, expansion counter)
8. CORE-009 (P3, heap timing)

**第五波（C 分支，找对抗场景）**：

9. CORE-002 (P0, LOS Bresenham)

**第六波（D 分支，PROCESS-001 流程）**：

10. LAB-003 (P1, 41.5px 跳跃 — 确定性最强先做)
11. LAB-001 (P1, avg step)
12. LAB-002 (P1, stress 长帧)

**第七波（E 分支，lock-in 补完）**：

13. LAB-004 (P2, overlap matrix)
14. LAB-005 (P2, target separation docstring)

PROCESS-001 在 LAB-* 的 D 分支 sub_step 8 自动回填 worked examples，**不在 queue 里独立处理**。

## 中断恢复 / 取消 / 改 workflow

### 两套 state 文件并存（不要混淆）

| | 路径 | 谁在管 | 内容 |
|---|---|---|---|
| **ralph 内部 state** | `.claude/.ralph-loop.local.md` | ralph-loop 插件自己 | iteration count、loop 是否活跃 |
| **workflow 业务 state** | `addons/sim-nav-map/docs/_workflows/.ralph-state-fix-issue-batch.md` | 本 workflow（ralph 每轮读写） | queue / current / done / aborted |

### 取消正在跑的 ralph

```
/ralph-loop:cancel-ralph
```

只删 ralph 内部 state，**不动 workflow 业务 state**。下次再启动 `/ralph-loop:ralph-loop @<本文件>` → 第一轮读 workflow 业务 state → 从 `current` 续。

### 修改本 workflow 文档需要重启 ralph

ralph 启动时用 `@<file>` 引用通常会**展开为快照**——启动后改文档不生效。要改流程：先 `/ralph-loop:cancel-ralph` → 改 workflow → 再启动。

### ralph 中断后再启动续接

state 文件还在 → 第一轮读 state → 从 `current` 续：

- **commit 之前中断**：`git -C addons/sim-nav-map status` 显示未提交工作树改动 → 续做
- **submodule commit 之后、主仓 bump 之前中断**：第一轮检测到 submodule HEAD ≠ 主仓 pointer → 立刻补主仓 bump commit，再继续 queue
- **写 issue 文件之间中断**：以 issue 文件实际状态为准（Status / Resolution 段）

## 失败处理

- **single-iteration 卡住**：smoke 跑超 30s → kill（"godot smoke 30s 没返回基本就是有问题"——主仓 CLAUDE.md headless smoke 段），写 reason 到 state.notes
- **single issue abort**：sub_iteration 超分支上限 → `aborted` 段记录，`current` 清空，继续 queue 下一个
- **batch abort**：连续 3 个 issue abort → 发 `<promise>BATCH_COMPLETE: status=aborted, reason="3 consecutive issue aborts", done=<N>, aborted=<K>, total=<M></promise>` —— 用同一 `BATCH_COMPLETE` 前缀触发 `--completion-promise` 停 loop，正常 vs aborted 看 promise 文本里的 `status=` 字段

## 附录：依赖关系

从 issue 文件直接抠出的客观依赖（不是我编的，对应的行号都在）：

```
CORE-005 ─→ CORE-007  (CORE-007 issue 第 49 行: "Lock CORE-005 first or design the AABB expansion to fold in the extension radius cleanly")
CORE-001 ─→ CORE-008  (同文件 sim_nav_vertex_pathfinder.gd, 串行避免 rebase 冲突)
LAB-001 ─→ CORE-009   (CORE-009 issue 第 78 行: "only worth doing if measurement says heap matters at lab scale")
LAB-001/002/003 ─→ PROCESS-001 worked examples 回填（D 分支 sub_step 8）
```

非依赖但同表面（建议串行避免冲突）：
- CORE-004 / CORE-005 / CORE-006 / CORE-007 都摸 obstruction manager 或 sim_nav_map.gd

## 修订历史

- 2026-05-07: 初版
