# sim-nav-map Baseline (2026-05-07)

This is the addon state below which any change must not regress. Numbers
worse than this table or smoke that drops out of the matrix is a regression
and blocks merge until either fixed or this file is updated with explicit
justification.

## Repository state

- Main branch: `master`
- Pinned commit (main repo): `6335f32` — *Record sim nav core feature completion*
- Addons submodule: same baseline as the pinned commit's `addons/` pointer

## Smoke matrix (must stay green)

Both groups green at baseline:

```powershell
./tools/run_tests.ps1 simnav/smoke
./tools/run_tests.ps1 rtslab/smoke
```

For the canonical entries see [`../smoke-matrix.md`](../smoke-matrix.md).

## Public API surface

Stable surface as of baseline is documented in
[`../public-api.md`](../public-api.md). Any issue fix that changes that
surface must update `public-api.md` in the same PR and call out migration
notes in the issue's "Resolution" section.

## Lab metrics

Source: latest `rtslab/smoke` representative results recorded during the
2026-05-07 core feature completion review. The active follow-up items are
the linked issues below.

| Metric | Baseline | Target / target issue |
|---|---|---|
| `default` avg_step_usec | ~450–480 | ~100 ([LAB-001](lab-001-default-avg-step.md)) |
| stress vertex_usec spike (pre-gating) | 26–37 ms | resolved by gating |
| stress grid/long-path spike (post-gating) | 10–15 ms | reduce ([LAB-002](lab-002-stress-long-frames.md)) |
| `max_any_jump` | ~55 px | navcell-bounded ([LAB-003](lab-003-active-jump-55px.md)) |
| arrived idle overlap | ≤ `ARRIVE_MAX_OVERLAP` | hold ([LAB-004](lab-004-overlap-arrival-policy.md)) |

Useful log markers in `rtslab/smoke`:

- `RTS_PATHFINDING_LAB_METRICS`
- `RTS_PATHFINDING_LAB_STEP_PERF`

Primary log file:

```text
.claude/tmp/test-runs/addons__sim-nav-map__examples__rts-pathfinding-lab__tests__smoke__smoke_rts_pathfinding_lab.log
```

## Known correctness limits

Baseline ships with these incorrect behaviors. Each is tracked as a P0/P1
issue. A fix must include a smoke that proves the new correct behavior — do
not just patch silently.

- [CORE-002](core-002-long-path-los-sampling.md) — long-path LOS refinement may keep a corner-crossing segment
- [CORE-004](core-004-set-bounds-missing.md) — out-of-bounds query/rasterize behavior undefined
- [CORE-005](core-005-clearance-extension-radius.md) — long-path is not +1 navcell more conservative than short-path

## Regression protocol

When an issue is resolved:

1. Re-run both smoke groups.
2. Re-record any metric in the lab table above that moves (in either direction).
3. If a baseline number changes (better or worse), update this file in the
   same PR. Worse numbers must be justified in the issue's "Resolution".
4. If a smoke entry is added, update [`../smoke-matrix.md`](../smoke-matrix.md).
5. If public API changes, update [`../public-api.md`](../public-api.md).
