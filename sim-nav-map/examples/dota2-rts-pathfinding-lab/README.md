# Dota2 RTS Pathfinding Lab

> **Status: LAYER 1 IMPLEMENTED.** The manual frontend, motion FSM, and smoke
> tests exist. Layer 2 AI control is still frozen until Layer 1 is approved.

This lab is the planned Dota2/LoL-style movement-policy example for
`sim-nav-map`. Dota2 is strictly a MOBA, but its pathfinding problem belongs to
the same family as RTS pathfinding (continuous-space movement on a navigation
grid, with dynamic and static obstacles), so the lab name follows the
`*-rts-pathfinding-lab` convention used by `0ad-rts-pathfinding-lab`.

## Three-Lab Complexity Gradient

| Lab | Collision policy | Command model | Algorithmic pressure point | Target unit density |
|---|---|---|---|---|
| `0ad-rts-pathfinding-lab` | hard + push pressure dynamics | individual, with formation commands | per-frame push force solver | 100–300 |
| `sc2-rts-pathfinding-lab` (planned) | hard, no push | group / cluster commands | command-level cluster pathfinding | 20–100 |
| **`dota2-rts-pathfinding-lab`** (this lab) | hard, no push | individual per unit | none — low density solves it | 10–40 |

The three labs are intentionally **independent**: they share `sim-nav-map` core
(long path / vertex path / obstruction / LoS) but their `logic/` directories do
**not** share base classes. The motion abstraction point differs too sharply
between paradigms to be unified.

## Motion Contract (Dota2 paradigm)

- **Collision = hard block all units, including allies.** A unit cannot occupy
  the same cell as another unit. No phasing / friendly walk-through.
- **No push at all.** When a unit attempts to step into an occupied cell, it
  stops. No separation force, no pair-wise dynamics. *This is the key
  difference from* `0ad-rts-pathfinding-lab` *— the entire push pressure
  subsystem is omitted.*
- **Bumped-then-repath.** When a step is blocked, the motion controller issues
  a vertex short-path request toward the move order target. No sliding along
  obstacles — the short path is a fresh vertex query.
- **No formation movement, no cluster pathfinding, no destination packing.**
  Each unit has its own move order; the command source (mouse / AI) sets it
  per unit.

Motion controller LOC estimate: **~200–300 lines** (vs.
`zero_ad_rts_lab_motion_controller.gd` at 1406 lines).

## Two-Layer Architecture

This lab runs in two phases:

```text
                 dota2-rts-pathfinding-lab
                            │
            ┌───────────────┴───────────────┐
            │                               │
       Layer 1 (manual)              Layer 2 (AI control)
       frontend/                     ai/    [not started]
            │                               │
            └───────────────┬───────────────┘
                            │
                  shared logic/ (motion / collision / pathfind)
```

**Layer 1 is the current scope.** It exists to:

- Let the developer **probe edge cases manually** (intentional narrow-gap
  insertion, target-switching spam, body-blocking own units) — things an AI
  controller would never test on its own.
- Validate **handling/feel** that can only be judged visually (response
  latency, stop precision, turn smoothness).
- Build a `tests/smoke/` regression set from cases discovered during manual
  play.

**Layer 2 is frozen** until Layer 1 is approved by the user. The MOBA
auto-battle end-game (every unit has an AI-decided move order, collision /
motion / pathfind unchanged) corresponds to Layer 2.

**Layer separation rule (write into every motion source file):**

> `logic/` must not know whether its `move_to(unit, target)` caller is a
> human or an AI. Layer 2 may only call public command APIs; it may not edit
> `logic/` internals.

## Layer 1 Approval Criteria

Layer 1 is "OK" — and Layer 2 may then start — when **all** of the following
hold:

1. **No deadlock.** Run any scene for N ticks; no unit gets permanently stuck.
2. **Bumped → repath.** When a unit's step is blocked by another unit, a vertex
   repath is issued; the unit eventually reaches an alternative cell or
   registers a clean move-failure.
3. **Target-switch smoothness.** Rapidly re-issuing move orders to a different
   target does not produce path-thrash or position-jitter.
4. **Narrow-gap behavior.** Forcing a unit toward a gap blocked by two other
   units produces deterministic, non-flickering behavior (either route around,
   or stop).
5. **Mixed static + dynamic obstacles.** A scene with a static obstruction and
   dynamic units near it produces reachable paths from the vertex pathfinder,
   not infinite repath loops.

**Plus**: every corner case the developer discovers during manual play must be
converted to a scripted smoke in `tests/smoke/`. "I played it, looked fine" is
not acceptable; the regression set must capture it.

## Directory Layout

```text
dota2-rts-pathfinding-lab/
├── README.md                          (this file)
├── docs/
│   └── (design notes, when needed)
├── logic/
│   ├── dota2_lab_world.gd
│   ├── dota2_lab_unit.gd
│   ├── dota2_lab_motion_controller.gd
│   ├── dota2_lab_move_order.gd
│   └── dota2_lab_pathfinder_wrapper.gd
├── frontend/
│   ├── dota2_pathfinding_lab.tscn
│   └── dota2_pathfinding_lab.gd
├── ai/                                (empty until Layer 2)
└── tests/
    ├── test_groups.json
    ├── smoke/
    │   └── (Layer 1 regression smokes)
    └── ai_smoke/                      (empty until Layer 2)
```

## Controls (follows `0ad-rts-pathfinding-lab` conventions)

- `1`: command mode. Left-click selects, drag selects, right-click moves the
  current selection. No selection ⇒ moves all mobile units.
- `2`: place static obstacle.
- `3`: place non-mobile blocker unit.
- `4`: erase the nearest editable obstacle / blocker.
- `A`: select all mobile units.
- `C`: clear traces.
- `E`: export a JSON debug snapshot.
- `R`: reset scene.
- `Space`: pause / resume simulation.
- `Export log` button: write a JSON debug snapshot to
  `user://dota2_rts_pathfinding_lab_logs/`.

## Debug Surface

The frontend HUD and export log intentionally mirror the 0AD lab where useful:

- `world.step` last/avg/max timings and slow-frame count.
- state counts, long/short path request counts, queue pending/result/processed,
  retry max, reached/failed counters.
- failed-unit line plus red ring / `X` glyph on failed units.
- grid, obstacle clearance overlay, placement preview, current target marker,
  movement traces, selected path waypoints, and drag-select rectangle.
- 1320x900 manual-test map with a fixed right-side debug sidebar, sized for
  the project's default 1920x1080 window.
- JSON export snapshot with scene state, perf counters, world metrics,
  pathfinder queue diagnostics, obstacles, units, recent frontend events,
  recent motion updates, and slow frames.

## DevAgent Debug Mode

`frontend/dota2_pathfinding_lab.tscn` has an opt-in DevAgent adapter for live
manual debugging. Normal scene behavior is unchanged unless DevAgent is enabled
with `--dev-agent`, `--dev-agent-session=<id>`, or the
`debug/dev_agent/enabled` project setting.

Run the scene in editor/windowed Godot when visual evidence matters, then use
the printed paths:

```text
[Dota2PathfindingLab DevAgent] inbox: C:\...\user_data\Inkmon\dev-agent\sessions\<session-id>\inbox.jsonl
[Dota2PathfindingLab DevAgent] outbox: C:\...\user_data\Inkmon\dev-agent\sessions\<session-id>\outbox.jsonl
```

Append one JSON object per line to `inbox.jsonl`:

```jsonl
{"id":"dota2-001","op":"capture","label":"initial"}
{"id":"dota2-002","op":"inspect_controls","label":"controls"}
{"id":"dota2-003","op":"tap_key","key":"2"}
{"id":"dota2-004","op":"click_at","x":1040,"y":450}
{"id":"dota2-005","op":"tap_key","key":"1"}
{"id":"dota2-006","op":"drag_at","from_x":90,"from_y":350,"to_x":285,"to_y":550,"steps":8}
{"id":"dota2-007","op":"click_at","x":1160,"y":450,"button":"right"}
{"id":"dota2-008","op":"scene","name":"dump_scene_state"}
{"id":"dota2-009","op":"scene","name":"export_debug_log"}
```

Raw bridge operations remain available: `click_at`, `drag_at`, `tap_key`,
`wait_frames`, `capture`, `inspect_tree`, `inspect_controls`, and `dump_node`.
Scene-specific ops are intentionally small:

- `dump_scene_state` — returns compact lab state, selected units, perf counters,
  world metrics, and pathfinder diagnostics in `outbox.jsonl`.
- `export_debug_log` — writes the existing full JSON debug export and returns
  the global artifact path in `outbox.jsonl`.

## Smoke

```powershell
./tools/run_tests.ps1 dota2lab/smoke
```

The smoke group covers both motion state-machine contracts and frontend
operations: obstacle/blocker/erase, select-all, drag-select, move command,
clear traces, and export-log shape.

## Motion Rules Are Lab-Defined

This lab does **not** consume an external pathfinding reference. The Dota2
paradigm is simple enough — hard block + no push + stop + vertex repath — that
the motion rules can be authored from first principles against `sim-nav-map`
core, without porting or paraphrasing any upstream implementation.

When motion-rule decisions need to be recorded, write them to
`docs/design-notes/` in this lab. Do not introduce new external pathfinding
references without explicit re-evaluation.

## Out of Scope (Things This Lab Will Not Do)

- Formation movement (use `sc2-rts-pathfinding-lab` for that).
- Push pressure / dynamics (use `0ad-rts-pathfinding-lab` for that).
- Cluster / group pathfinding.
- Phasing / friendly walk-through (allies are hard blockers, just like
  enemies).
- Destination packing.
- Replication of any specific Dota2 game mechanic (items, abilities, heroes,
  vision) — this is a *pathfinding* lab.
