# LAB-005: Command target vs path target separation

- Status: resolved
- Severity: P2
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `fe722b4`
- smoke: `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.tscn` (registered under `rtslab/smoke` group as a lock-in smoke)
- 0 A.D. files checked: n/a (lab semantic naming, no 0 A.D. analogue)
- Fix:
  1. Added docstring on `RtsPathfindingLabUnit.target` (= user click + formation slot, read by frontend command markers / group intent UI) and `RtsPathfindingLabUnit.path_target` (= canonical reachable stop point the current path is actually trying to reach; arrival, stuck detection, replan triggers, and final-error metrics read this). Docstrings explicitly call out the "MUST NOT be merged" invariant and link this issue.
  2. Audited `examples/rts-pathfinding-lab/frontend/`: the only target-side draw is `draw_circle(_world.current_target, ...)` in `rts_pathfinding_lab.gd` (group-level command marker, correctly reads command intent). No frontend renders `unit.path_target` as a marker. The diagnostics export at `frontend/rts_pathfinding_lab.gd:322-323` and `:374-375` exposes both fields with their distinct names — no merging.
  3. Registered the existing lock-in smoke under `rtslab/smoke` so any future change that re-merges the two fields flips the matrix red.
- baseline impact: none (LAB-005 was already correct at HEAD; this issue locked the invariant in via smoke + docstrings).
- public-api.md: no change. The lab unit script is example-side and not part of `sim-nav-map`'s public API surface.

## Symptoms

The lab previously rewrote `unit.target` to `reachable_goal` when
`used_make_goal_reachable` was true, mixing user command target, UI
target marker, formation slot, and canonical reachable stop point. That
made several subsequent decisions ambiguous (which "target" does
arrival use? which does the marker render?).

## Current state

- `unit.target` should mean the user command / formation slot.
- `unit.path_target` should mean the reachable / canonical stop point
  that the current path is actually trying to reach.
- Future changes must not merge these meanings again.

## Investigation backlog

- Re-test unreachable clicks and clicks inside / behind obstacles.
- Confirm the frontend command marker reads the command target, not
  the canonical path target.
- Confirm path completion, final error, stuck detection, and debug
  export use `path_target` when they evaluate actual movement
  completion.

## Proposed approach

This issue is "hold the line". The current state is correct; the work
is to lock it in with smoke and clear documentation:

1. Extend `rtslab/smoke` with a regression that:
   - Issues a command to an unreachable point (inside a static OBB).
   - Captures `unit.target` and `unit.path_target` after the lab
     canonicalizes.
   - Asserts they differ as expected (target == click, path_target ==
     canonical).
   - Asserts arrival is judged against `path_target`, not `target`.
2. Add a comment / docstring on the unit script that says these two
   fields must not be merged. Reference this issue ID.
3. If the frontend command marker exists in `frontend/`, audit which
   field it reads.

## Verify before fixing

- [ ] Audit current code paths to confirm the separation is intact
- [ ] Decide whether `target_canonical` would be a clearer name than `path_target` (do not rename without reason; just consider)

## Repro at HEAD (LOCK-IN)

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.gd).

**This is a LOCK-IN smoke**, asserting the current correct separation:

- `unit.target` = the user click + formation slot (tracks the command)
- `unit.path_target` = the canonical reachable stop point (tracks the path)

Setup: `setup_default()`. Command all 6 blue units to (340, 210), which
is dead-center inside the default `stone_block` obstacle (so the click
is unreachable). Step 20 ticks to let canonicalization run. For each
unit assert `target ≠ path_target` (> 0.5 px apart) and
`distance(target, original_click) ≤ 60 px` (target follows the command,
not the canonical path).

At HEAD (commit 6335f32) the smoke PASSes:

```text
LAB-005 separation: checked 6 units, 6 had target ≠ path_target (>0.5 px apart)
SMOKE_TEST_RESULT: PASS - LAB-005 target vs path_target separation locked in
```

**Stability**: 5/5 runs **byte-identical** — 6/6 units separated every
time.

## Regression after fix

This smoke is the regression guard. Any change that merges
`unit.target` and `unit.path_target` back into one field, or that snaps
`unit.target` onto the canonical reachable point, flips this smoke to
FAIL.

## Cross-refs

- [LAB-004](lab-004-overlap-arrival-policy.md) — arrival uses path_target
- [LAB-003](lab-003-active-jump-55px.md) — fallback target changes are one
  attribution category for large jumps
- Source note: seeded from prior Codex discussion; active tracking is this issue.
