# LAB-003: Active position jump can hit ~55px

- Status: open
- Severity: P1
- Layer: lab
- Source: codex-discussion
- Created: 2026-05-07

## Symptoms

Smoke / debug logs have shown `max_any_jump ~= 55px`. A previous attempt
to cap static push per frame reduced jump symptoms but caused active
obstacle violations, so a simple movement cap is not sufficient.

## Current read

Likely lab movement / separation policy unless a core query says a
point is passable while it is actually inside an obstruction. The risky
area is how movement, overlap resolution, static obstacle escape,
arrival settling, and re-path decisions interact in one frame.

The important design conclusion from the earlier separation discussion
is preserved here: the visible jump is caused by the lab's simplified
post-hoc fixup model, not by a proven `sim-nav-map` core contract bug.
The lab currently combines direct position interpolation, overlap pushes,
and `_push_unit_out_of_static_component()` nearest-exit escape. 0 A.D.'s
UnitMotion-style reference validates movement/pushes and cancels invalid
adjustments instead of teleporting a unit out of an obstacle. A real fix
should move toward "validate, cancel/repath, then continue" rather than
tuning the teleport distance.

## Investigation backlog

Read these lab methods together:

- `_move_unit()`
- `_resolve_separation()`
- `_resolve_overlaps()`
- `_settle_idle_unit()`
- `_finish_move_order()`

For any large jump, log the cause: movement, separation push, static
obstacle escape, arrival snap, or fallback path target change. Do not
add a hard displacement cap unless the capped position is also checked
against static obstacles and unit overlap invariants. Consider a
UnitMotion-like rule: if a step cannot be validated, cancel, reduce, or
re-path instead of teleporting to satisfy separation.

## Proposed approach

1. Add per-step jump attribution: tag each large `Δposition` with the
   originating call (movement vs separation vs escape vs arrival vs
   re-path). Log at threshold (e.g. > 1 navcell).
2. Apply [PROCESS-001](process-001-core-lab-proof-protocol.md): for
   each attribution category, build a minimal core-only repro before
   blaming or fixing core.
3. If movement/separation: prefer "cancel and re-path" over "teleport
   to satisfy separation". The lab should be able to fail-safe.
4. If static-escape: investigate whether long-path is producing
   waypoints the short-path then refuses (couples to
   [CORE-005](core-005-clearance-extension-radius.md) and
   [CORE-002](core-002-long-path-los-sampling.md)).

## Verify before fixing

- [ ] Confirm the 55px observation is reproducible (it is logged but the exact step is not always pinned)
- [ ] Decide hard limit: e.g. "no single-frame jump > 1 navcell except for verified arrival snap" — lock in BASELINE

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_003_max_jump.tscn
```

Smoke: [`examples/rts-pathfinding-lab/tests/repro/repro_lab_003_max_jump.gd`](../../examples/rts-pathfinding-lab/tests/repro/repro_lab_003_max_jump.gd).

**Setup note**: the BASELINE-reported 55 px jump does not reproduce in
the *default* lab scenario — running default for hundreds of ticks shows
max < 5 px. The provoking situation is a static obstacle landing on top
of a mobile unit, forcing the static-escape system to extricate it on
the next step. The smoke scripts that scenario explicitly:

- `setup_default`. Step 20 ticks to let blue_0 enter motion.
- Capture blue_0's current position. Drop a 60×60 static obstacle
  centered there.
- Step 120 more ticks. Track per-tick world-space delta for every
  mobile unit. Threshold ≤ 16 px (2 navcells).

At HEAD (commit 6335f32) the smoke FAILs:

```text
LAB-003 static-escape max_any_jump_px = 41.50 (unit=blue_0, step=0, target ≤ 16.0)
SMOKE_TEST_RESULT: FAIL - LAB-003 reproduces: max single-step displacement = 41.50 px on unit blue_0 at step 0, exceeds target ≤ 16.0
```

**Stability**: 5/5 runs **byte-identical** — `41.50 px on blue_0 at step 0`
every time. The static-escape jump is fully deterministic.

The 41.50 px ≈ 5 navcells displacement happens on the very first step
after the obstacle drop — the escape system teleports the unit out of
the inflated obstacle in one tick rather than repathing.

## Regression after fix

After LAB-003 fix (jump-attribution + capped escape per step, or
"replan rather than teleport"), the smoke flips to PASS. Add a follow-up
smoke that asserts every large jump carries an attribution tag and falls
in an allowed category.

## Cross-refs

- [LAB-004](lab-004-overlap-arrival-policy.md) — overlap and arrival are part of the same movement-policy story
- [CORE-005](core-005-clearance-extension-radius.md) — long-vs-short hand-off invariant
- [CORE-002](core-002-long-path-los-sampling.md) — corner-crossing waypoint can cause an escape jump
- [PROCESS-001](process-001-core-lab-proof-protocol.md)
- Source note: seeded from prior Codex discussion; active tracking is this issue.
