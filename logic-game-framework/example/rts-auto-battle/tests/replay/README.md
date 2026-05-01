# tests/replay/ — RTS 决定性 / 录像验收 smoke

| 文件 | 用途 |
|---|---|
| `smoke_determinism.tscn` | P1.7 light determinism: 同 seed 跑 2 次 → 同 winner + 同 total_ticks ± 1 |

## 历史

- **Phase 1 P1.7**: 加 `smoke_determinism` 验证 RtsRng autoload + procedure rng_seed 写入 world_snapshot 的链路
- **Phase 2 P2.6+P2.7**: 计划加 `smoke_replay_bit_identical` 验证完整流式 event_timeline replay (player_commands 接入后)
