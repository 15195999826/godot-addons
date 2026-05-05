# RTS pathfinding baselines

Archived baseline trace + replay snapshot for the old RTS private pathfinder
fixture. Production pathfinding now goes through `RtsPathfinderFacade`, which
delegates to `addons/sim-nav-map`.

This directory remains compatibility evidence for historical RTS behavior. It is
not the active stabilization gate for new `sim-nav-map` work. Use these groups
instead:

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## 文件清单

| 文件 | 内容 | 何时刷新 |
|---|---|---|
| `0ad-baseline-master.csv` | `path_trace_v2` 24 字段 trace, 跑 `smoke_pathfinding_baseline` 30s 战斗逐 tick 写一行/alive actor | 仅在 M0 起点跑一次落地;后续 milestone **不刷新**,作为 bit-identical diff 参照 |
| `0ad-baseline-master.replay.json` | `RtsAutoBattleProcedure.finish()` 返回 record dict 的 JSON 序列化 (含 timeline events + player_commands + rng_seed) | 同上 |

## 用途

- **M5 / M7 验证**: 跑同 smoke,产出新 trace,与本目录 baseline 做 byte-identical diff;
  任何不一致 = 寻路 / 行为决定性破坏,milestone 不通过。
- **replay 重放**: replay JSON 可被 LGF `ReplayPlayer` 加载重放,验证录像系统改动后行为不漂。

## 如何刷新 baseline

⚠️ **仅在 M0 起点 / M3 epic 启动前跑一次,后续 milestone 不刷**(刷了就失去对照价值)。

1. 跑 baseline smoke,产出 trace + replay 到 `user://`:
   ```
   godot --headless --path . addons/logic-game-framework/example/rts-auto-battle/tests/battle/smoke_pathfinding_baseline.tscn
   ```
2. 找到 `user://` 真实路径(Windows 通常是 `%APPDATA%/Godot/app_userdata/Inkmon/`),
   把生成的两个文件 copy 到本目录:
   ```
   %APPDATA%/Godot/app_userdata/Inkmon/0ad-baseline-master.csv  →  此目录/0ad-baseline-master.csv
   %APPDATA%/Godot/app_userdata/Inkmon/0ad-baseline-master.replay.json  →  此目录/0ad-baseline-master.replay.json
   ```
3. submodule 内 git add + commit。

## Schema

CSV 字段顺序见 `tools/path_trace_v2.gd` 头部注释。M0 阶段部分字段填占位 (`-1` 或 `""`),
M1..M7 各 milestone 把对应字段填实(字段顺序不许动,只许把占位 → 实值)。

## Bit-identical diff 注意事项

- **CSV** 是 bit-identical 主参照(同 `rng_seed=42` 跑两次产物 byte-for-byte 一致;
  实测 baseline smoke 二次跑 = 主跑 byte-equal)
- **replay JSON** 内 `meta.battleId` / `meta.recordedAt` 跨 run 不同(stdlib
  `BattleRecorder` 用的 instance 计数 + wallclock),timeline + player_commands +
  rng_seed 字段才是 deterministic 部分。后续 milestone 跑 diff 时应剥掉 `meta` 字段
  (e.g. `jq 'del(.meta)' a.json | diff - <(jq 'del(.meta)' b.json)`)再做对照
