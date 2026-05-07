# LAB-004: Overlap / arrival policy is fragile

- Status: open
- Severity: P2
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07

## Symptoms

Earlier stress logs had ~2px overlap between arrived idle units (e.g.
`blue_4` and `blue_5`). The latest fix narrowed the idle-idle skip so
small arrived overlap is allowed only when within
`ARRIVE_MAX_OVERLAP`, but broader arrival packing still needs review.

## Current read (from rts-lab-open-issues.md Issue 4)

Lab policy. Core can provide path / collision primitives, but the lab
decides how many units may settle around the same command point and
when overlap is acceptable.

## Investigation backlog

- Audit `ARRIVE_MAX_OVERLAP`, arrival radius, formation slot spacing,
  and near-target settling together.
- Separate acceptable visual resting overlap from actual collision
  overlap.
- Stress-test cases where multiple units reach a blocked or
  edge-adjacent target.
- Keep arrived-idle behavior stable without disabling active separation.

## Proposed approach

1. Document the intended overlap matrix (active-active, active-idle,
   idle-idle) with one acceptance threshold per pair.
2. Express thresholds as named constants (`ACTIVE_*`, `IDLE_*`) in one
   place, not scattered through `_resolve_*` methods.
3. Add smoke that drives N units to one command target and asserts the
   overlap matrix in the resting state.

## Verify before fixing

- [ ] Confirm the overlap matrix above captures every interaction the
  lab cares about (e.g. unit-vs-static is separate)
- [ ] Decide whether "formation slot spacing" is an input to the policy
  or an emergent property — they are not the same thing

## Repro at HEAD (LOCK-IN)

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.gd).

**This is a LOCK-IN smoke, not a bug-exposure.** The codex Issue 4 stress
scenario previously produced ~2 px arrived-idle overlap. The latest fix
narrowed `ARRIVE_MAX_OVERLAP` so the *default* arrival case no longer
reproduces the problem. The smoke runs the default arrival and asserts
no pair exceeds 1 px overlap, locking the win in.

Setup: `setup_default()`, command all 6 mobile blue units to (610, 210),
step until `all_mobile_arrived()` (~380 ticks) plus 30 settle ticks.
For every pair, assert `max(0, sum_radii - dist) ≤ 1.0`.

At HEAD (commit 6335f32) the smoke PASSes:

```text
LAB-004 overlap: arrived_at_step=380, max_pair_overlap=0.00 px on  (target ≤ 1.0 px)
SMOKE_TEST_RESULT: PASS - LAB-004 default arrival overlap stays bounded
```

**Stability**: 5/5 runs **byte-identical** — arrival at step 380, max
overlap exactly 0.00 px. Default arrival is fully deterministic.

**Adversarial scenario still pending.** The codex Issue 4 stress case
(rapid obstacle edits during arrival, edge-adjacent target,
blocker-near-target packing) is not yet expressed as a smoke. When that
adversarial scenario is constructed, add `repro_lab_004b_*` next to this
file.

## Regression after fix

This smoke is the regression guard. If a future change brings back > 1 px
arrived overlap on the default scenario, this flips to FAIL.

## Cross-refs

- [LAB-003](lab-003-active-jump-55px.md) — overlap resolution can cause jumps
- [LAB-005](lab-005-command-vs-path-target.md) — the "command target" referred to here means the user click, not the canonical path target
- Original discussion: `../rts-lab-open-issues.md` Issue 4
