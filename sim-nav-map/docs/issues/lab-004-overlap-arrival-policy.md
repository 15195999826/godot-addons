# LAB-004: Overlap / arrival policy is fragile

- Status: resolved
- Severity: P2
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `9c7810f`
- smoke: `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.tscn` (default arrival lock-in) + new `repro/repro_lab_004b_overlap_adversarial.tscn` (edge-adjacent target + obstacle edits during arrival), both registered under `rtslab/smoke`.
- 0 A.D. files checked: n/a (lab policy)
- Fix:
  1. Documented the overlap matrix as a comment block above `ARRIVE_MAX_OVERLAP` in `rts_pathfinding_lab_world.gd`: active-vs-active bounded by `OVERLAP_PUSH_MAX_PER_FRAME_CELLS · cell_size` per unit per frame; active-vs-idle resolves through static-escape and `_settle_idle_unit`; idle-vs-idle ≤ `ARRIVE_MAX_OVERLAP` (1.0 px) — enforced by `_unit_max_overlap` gating in `_update_active_move_settle` (~line 509) and by `_is_better_static_exit`'s `candidate_is_clear` check.
  2. Wrote the adversarial smoke `repro_lab_004b_overlap_adversarial.gd`: scripts the codex Issue 4 stress case (edge-adjacent target near (640, 36), obstacles dropped at step 40 / step 80 to crowd the approach), runs 460 ticks total, and asserts (a) `max_active_pair_overlap ≤ 6.0 px` mid-flight and (b) `max_idle_pair_overlap ≤ ARRIVE_MAX_OVERLAP` for any unit that reached idle. The smoke deliberately does NOT assert arrival — edge-adjacent + obstacle-edited targets are intentionally hostile to arrival (LAB-001 / LAB-003 territory). What this smoke locks in is the overlap matrix, regardless of whether the units finish arriving.
  3. Registered the existing default-arrival lock-in (`repro_lab_004`) plus the new adversarial (`repro_lab_004b`) under `rtslab/smoke` so any future regression on either case flips the matrix red.
- baseline impact: none (LAB-004 was already lock-in correct at HEAD; this issue documents the matrix and locks it in via two regression smokes).
- public-api.md: no change.

## Symptoms

Earlier stress logs had ~2px overlap between arrived idle units (e.g.
`blue_4` and `blue_5`). The latest fix narrowed the idle-idle skip so
small arrived overlap is allowed only when within
`ARRIVE_MAX_OVERLAP`, but broader arrival packing still needs review.

## Current read

Lab policy. Core can provide path / collision primitives, but the lab
decides how many units may settle around the same command point and
when overlap is acceptable.

Treat overlap and active jump as coupled movement-policy problems. In
crowded or narrow-space cases, aggressive overlap resolution can push a
unit into an inflated static obstruction; the current static-escape
fallback may then teleport it out. A fix that only tightens overlap
thresholds can make jump behavior worse, and a fix that only caps jumps
can leave units stuck inside static blockers. Resolve the policy as a
matrix of allowed resting overlap, active separation, and static-block
response.

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
- Source note: seeded from prior Codex discussion; active tracking is this issue.
