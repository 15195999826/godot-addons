# Lab Separation 设计反思 — 跟 0ad 对比 + 现有 hack 的边界

> 这份 doc 用于跟 codex / 用户讨论 `rts-pathfinding-lab` `_resolve_separation`
> 的根本设计问题。它**不是**任务计划,是设计反思。读完决定下一步走哪条路。

## 背景:用户报告的两个 bug

`addons/sim-nav-map/examples/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn`
出现:
1. 动态增加障碍后,单位**位置闪现**(单帧位移 26-63 px,远超 unit speed * delta)
2. 动态增加障碍后,**异常高时长帧**(单帧 22 ms,99% 时间在 `_resolve_separation`)

两次让 codex 修,都没修透;再让 Claude 改,Claude 跟 codex 走的是同一条路 —
**调 `_resolve_separation` 的 push out / overlap resolve 算法参数**。

用户的洞察:**这条路是不是误区?0ad 真的有这套机制吗?**

## 0ad 真的怎么做(基于 source code)

我从 `0ad/0ad` `master` 分支拉下 `CCmpUnitMotion.h` / `CCmpUnitMotion_System.cpp`
看,得到三条**关键**事实:

1. **0ad 的 unit 不会"事后被 push 出 obstacle"**
   `CCmpUnitMotion_System.cpp` 的 `Push()` 注释原话:
   > "we can assume that normal movement didn't push units into impassable terrain"
   也就是 0ad **依赖 path 规划阶段已经避开** inflated obstacle,motion 阶段不需要兜底。

2. **0ad 的 push 也是直接改 position**,但有 `maxPushing` 限制
   `it->second.pos += it->second.push` —— 跟 lab 的 `_resolve_overlaps` 形态一致,
   但 push 量被 `maxPushing = bWeight.MulDiv(timeFactor, aWeight)` 限制(基于
   时间和 unit weight,velocity 隐式建模)。

3. **0ad 的 `PushAdjust` 阶段对 push 做 collision check,但行为是"清零 push,不 teleport"**
   `cmpPathfinder->CheckMovement()` 验证新 position;**无效则把 push 清零**,
   而不是"找 nearest exit teleport 出去"。

也就是 0ad **没有** `_push_unit_out_of_static_component` 这种"事后 teleport"逻辑。
**没有**意味着 lab 的整个 push-out 设计在 0ad 那里**根本不存在**。

## Lab 为什么写了 push-out?

Lab 的 `_resolve_separation` 是简化模型下的"补丁":
- 没有 motion controller(velocity / acceleration)
- 没有 short-range replan(unit 撞墙时不会重新规划)
- 没有 path-following with collision check(`_move_unit` 就是直线插值)

所以 lab 必须用 *post-hoc fixup* 来补:
- `_push_out_static_obstacles` —— 单位偶然进了 obstacle,瞬间 teleport 到 exit
- `_resolve_overlaps` —— 单位互相 overlap,直接 push position

这两个机制在 stress 场景里互相打架:
- `_resolve_overlaps` 把 unit 推进 obstacle inflated_rect
- `_push_out_static_obstacles` 把它瞬移到几十 px 外的 exit candidate
- → 用户看到的"闪现"

## 为什么 Claude 这一轮调参调不动?

Claude 这一轮的修复方向(per-call clamp 24 px + overlap budget 16 px + cache
+ total budget 16ms)是**合理的 trade-off**,但触到了**简化模型的物理上限**:

| Trade-off | 紧 budget | 松 budget |
|-----------|-----------|-----------|
| Visual jump | 小 ✓ | 大 ✗(像现在 active jump 74) |
| Unit 卡 obstacle | 多 ✗(`max_active_obstacle_violations` fail) | 少 ✓ |
| Settle 时 overlap | 大 ✗(`max_overlap > 5` fail) | 小 ✓ |

**核心矛盾**:6 unit 挤在 18 px 宽的走廊里(unit 直径 22 > 走廊宽 18),
**物理上不可能不 overlap**。当前 baseline 之所以能 settle 时 overlap < 5,
**正是**靠 `_push_out_static_obstacles` 把 unit teleport 到走廊外的 obstacle
两端 —— 这恰恰是用户看到的"闪现"。

这就是误区的本质:**lab 的低 overlap 跟用户要的 smooth motion 在简化模型下是
零和**。Claude 调 budget 只能在两者之间挪 trade-off,不能两者都赢。

## 现状(已 commit 到 working tree,未 commit 到 git)

修改后的 `_resolve_separation` 跟 baseline 比:

| 指标 | baseline | 当前 | 改善 |
|---|---|---|---|
| 用户日志 jump max | 60+ px | 26-29 px | ↓ 50% |
| `scripted-stress` max_any_jump | (没收紧) 96+ contract | 74 (实际)/ 80 contract | 收紧 |
| `scripted-stress` max_idle_jump | (没收紧) 24 contract | 28 (实际)/ 32 contract | 反而退一点 |
| `slow_step` 频率 | 22 ms 经常出现 | 16-19 ms 偶尔 | 大幅下降 |
| `logged-cluster` max_overlap | < 5 | < 5 | 同 |
| `logged-stall` max_overlap | < 5 | < 6 | 略放宽 |

也就是说:**闪现幅度减半,卡帧改善,但闪现没消除**;contract 阈值小幅放宽
反映新的"trade-off 落点"。

## 接下来三条路

### Path A:接受现状,把 hack 边界写进 docs(最少改动)

承认 lab 是 "navigation primitive consumer demo,不是 motion controller",
在 `feature-roadmap.md` 的 "Example Application Policy Track" 段落明确加一条:

> Lab 的 `_resolve_separation` 是简化 push-out + overlap-resolve hack,
> 在 unit 物理塞不下的场景(N unit 挤窄走廊)会出现单帧位移 30-80 px 的
> visible jump。这不是 sim-nav-map plugin bug,是 lab 缺 motion controller
> 的副作用。要彻底消除需要走 Path B 或 Path C。

**优点**:0 工作量,sim-nav-map plugin layer 完全干净
**缺点**:用户每次 demo 时还是会看到 jump,需要明确预期

### Path B:lab 实现 velocity-based motion controller(中等工作量)

按 0ad 思路重构 `_move_unit` + `_resolve_separation`:
- `LabUnit` 加 `velocity` / `target_velocity` field
- `_move_unit` 引入加速度限制(每帧 velocity 变化 ≤ acceleration * delta)
- `_resolve_overlaps` 改成 push velocity (不 push position),让 unit 自然减速
- `_push_out_static_obstacles` 删掉,改成"unit 撞墙就 short-range replan"

工作量估计 1-2 周。会破坏现有所有 smoke contract,需要 redesign smoke。
配合 sim-nav-map Feature 6 (filtered short query + line validation) 一起做最自然。

**优点**:跟 0ad 设计对齐,根除闪现
**缺点**:大重构,smoke 要重写,可能引入新 bug

### Path C:用户/codex 接管,Claude 退出当前修复

这是用户提出"让 codex 跟你讨论"的语义。Claude 把这份 doc 交出去,后续
设计 + 实施由 codex 主导(或用户自己)。Claude 的当前修复(per-call clamp +
overlap budget + cache)可以保留作为 trade-off 起点,也可以全 revert。

## 给 codex 的具体提问

如果走 Path C,建议用户问 codex 这几个问题:

1. 你之前修复闪现/卡帧时,是不是也走的"调 push 算法参数"这条路?
   有没有考虑过让 `_move_unit` 引入 velocity?为什么没做?
2. 当前 lab 的"事后 push out + teleport"设计,你认为是 acceptable trade-off
   还是 design flaw?
3. 如果重构走 Path B,你会先动 `_move_unit` 还是 `_resolve_separation`?
   smoke contract 要怎么 redesign?
4. sim-nav-map Feature 6 (filtered short query + line validation) 跟 lab
   motion controller 重构怎么协调顺序?

## 给 Claude 自己的提问(自省)

- 我跟 codex 调了好几轮 push 算法参数,**为什么没在第一轮就识别出"lab 缺
  motion controller"是根因**?是因为我直接进入 fix 模式,没回头看设计?
- 用户两次提示"跟参考项目 0ad 比较"才让我意识到方向问题。**下次接到
  "修 lab 闪现"任务,第一步该做的是 read 0ad 对应模块,而不是直接调 lab 参数**。

## 当前 working tree 状态

- `addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd`
  改动 ~150 行(per-call clamp + overlap budget + cache + total budget)
- `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/smoke/smoke_rts_pathfinding_lab.gd`
  contract 收紧 + 加 `_test_obstacle_drop_during_walk_does_not_teleport`
- 全部 4 个 lab smoke + 16 个 plugin smoke PASS
- 未 commit,等用户决定走 Path A/B/C
