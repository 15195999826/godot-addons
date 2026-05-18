# Tests (M1 implemented)

> M1 已落地：`./tools/run_tests.ps1 dota2autobattle/smoke` →
> `battle/smoke_lane_wave_engage.tscn` + `frontend/smoke_frontend_main.tscn`
> (`test_groups.json` namespace `dota2autobattle`，组 `smoke` + `regression`
> required)。变更见 [../CHANGELOG.md](../CHANGELOG.md)。下列为原始规划。

Planned smoke targets:

- `battle/smoke_lane_wave_engage.tscn`: waves spawn, meet, attack, damage, and
  death or sustained combat is observed.
- `frontend/smoke_frontend_main.tscn`: visible scene loads and creates expected
  world/unit views.

No test group is registered yet.
